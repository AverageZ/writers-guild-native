import AppKit
import Foundation
import WebKit
import GuildCore
import GuildPersistence

/// Opt-in integration scenario against a disposable library, using the real native window
/// and WKWebView. Run twice: the second process verifies shutdown/reopen durability.
@MainActor
enum NativeSmoke {
    private static var started = false
    static func run(model: WorkspaceModel) {
        guard !started else { return }
        started = true
        Task {
            do {
                guard CommandLine.arguments.contains("--library"), let store = model.store else { throw Failure("Smoke requires an explicit disposable --library directory") }
                let marker = store.directory.appendingPathComponent("smoke-result.json")
                if FileManager.default.fileExists(atPath: marker.path) {
                    try require(model.library.manuscripts.contains { $0.text.contains("Native smoke: saved across process restart.") }, "reopened manuscript text")
                    try require(!model.library.feedback.isEmpty && !model.library.memories.isEmpty, "reopened feedback and agent memories")
                    try require(model.library.worlds.contains { $0.name == "Smoke World" }, "reopened created world")
                    try require(model.library.memories.contains { $0.layer == "semantic" && $0.category == "STYLE" }, "reopened consolidated style belief")
                    print("NATIVE REOPEN PASS: manuscript, worlds, feedback, memories")
                    NSApplication.shared.terminate(nil)
                    return
                }
                try await wait("WKWebView ready") { findWebView() != nil }
                let view = findWebView()!
                try await wait("editor document loaded") {
                    (try? await view.evaluateJavaScript("Boolean(document.querySelector('[contenteditable=true]'))")) as? Bool == true
                }
                try require(view.url?.path.hasPrefix(Bundle.main.bundleURL.path + "/") == true, "editor assets resolve inside the packaged app, never the build tree")
                guard let fixture = model.library.scenes.first(where: { $0.id == "scene-5" }) else { throw Failure("Greyhaven scene-5 missing") }
                model.switchScene(fixture)
                try await wait("fixture scene switch") { model.sceneID == fixture.id && !model.switching }
                try await Task.sleep(for: .milliseconds(250))
                let before = try await model.editor.export()
                try require(before.sceneID == fixture.id, "bridge document identity")
                _ = try await view.evaluateJavaScript("""
                (() => { const e = document.querySelector('[contenteditable=true]'); e.focus();
                const range = document.createRange(); range.selectNodeContents(e); range.collapse(false);
                const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
                return document.execCommand('insertText', false, '\\nNative smoke: saved across process restart.'); })()
                """)
                try await Task.sleep(for: .milliseconds(150))
                try require(await model.flush(), "flush editor to disk")
                try require(model.manuscript?.text.contains("Native smoke: saved across process restart.") == true, "real contenteditable input reached Swift")
                try require((model.manuscript?.revision ?? 0) > before.revision, "document revision advanced")
                model.review(deliberate: true)
                try await wait("grounded review") { !model.reviewing }
                let observations = model.observations
                try require(observations.count >= 5, "Greyhaven observations delivered")
                try require(observations.allSatisfy { !$0.evidence.isEmpty }, "observations have app evidence")
                model.review(deliberate: true)
                try await wait("repeat review") { !model.reviewing }
                try require(model.error == nil, "repeat review persistence: \(model.error ?? "no error")")
                try await Task.sleep(for: .milliseconds(200))
                let count = try await view.evaluateJavaScript("document.querySelectorAll('[data-annotation-id]').length") as? Int ?? 0
                try require(count > 0, "real in-editor annotations rendered")
                print("NATIVE EDITOR: \(count) annotation elements, \(observations.count) grounded observations")
                if let first = observations.first {
                    let clicked = try await view.evaluateJavaScript("(() => { const e = document.querySelector('[data-annotation-id]'); e.click(); return e.getAttribute('data-annotation-id'); })()") as? String
                    try await wait("annotation click callback") { model.selectedObservationID == clicked }
                    try require(clicked != nil, "annotation click targets evidence-backed observation")
                    if let evidence = first.evidence.first { model.showEvidence(evidence); try require(model.evidence?.id == evidence.id, "evidence inspector") }
                    model.evidence = nil
                    model.feedback(first, action: .markedIntentional)
                }
                let configuration = WKSnapshotConfiguration()
                let image = try await view.takeSnapshot(configuration: configuration)
                if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: store.directory.appendingPathComponent("editor-native.png"))
                }
                if let source = observations.first(where: { $0.category == "CHARACTER" })?.evidence.first(where: { $0.kind == "lore" }) {
                    model.navigateEvidence(source)
                    try require(model.route == "lore" && model.selectedLoreID == source.sourceID, "evidence selects its exact lore source")
                    model.switchScene(fixture)
                    try await wait("return from lore evidence") { model.route == "writing" && !model.switching }
                }
                let styleConcerns = Array(observations.filter { $0.category == "STYLE" }.prefix(2))
                try require(styleConcerns.count == 2, "independent stylistic feedback opportunities")
                for concern in styleConcerns { model.feedback(concern, action: .markedIntentional) }
                model.quietTime = true
                try require(model.quietTime && model.manuscript?.text.contains("Native smoke:") == true, "quiet writing retains manuscript")
                model.quietTime = false
                model.endSession()
                try await wait("session consolidation") { model.route == "guild" }
                try require(!model.library.memories.isEmpty, "session memory effect")
                try require(model.library.memories.contains { $0.layer == "semantic" && $0.category == "STYLE" }, "End Session produced a semantic belief")
                let originalStyle = model.library.agents.first { $0.categories.contains("STYLE") }!
                let learnedStyle = AgentMemoryEngine.adjustedAgents(in: model.library, worldID: model.worldID!).first { $0.id == originalStyle.id }!
                try require(learnedStyle.patternThreshold > originalStyle.patternThreshold, "feedback measurably changed later review threshold")
                model.createWorld(name: "Smoke World")
                try await wait("created world selected") { model.world?.name == "Smoke World" }
                model.createStory(title: "First Smoke Story")
                try await wait("created story selected") { model.story?.title == "First Smoke Story" && !model.switching }
                model.createStory(title: "Second Smoke Story")
                try await wait("second story selected") { model.story?.title == "Second Smoke Story" && !model.switching }
                try require(model.library.stories.filter { $0.worldID == model.worldID }.count == 2, "multiple stories share created world")
                let authoredStory = model.story!
                let earlierScene = model.scene!
                try await model.editor.insertText("Aster was promoted to Corporal.")
                try require(await model.flush(), "writer-authored earlier scene")
                guard let asterID = model.createEntity(name: "Aster", kind: "character", aliases: "Aster Vale") else { throw Failure("entity creation") }
                model.addLore(title: "Smoke Lore")
                let loreIndex = model.library.lore.count - 1
                model.library.lore[loreIndex].markdown = "# Aster\n\nAster begins as Private."
                model.establishCanonicalFact(entityID: asterID, property: "rank", value: "Private", quote: "Aster begins as Private.", loreID: model.library.lore[loreIndex].id)
                model.establishEvent(entityID: asterID, property: "rank", value: "Corporal", quote: "Aster was promoted to Corporal.", time: earlierScene.time)
                model.createScene(storyID: authoredStory.id, title: "Later", chapter: "Chapter 2", time: earlierScene.time + 1)
                try await wait("writer-created later scene") { model.scene?.title == "Later" && !model.switching }
                try await model.editor.insertText("Private Aster stepped forward.")
                try require(await model.flush(), "writer-authored later mistake")
                model.review(deliberate: true)
                try await wait("writer-authored continuity review") { !model.reviewing }
                try require(model.observations.contains { $0.category == "CHARACTER" && $0.evidence.contains { $0.sourceID == earlierScene.id } }, "new world continuity cites writer-established earlier event")
                try require(await model.flush(), "final flush")
                let reloaded = try LibraryStore(directory: store.directory).load()
                try require(reloaded.manuscripts.contains { $0.text.contains("Native smoke: saved across process restart.") }, "independent store reload")
                try require(!reloaded.feedback.isEmpty && !reloaded.memories.isEmpty, "persistent memory and feedback")
                try require(model.error == nil, "native workflow remained error-free: \(model.error ?? "no error")")
                try Data("{\"status\":\"passed\",\"observations\":\(observations.count)}\n".utf8).write(to: marker, options: .atomic)
                print("NATIVE SMOKE PASS: real Wordgard input, grounded review, evidence, feedback, Quiet Time, memory, world/story/scene/lore creation, disk reload")
                NSApplication.shared.terminate(nil)
            } catch {
                print("NATIVE SMOKE FAIL: \(error)")
                fflush(stdout)
                exit(1)
            }
        }
    }

    private static func require(_ condition: Bool, _ label: String) throws { if !condition { throw Failure(label) } }
    private static func wait(_ label: String, condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<150 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure("Timed out: \(label)")
    }
    private static func findWebView() -> WKWebView? {
        func descend(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap(descend).first
        }
        return NSApplication.shared.windows.compactMap(\.contentView).lazy.compactMap(descend).first
    }
    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
