// Technical walkthrough for the scratch app. Exercises the same action handlers as the UI;
// it does not drive a physical drag or supply human feedback.
import AppKit
import EditorHost
import GuildCore
import WebKit

private struct OutlineSmokeFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
func runOutlineSmoke(_ session: OutlineSession, window: NSWindow, output: URL) async {
    func require(_ ok: Bool, _ message: String) throws {
        if !ok { throw OutlineSmokeFailure(message: message) }
    }
    func wait(_ message: String, until check: () async throws -> Bool) async throws {
        for _ in 0..<100 {
            if try await check() { return }
            try await Task.sleep(for: .milliseconds(60))
        }
        throw OutlineSmokeFailure(message: message)
    }
    func screenshot(_ name: String, web: WKWebView? = nil) async throws {
        try await Task.sleep(for: .milliseconds(160))
        guard let content = window.contentView,
              let backing = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw OutlineSmokeFailure(message: "No native window backing")
        }
        let editorImage = try await web?.takeSnapshot(configuration: nil)
        content.layoutSubtreeIfNeeded()
        content.cacheDisplay(in: content.bounds, to: backing)
        let image = NSImage(size: content.bounds.size)
        image.lockFocus()
        backing.draw(in: content.bounds)
        if let editorImage, let web {
            var frame = content.convert(web.bounds, from: web)
            if content.isFlipped { frame.origin.y = content.bounds.height - frame.maxY }
            editorImage.draw(in: frame)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rendered = NSBitmapImageRep(data: tiff),
              let png = rendered.representation(using: .png, properties: [:]) else {
            throw OutlineSmokeFailure(message: "Unable to encode snapshot")
        }
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }
    let editor = session.editor
    do {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await wait("Native editor did not load S1") { editor.isLoaded && editor.loadedSceneID == "S1" }
        guard let web = findOutlineWeb(in: window.contentView),
              web.url?.path.hasPrefix(Bundle.main.bundleURL.path + "/") == true else {
            throw OutlineSmokeFailure(message: "Packaged WebKit editor not found")
        }
        func js(_ script: String) async throws -> Bool { try await web.evaluateJavaScript(script) as? Bool == true }
        let note = session.ghost!
        try await wait("Inline ghost not rendered") { try await js("!!document.querySelector('[data-ghost-copy]')") }
        let initial = try await editor.export()
        let timeIDs = session.fixture.chronology.map(\.id)
        let initialPresentation = session.fixture.presentation
        try await screenshot("manuscript-list", web: web)

        let first = OutlineFixture.Slot(chapter: "A", before: "S1")
        session.beginDrag("S3")
        session.drag.gap = first
        session.drag.hoveredRow = first
        try await screenshot("insertion-gap", web: web)
        session.endDrag()
        try require(session.drag.gap == nil && session.drag.source == nil
                    && session.fixture.presentation == initialPresentation, "Cancel retained a preview or moved a row")
        try require(session.drop("S3", at: first), "Move refused")
        try require(session.fixture.presentation == ["S3", "S1", "L1", "S2"], "Cross-chapter move order incorrect")
        try require(session.fixture.chapters[1].blocks.isEmpty, "Chapter B lost its empty grouping")
        try require(session.fixture.chronology.map(\.id) == timeIDs && session.fixture.blocks["S3"]?.time == 1,
                    "Move affected chronology")
        try require(session.selected == "S1" && session.ghost?.id == note.id && session.feedback.contains("Story time unchanged"),
                    "Reorder changed selection, ghost identity or omitted feedback")
        try await screenshot("list-after-move", web: web)
        session.undoMove()
        try require(session.fixture.presentation == initialPresentation, "Undo did not restore chapter ownership/order")
        _ = session.drop("S3", at: .init(chapter: "A", before: "not-a-block"))
        try require(session.fixture.presentation == initialPresentation, "Invalid destination moved a block")

        let idea = session.fixture.ideas[0]
        let end = OutlineFixture.Slot(chapter: "B")
        try require(session.drop(idea.id, at: end), "Drop did not stage promotion")
        guard var form = session.creation else { throw OutlineSmokeFailure(message: "Promotion did not open chooser") }
        try require(form.kind == nil && session.fixture.ideas.contains(where: { $0.id == idea.id }), "Drop committed the idea automatically")
        session.create(form)
        try require(session.creation != nil && session.fixture.presentation == initialPresentation, "Missing block type committed the idea")
        session.creation = nil
        try require(session.fixture.ideas.contains(where: { $0.id == idea.id }), "Cancel lost the idea")
        form.kind = .scene
        session.create(form)
        let newScene = session.selected
        try await wait("Promoted Scene didn't load") { editor.isLoaded && editor.loadedSceneID == newScene }
        try require(session.fixture.presentation.last == newScene && session.fixture.ideas.isEmpty,
                    "Promotion did not consume/place idea")
        let promotedText = try await editor.getText()
        try require(session.block.note == idea.note && promotedText.isEmpty, "Idea text leaked into the manuscript")
        try await checkNotes(session, initial: initial, note: note, web: web, screenshot: screenshot)
        print("OUTLINE SMOKE PASS: native List snapshots; reorder and undo without chronology changes; explicit promotion;"
              + " unbound Level navigation; Wordgard ghost typing, replacement, reattachment and resolution history")
        fflush(nil)
        exit(EXIT_SUCCESS)
    } catch {
        print("OUTLINE SMOKE FAIL: \(error.localizedDescription) · bridge: \(session.error ?? editor.lastError ?? "none")")
        fflush(nil)
        exit(EXIT_FAILURE)
    }
}

@MainActor
private func checkNotes(
    _ session: OutlineSession, initial: Manuscript, note: OutlineFixture.Ghost, web: WKWebView,
    screenshot: (String, WKWebView?) async throws -> Void
) async throws {
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw OutlineSmokeFailure(message: message) }
    }
    func wait(_ message: String, until check: () async throws -> Bool) async throws {
        for _ in 0..<100 {
            if try await check() { return }
            try await Task.sleep(for: .milliseconds(60))
        }
        throw OutlineSmokeFailure(message: message)
    }
    func js(_ script: String) async throws -> Bool { try await web.evaluateJavaScript(script) as? Bool == true }
    let editor = session.editor
    let newScene = session.selected
    session.fixture.blocks[newScene]?.note = "Edited outline-only note."
    try require(try await editor.getText().isEmpty, "Changing outline note altered draft")

    session.open("S1")
    try await wait("S1 not reachable") { editor.isLoaded && editor.loadedSceneID == "S1" }
    session.open(session.adjacent.next!)
    try require(session.selected == "L1" && session.block.prose == nil && session.block.referenceState == "Unbound",
                "Next didn't enter the unbound Level")
    try await wait("Previous Scene editor was not hidden on the Level") { web.isHidden }
    try await screenshot("unbound-level", nil)
    session.fixture.blocks["L1"]?.reference = "cross-lock-01"
    try require(session.block.referenceState == "Reference supplied—not verified", "Reference implies playable or unbound")
    session.fixture.blocks["L1"]?.reference = ""
    try require(session.block.id == "L1" && session.block.referenceState == "Unbound", "Clearing reference replaced Level")
    session.open(session.adjacent.next!)
    try await wait("Navigation skipped or failed to enter S2") { editor.isLoaded && editor.loadedSceneID == "S2" }
    session.open("S1")
    try await wait("Return to S1 timed out") { editor.isLoaded && editor.loadedSceneID == "S1" }
    try await wait("Ghost did not return with its scene") { try await js("!!document.querySelector('[data-ghost-copy]')") }

    let past = note.lastAnchor.start + note.lastAnchor.length
    try await editor.setSelection(start: past, length: 0)
    try await editor.insertText(" No one answered.")
    try await wait("Draft edit did not reach the scratch model") { session.block.prose?.text.contains("No one answered.") == true }
    try require(session.ghost?.id == note.id && session.ghost?.state == .active, "Drafting silently changed ghost state")
    let written = try await editor.export()
    try require(written.text != initial.text && !written.text.contains(note.text) && !written.html.contains(note.text),
                "Ghost appeared in manuscript text or HTML")
    try await screenshot("ghost-after-typing", web)
    session.showGhost = false
    try require(session.ghost?.id == note.id && session.ghost?.state == .active, "Closing controls changed the ghost")

    try await editor.setSelection(start: note.lastAnchor.start, length: note.lastAnchor.length)
    try await editor.insertText("the bells stopped.")
    try await wait("Replaced passage did not expose Needs placement") { session.ghost?.state == .unplaced }
    try require(session.ghost?.id == note.id, "Replacing a passage discarded its ghost note")
    try await wait("Unplaced note remained drawn inline") { try await js("!document.querySelector('[data-ghost-copy]')") }
    let replacement = (try await editor.getText() as NSString).range(of: "the bells stopped.")
    try await editor.setSelection(start: replacement.location, length: replacement.length)
    await session.placeGhost(text: nil)
    try require(session.ghost?.id == note.id && session.ghost?.lastAnchor.quote == "the bells stopped.",
                "Explicit placement did not reuse the same note")
    try await wait("Reattached note not inline") { try await js("!!document.querySelector('[data-ghost-copy]')") }
    session.resolveGhost()
    try await wait("Resolved note remained inline") { try await js("!document.querySelector('[data-ghost-copy]')") }
    try require(session.ghost == nil && session.resolved.map(\.id) == [note.id], "Resolve lost ghost history")
    try await screenshot("resolved-note", web)
    await session.placeGhost(text: "A new passage reminder.")
    try require(session.ghost?.text == "A new passage reminder." && session.resolved.map(\.id) == [note.id],
                "A resolved note prevented a new ghost or disappeared when a new ghost was added")
    try require(session.error == nil, session.error ?? "Editor reported an error")
}
