import AppKit
import GuildCore
import XCTest
@testable import EditorHost

final class EditorHostTests: XCTestCase {
    @MainActor
    func testBundledWordgardRoundTripAndSceneSwitchFlush() async throws {
        _ = NSApplication.shared
        let controller = EditorController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.webView
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        var changes: [Manuscript] = []
        controller.onChange = { changes.append($0) }
        var selections: [EditorSelection] = []
        controller.onSelectionChange = { selections.append($0) }
        controller.load(Manuscript(sceneID: "first", html: "<p>A 🦊 waits.</p>", text: "A 🦊 waits.", revision: 12))
        try await waitUntil { controller.loadedSceneID == "first" && controller.isLoaded }
        XCTAssertTrue(controller.isReady)
        let initial = try await controller.export()
        XCTAssertEqual(initial.text, "A 🦊 waits.")
        XCTAssertEqual(initial.revision, 12)

        try await controller.setSelection(start: 5, length: 5)
        let selection = try await controller.getSelection()
        XCTAssertEqual(selection, EditorSelection(start: 5, length: 5, text: "waits"))
        try await waitUntil { selections.last == selection }
        try await controller.applyFormatting(.strong)
        let formatted = try await controller.export()
        XCTAssertTrue(formatted.html.contains("<strong>waits</strong>"))
        XCTAssertGreaterThan(formatted.revision, initial.revision)
        controller.load(formatted)
        try await controller.applyFormatting(.undo)
        let undone = try await controller.export()
        XCTAssertFalse(undone.html.contains("<strong>"))

        try await controller.setSelection(start: 5, length: 5)
        try await controller.insertText("listens")
        // Switch without an explicit export: the controller must flush old prose.
        controller.load(Manuscript(sceneID: "second", html: "<p>Elsewhere.</p>", text: "Elsewhere.", revision: 3))
        try await waitUntil { controller.loadedSceneID == "second" && controller.isLoaded }
        let savedFirst = try XCTUnwrap(changes.last(where: { $0.sceneID == "first" }))
        XCTAssertEqual(savedFirst.text, "A 🦊 listens.")
        XCTAssertGreaterThan(savedFirst.revision, formatted.revision)
        let second = try await controller.export()
        XCTAssertEqual(second.text, "Elsewhere.")
        XCTAssertEqual(second.revision, 3)
        controller.load(savedFirst)
        try await waitUntil { controller.loadedSceneID == "first" && controller.isLoaded }
        let reopened = try await controller.export()
        XCTAssertEqual(reopened, savedFirst)
        XCTAssertNil(controller.lastError)
    }

    @MainActor
    func testUnavailableBridgeReturnsExplicitError() async throws {
        let controller = EditorController()
        do {
            _ = try await controller.export()
            XCTFail("An unready editor must not fabricate a manuscript")
        } catch {
            XCTAssertTrue(error is EditorBridgeError)
        }
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw EditorBridgeError.unavailable("Timed out waiting for bundled Wordgard to load") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
