import Foundation
import XCTest
import GuildCore
@testable import GuildPersistence

final class LibraryStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GuildPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    @MainActor
    func testRealGuildReviewPersistsProseDerivedIdentifiers() async throws {
        let directory = try temporaryDirectory()
        let store = try LibraryStore(directory: directory)
        var library = Greyhaven.make()
        let scene = try XCTUnwrap(library.scenes.first { $0.id == "scene-5" })
        let manuscript = try XCTUnwrap(library.manuscripts.first { $0.sceneID == scene.id })
        let result = try await DeterministicAnalyzer().analyze(ReviewContext(library: library, scene: scene, manuscript: manuscript))
        library.observations = result.observations
        library.claims = result.claims
        XCTAssertTrue(result.observations.contains { $0.category == "STYLE" && $0.anchor.quote.contains("The bell") })
        try store.save(library)
        let reopened = try LibraryStore(directory: directory).load()
        XCTAssertEqual(reopened.observations, result.observations)
        XCTAssertEqual(reopened.claims, result.claims)
    }

    private func fixture() -> Library {
        var library = Library()
        library.worlds = [World(id: "world-z", name: "The Reach"), World(id: "world-a", name: "Elsewhere")]
        library.stories = [Story(id: "story", worldID: "world-z", title: "The Crossing", worldOffset: -20)]
        library.scenes = [Scene(id: "scene", storyID: "story", title: "The Gate", chapter: "Arrival", order: 7, time: 3)]
        let text = "Élise 👩🏽‍🚀 crossed the northern gate.\nPerhaps Rowan was ready.\nA\u{00A0}B e\u{0301} 漢字"
        library.manuscripts = [Manuscript(sceneID: "scene", html: "<h2>Élise 👩🏽‍🚀</h2><p><strong>northern</strong> <em>gate</em><br>Perhaps <s>Rowan</s> <a href=\"https://example.com\">ready</a>.</p><ul><li>A&nbsp;B é 漢字</li></ul>", text: text, revision: 1)]
        library.lore = [Lore(id: "lore", worldID: "world-z", title: "Northern Gate", markdown: "# Northern Gate\n\nÉlise’s **northern** gate is old.\n"), Lore(id: "other-lore", worldID: "world-a", title: "Northern Gate", markdown: "A northern gate in another world.")]
        library.entities = [Entity(id: "rowan", worldID: "world-z", name: "Rowan", aliases: ["Ro"])]
        let anchor = TextAnchor(sceneID: "scene", revision: 1, start: 0, length: 5, quote: "Élise", suffix: " 👩🏽‍🚀 crossed")
        let canonEvidence = EvidenceReference(id: "entity:rowan", kind: "lore", sourceID: "lore", label: "Northern Gate", quote: "Private Rowan")
        let sceneEvidence = EvidenceReference(id: "text:scene:1:0:5", kind: "manuscript", sourceID: "scene", label: "The Gate", quote: "Élise", anchor: anchor)
        library.facts = [CanonicalFact(id: "fact", worldID: "world-z", entityID: "rowan", property: "rank", value: "Private", validFrom: -30, evidence: canonEvidence)]
        library.events = [StoryEvent(id: "event", storyID: "story", sceneID: "scene", time: 3, sequence: 2, entityID: "rowan", property: "rank", value: "Corporal", previousValue: "Private", evidence: sceneEvidence)]
        library.claims = [NarrativeClaim(id: "claim:scene:1", storyID: "story", sceneID: "scene", entityID: "rowan", property: "rank", value: "Private", isTransition: false, anchor: anchor, status: .conflict)]
        library.agents = [AgentDefinition(id: "guild.style", name: "The Stylist", role: "Prose", categories: ["STYLE"], traits: ["Gentle"])]
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        library.observations = [AgentObservation(id: "scene:1:hedge:0", agentID: "guild.style", category: "STYLE", confidence: 0.8, anchor: anchor, message: "Is the hesitation intentional?", question: "Keep it?", evidence: [sceneEvidence, canonEvidence], createdAt: date, status: .markedIntentional)]
        library.feedback = [FeedbackEvent(id: "feedback", observationID: "scene:1:hedge:0", agentID: "guild.style", worldID: "world-z", category: "STYLE", action: .markedIntentional, createdAt: date)]
        library.memories = [AgentMemory(id: "memory", agentID: "guild.style", worldID: "world-z", layer: "semantic", category: "STYLE", belief: "Hesitation is deliberate here.", salience: 0.8, strength: 0.9, confidence: 0.75, decayRate: 0.03, createdAt: date, lastRecalledAt: date, recallCount: 2, sourceFeedbackIDs: ["feedback"])]
        library.reviewRuns = [ReviewRun(id: "review", sceneID: "scene", revision: 1, startedAt: date, status: "completed")]
        return library
    }

    private func sourceFiles(_ directory: URL, extension suffix: String) throws -> [URL] {
        let root = directory.appendingPathComponent("sources")
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == suffix }
    }

    private func sql(_ sql: String, directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [directory.appendingPathComponent("library.sqlite3").path, sql]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SQLiteTestSetup", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)])
        }
    }

    func testEmptyInitializationAndCompleteUnicodeRoundTrip() throws {
        let directory = try temporaryDirectory()
        let store = try LibraryStore(directory: directory)
        XCTAssertEqual(try store.load(), Library())
        let expected = fixture()
        try store.save(expected)
        XCTAssertEqual(try LibraryStore(directory: directory).load(), expected)
        let html = try XCTUnwrap(sourceFiles(directory, extension: "html").first)
        XCTAssertEqual(try String(contentsOf: html, encoding: .utf8), expected.manuscripts[0].html)
        let plainText = try XCTUnwrap(sourceFiles(directory, extension: "txt").first)
        XCTAssertEqual(try String(contentsOf: plainText, encoding: .utf8), expected.manuscripts[0].text)
        let markdown = try sourceFiles(directory, extension: "md").map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(Set(markdown), Set(expected.lore.map(\.markdown)))
    }

    func testNewRevisionSurvivesReopenAndKeepsOldPortableSource() throws {
        let directory = try temporaryDirectory()
        let store = try LibraryStore(directory: directory)
        var novel = fixture()
        try store.save(novel)
        let originalURL = try XCTUnwrap(sourceFiles(directory, extension: "html").first)
        let originalHTML = novel.manuscripts[0].html
        novel.manuscripts[0].revision += 1
        novel.manuscripts[0].html = "<p><strong>New</strong> ending 👩🏽‍🚀.</p>"
        novel.manuscripts[0].text = "New ending 👩🏽‍🚀."
        novel.lore[0].markdown += "\nThe gate has fallen.\n"
        try store.save(novel)
        XCTAssertEqual(try LibraryStore(directory: directory).load(), novel)
        XCTAssertEqual(try String(contentsOf: originalURL, encoding: .utf8), originalHTML)
        XCTAssertThrowsError(try store.save(fixture())) { error in
            guard case LibraryStoreError.staleRevision("scene") = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try store.load(), novel)
    }

    func testTransactionFailurePreservesCommittedNovelAndNewSources() throws {
        let directory = try temporaryDirectory()
        let store = try LibraryStore(directory: directory)
        let original = fixture()
        try store.save(original)
        try sql("CREATE TRIGGER reject_records BEFORE INSERT ON records BEGIN SELECT RAISE(ABORT, 'simulated disk transaction failure'); END;", directory: directory)
        var changed = original
        changed.manuscripts[0].revision += 1
        changed.manuscripts[0].html = "<p>Uncommitted but preserved writing.</p>"
        changed.manuscripts[0].text = "Uncommitted but preserved writing."
        XCTAssertThrowsError(try store.save(changed))
        XCTAssertEqual(try LibraryStore(directory: directory).load(), original)
        let html = try sourceFiles(directory, extension: "html").map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertTrue(html.contains(original.manuscripts[0].html))
        XCTAssertTrue(html.contains(changed.manuscripts[0].html))
        XCTAssertEqual(Set(try store.search("northern", worldID: "world-z").map(\.kind)), ["lore", "manuscript"])
        try sql("DROP TRIGGER reject_records;", directory: directory)
        try store.save(changed)
        XCTAssertEqual(try store.load(), changed)
    }

    func testSourceCorruptionIsExplicitAndCannotBeOverwrittenBySave() throws {
        let directory = try temporaryDirectory()
        let store = try LibraryStore(directory: directory)
        let novel = fixture()
        try store.save(novel)
        let html = try XCTUnwrap(sourceFiles(directory, extension: "html").first)
        try Data("corrupted externally".utf8).write(to: html)
        XCTAssertThrowsError(try store.load()) { error in
            guard case LibraryStoreError.corruptSource = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertThrowsError(try store.save(novel))
        XCTAssertEqual(try String(contentsOf: html, encoding: .utf8), "corrupted externally")
    }

    func testDatabaseCorruptionAndNewerSchemaAreNotReset() throws {
        let corruptDirectory = try temporaryDirectory()
        let bytes = Data("this is not a SQLite database".utf8)
        let database = corruptDirectory.appendingPathComponent("library.sqlite3")
        try bytes.write(to: database)
        XCTAssertThrowsError(try LibraryStore(directory: corruptDirectory))
        XCTAssertEqual(try Data(contentsOf: database), bytes)
        let futureDirectory = try temporaryDirectory()
        let store = try LibraryStore(directory: futureDirectory)
        try store.save(fixture())
        try sql("PRAGMA user_version=999;", directory: futureDirectory)
        XCTAssertThrowsError(try LibraryStore(directory: futureDirectory)) { error in
            guard case LibraryStoreError.unsupportedSchema(999) = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInvalidIDsAndCrossWorldOwnershipRejectWithoutDamagingNovel() throws {
        let directory = try temporaryDirectory()
        let store = try LibraryStore(directory: directory)
        let original = fixture()
        try store.save(original)
        var invalid = original
        invalid.lore[0].id = "../../escape"
        XCTAssertThrowsError(try store.save(invalid))
        invalid = original
        invalid.entities[0].worldID = "world-a"
        XCTAssertThrowsError(try store.save(invalid))
        invalid = original
        invalid.worlds.append(invalid.worlds[0])
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load(), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("escape.md").path))
    }

    func testIndependentStoresRejectStaleWritesUntilReload() throws {
        let directory = try temporaryDirectory()
        let first = try LibraryStore(directory: directory)
        var novel = fixture()
        try first.save(novel)
        let second = try LibraryStore(directory: directory)
        let stale = try second.load()
        novel.worlds[0].name = "The Changed Reach"
        try first.save(novel)
        XCTAssertThrowsError(try second.save(stale)) { error in
            guard case LibraryStoreError.staleSnapshot = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try second.load(), novel)
        novel.worlds[0].name = "Reloaded and changed"
        try second.save(novel)
        XCTAssertEqual(try first.load(), novel)
    }

    func testLexicalSearchIsWorldScopedAndTreatsQuerySyntaxAsText() throws {
        let directory = try temporaryDirectory()
        let store = try LibraryStore(directory: directory)
        try store.save(fixture())
        let hits = try store.search("northern gate", worldID: "world-z")
        XCTAssertEqual(Set(hits.map(\.id)), ["scene", "lore"])
        XCTAssertTrue(hits.allSatisfy { $0.snippet.lowercased().contains("northern") })
        XCTAssertEqual(try store.search("northern", worldID: "world-a").map(\.id), ["other-lore"])
        XCTAssertEqual(try store.search("northern", worldID: "world-z", limit: 1).count, 1)
        XCTAssertEqual(try store.search("northern", worldID: "world-z", limit: 0), [])
        XCTAssertEqual(try store.search("\"*():", worldID: "world-z"), [])
        XCTAssertEqual(try store.search("northern OR nonmatchingword", worldID: "world-z"), [])
        XCTAssertEqual(try store.search("Élise", worldID: "world-z").count, 2)
    }

    func testMissingDatabaseBesideSourcesDoesNotInitializeAnEmptyNovel() throws {
        let directory = try temporaryDirectory()
        let sources = directory.appendingPathComponent("sources/manuscripts/scene", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let html = sources.appendingPathComponent("recovered.html")
        try Data("<p>Recover me.</p>".utf8).write(to: html)
        XCTAssertThrowsError(try LibraryStore(directory: directory))
        XCTAssertEqual(try String(contentsOf: html, encoding: .utf8), "<p>Recover me.</p>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("library.sqlite3").path))
    }
}
