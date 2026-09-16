import AppKit
import Combine
import Foundation
import GuildCore
import SwiftUI
import WebKit

public enum EditorBridgeError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    case command(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let message), .command(let message): message
        case .invalidResponse: "The manuscript editor returned an invalid bridge response."
        }
    }
}

public struct EditorSelection: Codable, Sendable, Equatable {
    public var start: Int
    public var length: Int
    public var text: String
    public init(start: Int, length: Int, text: String) { self.start = start; self.length = length; self.text = text }
}

public enum EditorFormatting: String, Codable, Sendable {
    case strong, emphasis, paragraph, heading1, heading2, blockquote, bulletList, orderedList, undo, redo
}

/// Owns one persistent WKWebView. SwiftUI updates never replace its editing state.
@MainActor
public final class EditorController: NSObject, ObservableObject {
    public var onChange: ((Manuscript) -> Void)?
    public var onSelectionChange: ((EditorSelection) -> Void)?
    public var onAnnotationClick: ((ID) -> Void)?
    public var onError: ((String) -> Void)?
    @Published public private(set) var isReady = false
    @Published public private(set) var loadedSceneID: ID?
    @Published public private(set) var lastError: String?
    @Published public private(set) var isLoading = false
    public var isLoaded: Bool { loadedSceneID != nil && !isLoading }

    let webView: WKWebView
    private var entryURL: URL?
    private var current: Manuscript?
    private var pending: Manuscript?
    private var observations: [AgentObservation] = []
    private var handler: WeakMessageHandler?

    public override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        let handler = WeakMessageHandler(owner: self)
        self.handler = handler
        configuration.userContentController.add(handler, name: "guild")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            // SwiftPM's generated accessor searches the app root, not Contents/Resources.
            // Packaged apps must never fall back to an absolute developer build path.
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("WritersGuild_EditorHost.bundle"),
                  let bundle = Bundle(url: url) else {
                report("The application is missing its bundled manuscript editor. Rebuild the app with make app.")
                return
            }
            resources = bundle
        } else {
            resources = Bundle.module
        }
        guard let directory = resources.resourceURL?.appendingPathComponent("Editor", isDirectory: true),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path) else {
            report("Bundled manuscript editor is missing. Run npm ci && npm run build in Editor before building the app.")
            return
        }
        entryURL = directory.appendingPathComponent("index.html")
        // CSP denies all network categories; the WebKit rule also blocks network
        // subresources before any document/parser can attempt loading an embed.
        let rules = """
        [{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "GuildOfflineEditor", encodedContentRuleList: rules) { [weak self] list, error in
            guard let self else { return }
            if let error { self.report("Cannot install editor network protection: \(error.localizedDescription)"); return }
            guard let list else { self.report("Editor network protection was not created."); return }
            self.webView.configuration.userContentController.add(list)
            if let entryURL = self.entryURL { self.webView.loadFileURL(entryURL, allowingReadAccessTo: directory) }
        }
    }

    /// Queues a switch, exporting the previous scene before replacing the surface.
    /// Same-scene snapshots are acknowledgements, not a reason to reset typing/undo.
    public func load(_ manuscript: Manuscript) {
        guard manuscript.sceneID != loadedSceneID else { return }
        pending = manuscript
        startPendingLoad()
    }

    private func startPendingLoad() {
        guard isReady, !isLoading, pending != nil else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false; self.startPendingLoad() }
            guard let next = self.pending else { return }
            self.pending = nil
            do {
                if self.current != nil {
                    let previous = try await self.export()
                    self.onChange?(previous)
                }
                let loaded: Manuscript = try await self.request("load", payload: next)
                self.current = loaded
                self.loadedSceneID = loaded.sceneID
                if loaded != next { self.onChange?(loaded) }
                try await self.sendAnnotations()
            } catch { self.report(error.localizedDescription) }
        }
    }

    public func annotate(_ observations: [AgentObservation]) {
        self.observations = observations
        guard isReady, current != nil, !isLoading else { return }
        Task { [weak self] in
            guard let self else { return }
            do { try await self.sendAnnotations() } catch { self.report(error.localizedDescription) }
        }
    }

    private struct AnnotationPayload: Encodable {
        var id: ID
        var anchor: TextAnchor
    }
    private func sendAnnotations() async throws {
        let annotations = observations.filter {
            $0.anchor.sceneID == loadedSceneID && ($0.status == .unread || $0.status == .read || $0.status == .accepted)
        }.map { AnnotationPayload(id: $0.id, anchor: $0.anchor) }
        try await command("annotate", payload: annotations)
    }

    public func scrollTo(_ id: ID) {
        Task { [weak self] in
            guard let self else { return }
            do { try await self.command("scrollTo", payload: id) } catch { self.report(error.localizedDescription) }
        }
    }

    /// Call and await before closing a window or persisting its final state.
    public func export() async throws -> Manuscript {
        let manuscript: Manuscript = try await request("export", payload: Optional<String>.none)
        current = manuscript
        return manuscript
    }
    public func getText() async throws -> String { try await request("getText", payload: Optional<String>.none) }
    public func getSelection() async throws -> EditorSelection { try await request("getSelection", payload: Optional<String>.none) }
    public func getTextForAnchor(_ anchor: TextAnchor) async throws -> String { try await request("getTextForAnchor", payload: anchor) }
    public func applyFormatting(_ format: EditorFormatting) async throws { try await command("applyFormatting", payload: format) }
    public func removeAnnotation(_ id: ID) async throws { try await command("removeAnnotation", payload: id) }
    public func setSelection(start: Int, length: Int) async throws {
        struct SelectionPayload: Encodable { var start: Int; var length: Int }
        try await command("setSelection", payload: SelectionPayload(start: start, length: length))
    }
    /// Inserts explicitly supplied writer text through Wordgard's input command.
    public func insertText(_ text: String) async throws { try await command("insertText", payload: text) }

    private struct Envelope<Payload: Encodable>: Encodable {
        let version = 1
        var id: String
        var method: String
        var payload: Payload
    }
    private struct Response<Value: Decodable>: Decodable {
        var version: Int
        var id: String
        var ok: Bool
        var value: Value?
        var error: String?
    }
    private struct Empty: Decodable {}

    private func command<Payload: Encodable>(_ method: String, payload: Payload) async throws {
        let _: Empty? = try await request(method, payload: payload)
    }
    private func request<Payload: Encodable, Value: Decodable>(_ method: String, payload: Payload) async throws -> Value {
        guard isReady else { throw EditorBridgeError.unavailable(lastError ?? "The manuscript editor is not ready.") }
        let id = UUID().uuidString
        let data = try JSONEncoder().encode(Envelope(id: id, method: method, payload: payload))
        let envelope = try JSONSerialization.jsonObject(with: data)
        let json: String = try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript("return JSON.stringify(window.guildEditor.dispatch(envelope));", arguments: ["envelope": envelope], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    guard let string = value as? String else { continuation.resume(throwing: EditorBridgeError.invalidResponse); return }
                    continuation.resume(returning: string)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        guard let resultData = json.data(using: .utf8) else { throw EditorBridgeError.invalidResponse }
        let response = try JSONDecoder().decode(Response<Value>.self, from: resultData)
        guard response.version == 1, response.id == id else { throw EditorBridgeError.invalidResponse }
        guard response.ok else { throw EditorBridgeError.command(response.error ?? "Editor command failed without an explanation.") }
        // Decode `value` directly so JSON null is valid for Optional command results.
        guard let object = try JSONSerialization.jsonObject(with: resultData) as? [String: Any], let value = object["value"] else { throw EditorBridgeError.invalidResponse }
        let valueData = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(Value.self, from: valueData)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url == entryURL,
              let body = message.body as? [String: Any], body["version"] as? Int == 1,
              let type = body["type"] as? String, let payload = body["payload"] else {
            report("Rejected invalid editor event envelope."); return
        }
        do {
            switch type {
            case "ready":
                guard payload is NSNull else { throw EditorBridgeError.invalidResponse }
                isReady = true; startPendingLoad()
            case "change":
                let data = try JSONSerialization.data(withJSONObject: payload)
                let manuscript = try JSONDecoder().decode(Manuscript.self, from: data)
                guard manuscript.sceneID == loadedSceneID, manuscript.revision >= (current?.revision ?? 0) else { return }
                current = manuscript; onChange?(manuscript)
            case "selectionChange":
                let data = try JSONSerialization.data(withJSONObject: payload)
                let selection = try JSONDecoder().decode(EditorSelection.self, from: data)
                guard selection.start >= 0, selection.length >= 0, selection.text.utf16.count == selection.length else { throw EditorBridgeError.invalidResponse }
                onSelectionChange?(selection)
            case "annotationClick":
                guard let id = payload as? String, !id.isEmpty else { throw EditorBridgeError.invalidResponse }
                onAnnotationClick?(id)
            case "error":
                guard let error = payload as? String else { throw EditorBridgeError.invalidResponse }
                report(error)
            default: throw EditorBridgeError.invalidResponse
            }
        } catch { report(error.localizedDescription) }
    }
    private func report(_ message: String) { lastError = message; onError?(message) }
}

@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: EditorController?
    init(owner: EditorController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}

extension EditorController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.targetFrame?.isMainFrame == true && navigationAction.request.url == entryURL
        decisionHandler(allowed ? .allow : .cancel)
    }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error.localizedDescription) }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error.localizedDescription) }
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        report("The manuscript editor process stopped. Reopen the window to restore the latest saved manuscript.")
    }
}

@MainActor
public struct ManuscriptEditor: NSViewRepresentable {
    public let controller: EditorController
    public init(controller: EditorController) { self.controller = controller }
    public func makeNSView(context: Context) -> WKWebView { controller.webView }
    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
