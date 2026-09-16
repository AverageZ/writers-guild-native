import AppKit
import Combine
import Foundation
import GuildCore
import GuildPersistence
import GuildAI
import EditorHost

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var library = Library()
    @Published var worldID: ID?
    @Published var sceneID: ID?
    @Published var route = "writing"
    @Published var selectedObservationID: ID?
    @Published var selectedLoreID: ID?
    @Published var evidence: EvidenceReference?
    @Published var error: String? {
        didSet {
            if let error, CommandLine.arguments.contains("--smoke-test") { print("NATIVE APP ERROR: \(error)") }
        }
    }
    @Published var status = "Opening library…"
    @Published var quietTime = false { didSet { cancelReviews(); refreshAnnotations(); if !quietTime { review(deliberate: false) } } }
    @Published var reviewing = false
    @Published var switching = false
    @Published private(set) var editor = EditorController()
    let provider = AppleModelProvider()
    let coordinator = ReviewCoordinator()
    private(set) var store: LibraryStore?
    private var editorLoaded = false
    private var saveTask: Task<Void, Never>?

    var world: World? { library.worlds.first { $0.id == worldID } }
    var scene: Scene? { library.scenes.first { $0.id == sceneID } }
    var story: Story? { library.stories.first { $0.id == scene?.storyID } }
    var manuscript: Manuscript? { library.manuscripts.first { $0.sceneID == sceneID } }
    var observations: [AgentObservation] {
        library.observations.filter { $0.anchor.sceneID == sceneID && [.unread, .read, .accepted].contains($0.status) }
    }
    var pendingClaims: [NarrativeClaim] {
        library.claims.filter { $0.sceneID == sceneID && [.pending, .conflict, .ambiguous].contains($0.status) && $0.anchor.revision == manuscript?.revision }
    }

    init() {
        connectEditor()
        do {
            let args = CommandLine.arguments
            let directory: URL
            if let index = args.firstIndex(of: "--library"), args.indices.contains(index + 1) {
                directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            } else {
                directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("Writers Guild", isDirectory: true)
            }
            try open(directory)
        } catch { self.error = error.localizedDescription; status = "Library could not be opened; original files untouched." }
    }

    private func connectEditor() {
        editor.onChange = { [weak self] document in self?.documentChanged(document) }
        editor.onAnnotationClick = { [weak self] id in self?.selectObservation(id) }
        editor.onError = { [weak self] message in self?.error = message }
    }

    func open(_ directory: URL) throws {
        let nextStore = try LibraryStore(directory: directory)
        var next = try nextStore.load()
        if next.worlds.isEmpty {
            next = Greyhaven.make()
            try nextStore.save(next)
        }
        cancelReviews()
        if store != nil {
            // A different library can legitimately reuse scene IDs. Never let its
            // pending bridge callbacks overwrite this library's documents.
            editor.onChange = nil
            editor.onAnnotationClick = nil
            editor.onError = nil
            editor = EditorController()
            connectEditor()
        }
        store = nextStore
        library = next
        worldID = next.worlds.first?.id
        sceneID = nil
        route = "writing"
        editorLoaded = false
        let firstStory = next.stories.first { $0.worldID == worldID }
        if let initial = next.scenes.filter({ $0.storyID == firstStory?.id }).sorted(by: { $0.order < $1.order }).first {
            activate(initial)
        }
        status = "Saved locally · \(directory.lastPathComponent)"
    }

    func chooseLibrary() {
        Task {
            guard await flush() else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            panel.prompt = "Open Library"; panel.message = "Choose a Writers Guild library folder. An empty folder starts with Greyhaven."
            if panel.runModal() == .OK, let url = panel.url {
                do { try open(url) } catch { self.error = error.localizedDescription }
            }
        }
    }

    func switchScene(_ next: Scene) {
        guard !switching else { return }
        switching = true
        Task {
            defer { switching = false }
            guard await flush() else { return }
            activate(next)
            do { try await waitForEditor() } catch { self.error = error.localizedDescription }
        }
    }

    private func activate(_ next: Scene) {
        cancelReviews()
        sceneID = next.id
        worldID = library.stories.first { $0.id == next.storyID }?.worldID
        selectedObservationID = nil
        route = "writing"
        if let document = manuscript { editor.load(document); editorLoaded = true }
        refreshAnnotations()
    }

    func selectWorld(_ id: ID) {
        guard id != worldID else { route = "writing"; return }
        Task {
            guard await flush() else { return }
            cancelReviews()
            worldID = id; sceneID = nil; editorLoaded = false; route = "writing"
            let storyIDs = Set(library.stories.filter { $0.worldID == id }.map(\.id))
            if let next = library.scenes.filter({ storyIDs.contains($0.storyID) }).sorted(by: { $0.order < $1.order }).first { activate(next) }
        }
    }

    func documentChanged(_ document: Manuscript) {
        guard let index = library.manuscripts.firstIndex(where: { $0.sceneID == document.sceneID }),
              document.revision >= library.manuscripts[index].revision else { return }
        guard document != library.manuscripts[index] else { return }
        library.manuscripts[index] = document
        for index in library.observations.indices where library.observations[index].anchor.sceneID == document.sceneID {
            if [.unread, .read, .accepted].contains(library.observations[index].status) { library.observations[index].status = .obsolete }
        }
        cancelReviews()
        refreshAnnotations()
        status = "Saving…"
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(250)); save() } catch { }
        }
        if document.sceneID == sceneID && !quietTime { review(deliberate: false) }
    }

    @discardableResult
    func flush() async -> Bool {
        saveTask?.cancel()
        if editorLoaded {
            do {
                try await waitForEditor()
                documentChanged(try await editor.export())
            }
            catch { self.error = "Could not finish saving the editor: \(error.localizedDescription)"; return false }
        }
        saveTask?.cancel()
        return save()
    }

    private func waitForEditor() async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !editor.isLoaded || editor.loadedSceneID != sceneID {
            if let message = editor.lastError { throw EditorBridgeError.unavailable(message) }
            guard ContinuousClock.now < deadline else { throw EditorBridgeError.unavailable("The selected manuscript did not finish loading.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let store else { error = "No writable library is open."; return false }
        do { try store.save(library); status = "Saved locally"; return true }
        catch { self.error = error.localizedDescription; status = "Save failed — keep this window open"; return false }
    }

    func createWorld(name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let newWorld = World(name: value)
        library.worlds.append(newWorld)
        if library.agents.isEmpty { library.agents = DeterministicAnalyzer.defaultAgents }
        save(); selectWorld(newWorld.id)
    }

    func createStory(title: String) {
        guard let worldID, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let newStory = Story(worldID: worldID, title: title)
        library.stories.append(newStory)
        createScene(storyID: newStory.id, title: "Opening", chapter: "Chapter 1", time: 1)
    }

    func createScene(storyID: ID, title: String, chapter: String, time: Int) {
        let order = (library.scenes.filter { $0.storyID == storyID }.map(\.order).max() ?? 0) + 1
        let next = Scene(storyID: storyID, title: title, chapter: chapter, order: order, time: time)
        library.scenes.append(next); library.manuscripts.append(Manuscript(sceneID: next.id))
        save(); switchScene(next)
    }

    func addLore(title: String) {
        guard let worldID else { return }
        let lore = Lore(worldID: worldID, title: title)
        library.lore.append(lore); selectedLoreID = lore.id; save(); route = "lore"
    }

    func review(deliberate: Bool) {
        guard let scene, let manuscript, let worldID, deliberate || !quietTime else { return }
        cancelReviews()
        if deliberate {
            for agent in library.agents where agent.enabled {
                for category in agent.categories {
                    _ = AgentMemoryEngine.recall(agentID: agent.id, worldID: worldID, category: category, in: &library)
                }
            }
        }
        var snapshot = library
        snapshot.agents = AgentMemoryEngine.adjustedAgents(in: library, worldID: worldID)
        let context = ReviewContext(library: snapshot, scene: scene, manuscript: manuscript)
        let run = ReviewRun(sceneID: scene.id, revision: manuscript.revision, status: "running")
        if deliberate { library.reviewRuns.append(run); reviewing = true; status = "The Guild is reading…" }
        coordinator.review(context, delay: deliberate ? .zero : .seconds(2), model: deliberate && provider.isAvailable ? provider : nil) { [weak self] result, message in
            guard let self, self.sceneID == scene.id, self.manuscript?.revision == manuscript.revision else { return }
            self.reviewing = false
            for index in self.library.observations.indices where self.library.observations[index].anchor.sceneID == scene.id && [.unread, .read].contains(self.library.observations[index].status) {
                self.library.observations[index].status = .obsolete
            }
            let prior = self.library.observations.filter { $0.anchor.sceneID == scene.id && [.dismissed, .markedIntentional, .accepted].contains($0.status) }
            let fresh = result.observations.filter { observation in
                !prior.contains { $0.agentID == observation.agentID && $0.category == observation.category && $0.anchor.quote == observation.anchor.quote && $0.anchor.prefix == observation.anchor.prefix && $0.anchor.suffix == observation.anchor.suffix }
            }
            let replacedIDs = Set(fresh.map(\.id))
            self.library.observations.removeAll { replacedIDs.contains($0.id) }
            self.library.observations.append(contentsOf: fresh)
            self.library.claims.removeAll { $0.sceneID == scene.id && $0.status != .accepted && $0.status != .rejected }
            let decidedIDs = Set(self.library.claims.map(\.id))
            self.library.claims.append(contentsOf: result.claims.filter { !decidedIDs.contains($0.id) })
            if let index = self.library.reviewRuns.firstIndex(where: { $0.id == run.id }) { self.library.reviewRuns[index].status = message == nil ? "completed" : "completedWithModelError" }
            else { self.library.reviewRuns.append(ReviewRun(sceneID: scene.id, revision: manuscript.revision, status: "completedLocal")) }
            self.save(); self.refreshAnnotations()
            self.status = message ?? "Guild review complete · \(fresh.count) observations"
        }
    }

    func refreshAnnotations() { editor.annotate(quietTime ? [] : observations.filter { $0.status != .accepted }) }

    func selectObservation(_ id: ID) {
        selectedObservationID = id
        if let index = library.observations.firstIndex(where: { $0.id == id }), library.observations[index].status == .unread {
            library.observations[index].status = .read; save()
        }
        editor.scrollTo(id)
    }

    func feedback(_ observation: AgentObservation, action: ObservationStatus) {
        guard let worldID, let index = library.observations.firstIndex(where: { $0.id == observation.id }) else { return }
        guard library.observations[index].status != action else { return }
        library.observations[index].status = action
        let event = FeedbackEvent(observationID: observation.id, agentID: observation.agentID, worldID: worldID, category: observation.category, action: action)
        AgentMemoryEngine.record(feedback: event, observation: observation, in: &library)
        save(); refreshAnnotations()
    }

    func endSession() {
        Task {
            guard await flush(), let worldID else { return }
            let summary = AgentMemoryEngine.consolidate(worldID: worldID, in: &library)
            save(); status = summary; route = "guild"
        }
    }

    private func cancelReviews() {
        coordinator.cancel()
        reviewing = false
        for index in library.reviewRuns.indices where library.reviewRuns[index].status == "running" {
            library.reviewRuns[index].status = "cancelled"
        }
    }

    func showEvidence(_ reference: EvidenceReference) { evidence = reference }
    func navigateEvidence(_ reference: EvidenceReference) {
        let targetID = reference.anchor?.sceneID ?? reference.sourceID
        if let target = library.scenes.first(where: { $0.id == targetID }) { switchScene(target) }
        else if library.lore.contains(where: { $0.id == reference.sourceID }) {
            selectedLoreID = reference.sourceID
            route = "lore"
        } else if library.entities.contains(where: { $0.id == reference.sourceID }) {
            route = "state"
        }
    }
}
