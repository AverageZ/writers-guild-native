// Throwaway host for issue #11. Real Wordgard in WKWebView; no library, production bridge or data access.
import AppKit
import WebKit

@main
@MainActor
private final class RepeatedEnterApp: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var entry: URL!

    static func main() {
        let app = NSApplication.shared
        let delegate = RepeatedEnterApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        let directory = Bundle.main.resourceURL!.appendingPathComponent("Editor", isDirectory: true)
        entry = directory.appendingPathComponent("index.html")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 730),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "The Tide Gate — Repeated Enter Prototype"
        window.minSize = NSSize(width: 790, height: 590)
        window.contentView = web
        window.center()
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit Prototype",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        web.loadFileURL(entry, allowingReadAccessTo: directory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.targetFrame?.isMainFrame == true
            && navigationAction.request.url?.standardizedFileURL.path == entry.standardizedFileURL.path
        decisionHandler(allowed ? .allow : .cancel)
    }
}
