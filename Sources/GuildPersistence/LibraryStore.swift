import Foundation
import CryptoKit
import Darwin
import CSQLite
import GuildCore

public struct SearchHit: Identifiable, Sendable, Equatable {
    public let id: ID
    public let label: String
    public let kind: String
    public let snippet: String
    public init(id: ID, label: String, kind: String, snippet: String) {
        self.id = id; self.label = label; self.kind = kind; self.snippet = snippet
    }
}

public enum LibraryStoreError: Error, LocalizedError {
    case database(String)
    case unsupportedSchema(Int)
    case invalidData(String)
    case corruptSource(String)
    case staleSnapshot
    case staleRevision(ID)

    public var errorDescription: String? {
        switch self {
        case .database(let message): return "Library database: \(message)"
        case .unsupportedSchema(let version): return "Unsupported library schema \(version). Open it with a compatible Writers Guild version."
        case .invalidData(let message): return "Invalid library data: \(message)"
        case .corruptSource(let path): return "Missing, changed, or unreadable source: \(path). The library was not reset."
        case .staleSnapshot: return "Another library store saved changes. Reload before saving; your sources have been preserved."
        case .staleRevision(let id): return "Manuscript \(id) has a newer or conflicting revision. Reload before saving."
        }
    }
}

/// Synchronous, intentionally non-Sendable. Use from one serialized owner.
/// Saves replace a value snapshot, guarded against writes by other store handles.
/// Call load() before editing an existing library. Never pass an older snapshot back
/// through the same owner: Library itself has no generation token.
public final class LibraryStore {
    public let directory: URL
    private let database: SQLiteConnection
    private var generation: Int?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL) throws {
        guard directory.isFileURL else { throw LibraryStoreError.invalidData("Library directory must be a file URL.") }
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let databaseURL = self.directory.appendingPathComponent("library.sqlite3")
        // A missing database beside preserved sources is recovery work, not a new empty novel.
        if !FileManager.default.fileExists(atPath: databaseURL.path),
           FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("sources").path) {
            throw LibraryStoreError.invalidData("Database is missing beside existing sources; restore the database rather than initializing an empty library.")
        }
        guard databaseURL.resolvingSymlinksInPath() == databaseURL else {
            throw LibraryStoreError.invalidData("Database may not be a symbolic link.")
        }
        database = try SQLiteConnection(url: databaseURL)
        try database.execute("PRAGMA foreign_keys = ON")
        try database.execute("PRAGMA journal_mode = WAL")
        try database.execute("PRAGMA synchronous = FULL")
        try migrate()
        let check = try database.statement("PRAGMA quick_check")
        guard try check.step(), check.text(0) == "ok" else {
            throw LibraryStoreError.database("Integrity check failed; no data was reset.")
        }
        // Existing libraries must be loaded before they can be replaced.
        generation = try database.integer("SELECT count(*) FROM records") == 0 ? currentGeneration() : nil
    }

    public func load() throws -> Library {
        try database.execute("BEGIN DEFERRED")
        do {
            let loadedGeneration = try currentGeneration()
            let result = try readLibrary()
            try database.execute("COMMIT")
            generation = loadedGeneration
            return result
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    public func save(_ library: Library) throws {
        try Self.validate(library)
        try database.execute("BEGIN IMMEDIATE")
        do {
            guard let generation, try currentGeneration() == generation else { throw LibraryStoreError.staleSnapshot }
            // Reading sources before writing detects missing/corrupt manuscripts rather
            // than silently replacing them with the caller's possibly empty snapshot.
            let previous = try readLibrary()
            let oldManuscripts = Dictionary(uniqueKeysWithValues: previous.manuscripts.map { ($0.sceneID, $0) })
            for manuscript in library.manuscripts {
                if let old = oldManuscripts[manuscript.sceneID],
                   manuscript.revision < old.revision || (manuscript.revision == old.revision && manuscript != old) {
                    throw LibraryStoreError.staleRevision(manuscript.sceneID)
                }
            }
            // Source revisions are written, synchronized, and never overwritten before
            // any transactional pointer is changed. A failed save leaves harmless orphans.
            let records = try makeRecords(library)
            try database.execute("DELETE FROM records")
            try database.execute("DELETE FROM source_search")
            let insert = try database.statement("INSERT INTO records(kind,id,ordinal,world_id,story_id,scene_id,payload) VALUES(?,?,?,?,?,?,?)")
            for record in records {
                try insert.bind([.text(record.kind), .text(record.id), .integer(record.ordinal), optional(record.worldID), optional(record.storyID), optional(record.sceneID), .blob(record.payload)])
                try insert.finish()
                try insert.reset()
            }
            let searchInsert = try database.statement("INSERT INTO source_search(id,world_id,kind,label,body) VALUES(?,?,?,?,?)")
            let stories = Dictionary(uniqueKeysWithValues: library.stories.map { ($0.id, $0) })
            let scenes = Dictionary(uniqueKeysWithValues: library.scenes.map { ($0.id, $0) })
            for manuscript in library.manuscripts {
                guard let scene = scenes[manuscript.sceneID], let story = stories[scene.storyID] else { throw LibraryStoreError.invalidData("Missing manuscript hierarchy.") }
                try searchInsert.bind([.text(scene.id), .text(story.worldID), .text("manuscript"), .text(scene.title), .text(manuscript.text)])
                try searchInsert.finish(); try searchInsert.reset()
            }
            for lore in library.lore {
                try searchInsert.bind([.text(lore.id), .text(lore.worldID), .text("lore"), .text(lore.title), .text(lore.markdown)])
                try searchInsert.finish(); try searchInsert.reset()
            }
            guard generation < Int.max else { throw LibraryStoreError.invalidData("Library generation overflow.") }
            try database.execute("UPDATE store_metadata SET generation = generation + 1 WHERE singleton = 1")
            try database.execute("COMMIT")
            self.generation = generation + 1
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    /// Literal lexical terms, AND-combined; no arbitrary FTS query syntax is executed.
    /// This retrieves source text only, never authoritative state or agent memory.
    public func search(_ query: String, worldID: ID, limit: Int = 20) throws -> [SearchHit] {
        try Self.validateID(worldID)
        guard limit > 0 else { return [] }
        let terms = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard !terms.isEmpty else { return [] }
        let expression = terms.map { "\"\($0)\"" }.joined(separator: " AND ")
        let statement = try database.statement("SELECT id,label,kind,snippet(source_search,4,'','', ' … ',24) FROM source_search WHERE source_search MATCH ? AND world_id = ? ORDER BY bm25(source_search),kind,id LIMIT ?")
        try statement.bind([.text(expression), .text(worldID), .integer(limit)])
        var result: [SearchHit] = []
        while try statement.step() {
            result.append(SearchHit(id: statement.text(0), label: statement.text(1), kind: statement.text(2), snippet: statement.text(3)))
        }
        return result
    }

    private func migrate() throws {
        try database.execute("BEGIN IMMEDIATE")
        do {
            let version = try database.integer("PRAGMA user_version")
            guard version <= 1 else { throw LibraryStoreError.unsupportedSchema(version) }
            if version == 0 {
                guard try database.integer("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0 else {
                    throw LibraryStoreError.invalidData("Unversioned database already contains tables; refusing to overwrite it.")
                }
                try database.execute("""
                    CREATE TABLE store_metadata(singleton INTEGER PRIMARY KEY CHECK(singleton=1), generation INTEGER NOT NULL);
                    INSERT INTO store_metadata VALUES(1,0);
                    CREATE TABLE records(
                        kind TEXT NOT NULL, id TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0),
                        world_id TEXT, story_id TEXT, scene_id TEXT, payload BLOB NOT NULL,
                        PRIMARY KEY(kind,id), UNIQUE(kind,ordinal)
                    );
                    CREATE INDEX records_world ON records(world_id,kind);
                    CREATE INDEX records_story ON records(story_id,kind);
                    CREATE INDEX records_scene ON records(scene_id,kind);
                    CREATE VIRTUAL TABLE source_search USING fts5(id UNINDEXED, world_id UNINDEXED, kind UNINDEXED, label, body, tokenize='unicode61');
                    PRAGMA user_version = 1;
                    """)
            }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    private func currentGeneration() throws -> Int {
        try database.integer("SELECT generation FROM store_metadata WHERE singleton=1")
    }

    private struct Record {
        let kind: String
        let id: ID
        let ordinal: Int
        let worldID: ID?
        let storyID: ID?
        let sceneID: ID?
        let payload: Data
    }
    private struct SourceFile: Codable { let path: String; let sha256: String }
    private struct StoredManuscript: Codable { let sceneID: ID; let revision: Int; let html: SourceFile; let text: SourceFile }
    private struct StoredLore: Codable { let id: ID; let worldID: ID; let title: String; let markdown: SourceFile }

    private func makeRecords(_ library: Library) throws -> [Record] {
        var records: [Record] = []
        func add<T: Encodable>(_ kind: String, _ value: T, _ id: ID, _ ordinal: Int, world: ID? = nil, story: ID? = nil, scene: ID? = nil) throws {
            records.append(Record(kind: kind, id: id, ordinal: ordinal, worldID: world, storyID: story, sceneID: scene, payload: try encoder.encode(value)))
        }
        let stories = Dictionary(uniqueKeysWithValues: library.stories.map { ($0.id, $0) })
        let scenes = Dictionary(uniqueKeysWithValues: library.scenes.map { ($0.id, $0) })
        func world(_ sceneID: ID) -> ID? { scenes[sceneID].flatMap { stories[$0.storyID]?.worldID } }
        for (i, value) in library.worlds.enumerated() { try add("world", value, value.id, i, world: value.id) }
        for (i, value) in library.stories.enumerated() { try add("story", value, value.id, i, world: value.worldID, story: value.id) }
        for (i, value) in library.scenes.enumerated() { try add("scene", value, value.id, i, world: world(value.id), story: value.storyID, scene: value.id) }
        for (i, value) in library.manuscripts.enumerated() {
            let folder = "manuscripts/\(value.sceneID)"
            let stored = try StoredManuscript(sceneID: value.sceneID, revision: value.revision,
                html: writeSource(value.html, folder: folder, prefix: "r\(value.revision)", extension: "html"),
                text: writeSource(value.text, folder: folder, prefix: "r\(value.revision)", extension: "txt"))
            try add("manuscript", stored, value.sceneID, i, world: world(value.sceneID), story: scenes[value.sceneID]?.storyID, scene: value.sceneID)
        }
        for (i, value) in library.lore.enumerated() {
            let stored = try StoredLore(id: value.id, worldID: value.worldID, title: value.title, markdown: writeSource(value.markdown, folder: "lore/\(value.id)", prefix: "source", extension: "md"))
            try add("lore", stored, value.id, i, world: value.worldID)
        }
        for (i, value) in library.entities.enumerated() { try add("entity", value, value.id, i, world: value.worldID) }
        for (i, value) in library.facts.enumerated() { try add("fact", value, value.id, i, world: value.worldID) }
        for (i, value) in library.events.enumerated() { try add("event", value, value.id, i, world: world(value.sceneID), story: value.storyID, scene: value.sceneID) }
        for (i, value) in library.claims.enumerated() { try add("claim", value, value.id, i, world: world(value.sceneID), story: value.storyID, scene: value.sceneID) }
        for (i, value) in library.agents.enumerated() { try add("agent", value, value.id, i) }
        for (i, value) in library.observations.enumerated() { try add("observation", value, value.id, i, world: world(value.anchor.sceneID), story: scenes[value.anchor.sceneID]?.storyID, scene: value.anchor.sceneID) }
        for (i, value) in library.feedback.enumerated() { try add("feedback", value, value.id, i, world: value.worldID) }
        for (i, value) in library.memories.enumerated() { try add("memory", value, value.id, i, world: value.worldID) }
        for (i, value) in library.reviewRuns.enumerated() { try add("reviewRun", value, value.id, i, world: world(value.sceneID), story: scenes[value.sceneID]?.storyID, scene: value.sceneID) }
        return records
    }

    private func readLibrary() throws -> Library {
        let statement = try database.statement("SELECT kind,id,payload FROM records ORDER BY kind,ordinal")
        var library = Library()
        while try statement.step() {
            let kind = statement.text(0), id = statement.text(1), payload = statement.data(2)
            func decode<T: Decodable>(_ type: T.Type, id key: (T) -> ID) throws -> T {
                let value = try decoder.decode(type, from: payload)
                guard key(value) == id else { throw LibraryStoreError.invalidData("Mismatched \(kind) record identifier.") }
                return value
            }
            switch kind {
            case "world": library.worlds.append(try decode(World.self, id: { $0.id }))
            case "story": library.stories.append(try decode(Story.self, id: { $0.id }))
            case "scene": library.scenes.append(try decode(Scene.self, id: { $0.id }))
            case "manuscript":
                let stored = try decode(StoredManuscript.self, id: { $0.sceneID })
                library.manuscripts.append(try Manuscript(sceneID: stored.sceneID, html: readSource(stored.html), text: readSource(stored.text), revision: stored.revision))
            case "lore":
                let stored = try decode(StoredLore.self, id: { $0.id })
                library.lore.append(try Lore(id: stored.id, worldID: stored.worldID, title: stored.title, markdown: readSource(stored.markdown)))
            case "entity": library.entities.append(try decode(Entity.self, id: { $0.id }))
            case "fact": library.facts.append(try decode(CanonicalFact.self, id: { $0.id }))
            case "event": library.events.append(try decode(StoryEvent.self, id: { $0.id }))
            case "claim": library.claims.append(try decode(NarrativeClaim.self, id: { $0.id }))
            case "agent": library.agents.append(try decode(AgentDefinition.self, id: { $0.id }))
            case "observation": library.observations.append(try decode(AgentObservation.self, id: { $0.id }))
            case "feedback": library.feedback.append(try decode(FeedbackEvent.self, id: { $0.id }))
            case "memory": library.memories.append(try decode(AgentMemory.self, id: { $0.id }))
            case "reviewRun": library.reviewRuns.append(try decode(ReviewRun.self, id: { $0.id }))
            default: throw LibraryStoreError.invalidData("Unknown record kind \(kind).")
            }
        }
        try Self.validate(library)
        return library
    }

    private func writeSource(_ string: String, folder: String, prefix: String, extension suffix: String) throws -> SourceFile {
        let bytes = Data(string.utf8)
        let digest = Self.digest(bytes)
        let relative = "sources/\(folder)/\(prefix)-\(digest).\(suffix)"
        let url = try sourceURL(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == bytes else { throw LibraryStoreError.corruptSource(relative) }
        } else {
            try bytes.write(to: url, options: .atomic)
        }
        // Also synchronize reused files: an earlier failed save may have written
        // this content-addressed orphan without finishing its durability barrier.
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        var parent = url.deletingLastPathComponent()
        while parent.path.hasPrefix(directory.path + "/") {
            try synchronizeDirectory(parent)
            parent.deleteLastPathComponent()
        }
        try synchronizeDirectory(directory)
        return SourceFile(path: relative, sha256: digest)
    }

    private func readSource(_ file: SourceFile) throws -> String {
        let url = try sourceURL(file.path)
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw LibraryStoreError.corruptSource(file.path) }
        guard Self.digest(data) == file.sha256, let string = String(data: data, encoding: .utf8) else { throw LibraryStoreError.corruptSource(file.path) }
        return string
    }

    private func sourceURL(_ path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 4, components[0] == "sources", ["manuscripts", "lore"].contains(String(components[1])),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.allSatisfy { (45...57).contains($0) || (65...90).contains($0) || $0 == 95 || (97...122).contains($0) } }) else {
            throw LibraryStoreError.invalidData("Unsafe source path \(path).")
        }
        let url = directory.appendingPathComponent(path)
        guard url.resolvingSymlinksInPath() == url else { throw LibraryStoreError.invalidData("Source path may not contain symbolic links: \(path).") }
        return url
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func optional(_ value: String?) -> SQLValue { value.map(SQLValue.text) ?? .null }
}

private enum SQLValue { case text(String), integer(Int), blob(Data), null }

private final class SQLiteConnection {
    private var handle: OpaquePointer?
    init(url: URL) throws {
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database."
            if let handle { sqlite3_close_v2(handle) }
            handle = nil
            throw LibraryStoreError.database(message)
        }
        sqlite3_extended_result_codes(handle, 1)
        sqlite3_busy_timeout(handle, 5_000)
    }
    deinit { sqlite3_close_v2(handle) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    func statement(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return SQLiteStatement(connection: self, handle: statement)
    }
    func integer(_ sql: String) throws -> Int {
        let statement = try statement(sql)
        guard try statement.step() else { throw LibraryStoreError.database("Missing required metadata row.") }
        return statement.integer(0)
    }
    func failure() -> LibraryStoreError { .database(String(cString: sqlite3_errmsg(handle))) }
}

private final class SQLiteStatement {
    private let connection: SQLiteConnection
    private let handle: OpaquePointer
    init(connection: SQLiteConnection, handle: OpaquePointer) { self.connection = connection; self.handle = handle }
    deinit { sqlite3_finalize(handle) }
    func bind(_ values: [SQLValue]) throws {
        guard values.count == Int(sqlite3_bind_parameter_count(handle)) else { throw LibraryStoreError.database("Wrong number of SQL parameters.") }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .text(let text):
                guard text.utf8.count <= Int(Int32.max) else { throw LibraryStoreError.invalidData("Text exceeds SQLite binding limit.") }
                code = text.withCString { sqlite3_bind_text(handle, index, $0, Int32(text.utf8.count), transient) }
            case .integer(let integer): code = sqlite3_bind_int64(handle, index, Int64(integer))
            case .blob(let data):
                guard data.count <= Int(Int32.max) else { throw LibraryStoreError.invalidData("Record exceeds SQLite binding limit.") }
                code = data.withUnsafeBytes { sqlite3_bind_blob(handle, index, $0.baseAddress, Int32(data.count), transient) }
            case .null: code = sqlite3_bind_null(handle, index)
            }
            guard code == SQLITE_OK else { throw connection.failure() }
        }
    }
    func step() throws -> Bool {
        switch sqlite3_step(handle) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw connection.failure()
        }
    }
    func finish() throws {
        guard try !step() else { throw LibraryStoreError.database("Unexpected row in write statement.") }
    }
    func reset() throws {
        guard sqlite3_reset(handle) == SQLITE_OK, sqlite3_clear_bindings(handle) == SQLITE_OK else { throw connection.failure() }
    }
    func integer(_ index: Int32) -> Int { Int(sqlite3_column_int64(handle, index)) }
    func text(_ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(handle, index) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(handle, index))), as: UTF8.self)
    }
    func data(_ index: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(handle, index) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, index)))
    }
}
