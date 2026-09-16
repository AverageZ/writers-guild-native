import AppKit
import SwiftUI

@main
struct WritersGuildApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = WorkspaceModel()

    var body: some Scene {
        Window("Writers Guild", id: "workspace") {
            WorkspaceView(model: model)
                .onAppear {
                    delegate.model = model
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if CommandLine.arguments.contains("--smoke-test") { NativeSmoke.run(model: model) }
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Library Folder…") { model.chooseLibrary() }.keyboardShortcut("o")
                Button("Save") { Task { await model.flush() } }.keyboardShortcut("s")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: WorkspaceModel?
    private var terminating = false
    private var readyToTerminate = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if readyToTerminate { return .terminateNow }
        guard let model else { return .terminateNow }
        guard !terminating else { return .terminateCancel }
        terminating = true
        let windows = sender.windows
        for window in windows {
            window.makeFirstResponder(nil)
            window.ignoresMouseEvents = true
        }
        // Keep the normal run loop alive while WKWebView exports. terminateLater
        // enters AppKit's termination loop, which can starve the WebKit reply.
        Task {
            let saved = await model.flush()
            for window in windows { window.ignoresMouseEvents = false }
            terminating = false
            if saved {
                readyToTerminate = true
                sender.terminate(nil)
            }
        }
        return .terminateCancel
    }
}
