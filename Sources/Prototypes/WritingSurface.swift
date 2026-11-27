// Throwaway issue #8 comparison: Book for focused drafting, Desk for visible tools.
// Standalone target built by scripts/build-writing-surface-prototype.sh; no library or AI access.
import AppKit
import EditorHost
import GuildCore
import SwiftUI
import WebKit

private enum Layout: String, CaseIterable, Identifiable {
    case desk = "Desk", book = "Book"
    var id: Self { self }
    var key: String { rawValue.lowercased() }
}

private struct Block: Identifiable {
    let title: String
    let chapter: String
    let time: Int
    var opening = false
    var cap = false
    var paragraphs: [String] = []
    var intent: String? = nil
    var reference: String? = nil
    var id: String { title }
    var isLevel: Bool { intent != nil }
    var referenceState: String { reference == nil ? "Unbound" : "Reference supplied—not verified" }

    var manuscript: Manuscript {
        Manuscript(sceneID: id, html: paragraphs.map { "<p>\($0)</p>" }.joined(), text: paragraphs.joined(separator: "\n"))
    }

    static let sample = [
        Block(title: "The lantern keeper", chapter: "Prologue", time: 0, opening: true, cap: true, paragraphs: [
            "Nobody had lit the western lantern in nineteen years. On the last night of winter it came on by itself, a quiet flame behind glass the color of old honey.",
            "From across the water, a woman took off her hat and waited for the bell to answer. It never did."
        ]),
        Block(title: "The tide gate", chapter: "Chapter 1", time: 4, opening: true, cap: true, paragraphs: [
            "Mara reached the tide gate just as the bell let go of its last note. "
                + "The sound rolled out over the flats, low enough to stir the puddles. "
                + "At this hour the road should have been full of fish carts, but the only tracks led straight into the water.",
            "She took the little brass key from her pocket. Her brother had wrapped it in a scrap from a map, with one of the islands circled in black. There was nothing written on the other side.",
            "Beyond the gate, lamps moved down the embankment in twos. Mara stood very still until the last one passed, then put her hand on the latch. The iron was warm.",
            "Across the channel, on a shore that ought to have been dark, someone had left a lamp burning "
                + "inside a house with no roof. She watched it until her eyes began to water. Then she unlatched the gate."
        ]),
        Block(title: "Across the lock", chapter: "Chapter 1", time: 5, intent: "Separate Mara from the town before the tide turns."),
        Block(title: "The note under the door", chapter: "Chapter 1", time: 6, paragraphs: [
            "The lock house smelled of rain and machine oil. A note lay face down beneath the door, weighted with a clean white stone.",
            "Mara left the stone where it was. If someone came back for the note, she wanted them to know it had been read."
        ]),
        Block(title: "Up the signal tower", chapter: "Chapter 1", time: 7, intent: "Let the distant lantern become visible from above the flats.", reference: "signal-tower-01"),
        Block(title: "A voice in the fog", chapter: "Chapter 2", time: 8, opening: true, paragraphs: [
            "“Put the lamp out,” someone whispered on the stair. Mara held the flame away from her face. Through the fog a wet hand reached between the rails.",
            "She recognized the ring before she recognized the voice."
        ]),
        Block(title: "The far shore", chapter: "Epilogue", time: 12, opening: true, cap: true, paragraphs: [
            "By spring, even the children knew the lantern was not lit every night. They still looked for it on the way home."
        ])
    ]
}

@MainActor
private final class Comparison: ObservableObject {
    let editor = EditorController()
    let blocks = Block.sample
    @Published var layout: Layout = .book
    @Published private(set) var index = 1
    @Published var showOutline = false
    @Published var showFormat = false
    @Published var quiet = false { didSet { updateMarks() } }
    @Published var noteSelected = false
    @Published private(set) var error: String?
    private var drafts: [String: Manuscript] = [:]
    weak var window: NSWindow?
    private var started = false
    var block: Block { blocks[index] }
    var styleKey: String { "\(index)-\(layout.key)-\(showFormat)" }
    var canShowNote: Bool { index == 1 && !quiet }
    var web: WKWebView? { findWeb(in: window?.contentView) }

    func start() {
        guard !started else { return }
        started = true
        editor.onChange = { [weak self] in self?.drafts[$0.sceneID] = $0 }
        editor.onError = { [weak self] in self?.error = $0 }
        editor.onAnnotationClick = { [weak self] _ in self?.noteSelected = true }
        open(index)
    }

    func open(_ target: Int) {
        guard blocks.indices.contains(target) else { return }
        index = target
        noteSelected = false
        web?.isHidden = block.isLevel
        if block.isLevel {
            window?.makeFirstResponder(nil)
        } else {
            editor.load(drafts[block.id] ?? block.manuscript)
        }
        updateMarks()
    }

    func step(_ delta: Int) { open(index + delta) }

    func updateMarks() {
        guard canShowNote else { editor.annotate([]); return }
        let fixture = blocks[1].manuscript
        let quote = "the bell let go of its last note"
        let range = (fixture.text as NSString).range(of: quote)
        let anchor = TextAnchor(sceneID: fixture.sceneID, revision: fixture.revision, start: range.location,
                                length: range.length, quote: quote, prefix: "just as ", suffix: ". The sound")
        editor.annotate([AgentObservation(id: "fixture-note", agentID: "fixture", category: "Setting", confidence: 1,
                                          anchor: anchor, message: "Does the bell signal the gate closing?", evidence: [])])
    }

    func focusProse() {
        guard !block.isLevel, let web else { return }
        window?.makeFirstResponder(web)
        Task { _ = try? await web.evaluateJavaScript("document.querySelector('[contenteditable=true]')?.focus()") }
    }

    func style() async {
        guard !block.isLevel else { return }
        let target = block.id
        do {
            try await wait { self.editor.loadedSceneID == target && self.editor.isLoaded && self.web != nil }
            try Task.checkCancellation()
            guard block.id == target, let web else { return }
            _ = try await web.callAsyncJavaScript("""
                const root = document.documentElement;
                root.dataset.prototypeLayout = layout;
                root.dataset.prototypeFormat = reveal ? 'shown' : 'auto';
                root.dataset.prototypeCap = cap ? 'yes' : 'no';
                let sheet = document.getElementById('prototype-style');
                if (!sheet) {
                    sheet = document.createElement('style'); sheet.id = 'prototype-style';
                    document.head.append(sheet); sheet.textContent = css;
                }
                let header = document.getElementById('prototype-chapter');
                if (!header) {
                    header = document.createElement('header'); header.id = 'prototype-chapter';
                    header.append(document.createElement('span'), document.createElement('h1'));
                    document.getElementById('editor').prepend(header);
                }
                header.hidden = !chapter;
                header.firstChild.textContent = chapter;
                header.lastChild.textContent = title;
                return true;
                """, arguments: ["layout": layout.key, "reveal": showFormat, "cap": layout != .desk && block.cap,
                                  "chapter": block.opening ? block.chapter : "", "title": block.title, "css": Self.css],
                in: nil, contentWorld: .page)
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func findWeb(in view: NSView?) -> WKWebView? {
        guard let view else { return nil }
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = findWeb(in: child) { return web } }
        return nil
    }

    private static let css = """
        :root { color-scheme: light dark; --paper: #fcfaf4; --ink: #29261e; --muted: #726855; --rule: #e8dfcf; background: var(--paper); color: var(--ink); }
        @media (prefers-color-scheme: dark) { :root { --paper: #242321; --ink: #ebe3d2; --muted: #bcb198; --rule: #4a4236; } }
        #toolbar { background: var(--paper); border-color: var(--rule); }
        #toolbar button { color: var(--muted); }
        #toolbar button:hover, #toolbar button:focus-visible { background: var(--rule); color: var(--ink); }
        #toolbar .divider { background: var(--rule); }
        #editor { max-width: 790px; padding: 54px clamp(26px, 8vw, 94px) 160px; }
        :root:not([data-prototype-layout=desk]) #editor > :has(> wg-scroller) { border: 0; outline: none; }
        #editor [contenteditable] { font: 20px/1.68 Georgia, serif; letter-spacing: 0; min-height: 50vh; }
        #prototype-chapter { text-align: center; margin: 0 0 47px; }
        #prototype-chapter span { font: 600 12px system-ui; text-transform: uppercase; letter-spacing: .22em; color: var(--muted); }
        #prototype-chapter h1 { font: 38px/1.12 Georgia, serif; margin: 12px 0 0; }
        [data-prototype-layout=desk] #prototype-chapter { text-align: left; margin-bottom: 27px; }
        [data-prototype-layout=desk] #prototype-chapter h1 { font: 27px/1.2 system-ui; }
        [data-prototype-layout=desk] #editor [contenteditable] { font-size: 18px; }
        [data-prototype-layout=book][data-prototype-format=auto] #toolbar:not(:hover):not(:focus-within) { opacity: .55; }
        [data-prototype-cap=yes] #editor [contenteditable] > p:first-child::first-letter { float: left; color: var(--muted); font-size: 3.15em; line-height: .84; margin: .1em .1em 0 0; }
        """
}

private struct Surface: View {
    @ObservedObject var sample: Comparison

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WRITING SURFACE · PROTOTYPE").font(.caption.bold()).tracking(1.5)
                    Text("Which page would you draft on?").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Layout", selection: $sample.layout) {
                    ForEach(Layout.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 310)
                Spacer()
                Text("Sample only · edits not saved").font(.caption).foregroundStyle(.secondary)
            }.padding(14).background(.regularMaterial)
            Divider()
            HStack(spacing: 0) {
                if sample.layout == .desk { outline.frame(width: 210); Divider() }
                VStack(spacing: 0) {
                    navigation
                    Divider()
                    ZStack {
                        ManuscriptEditor(controller: sample.editor)
                            .opacity(sample.block.isLevel ? 0 : 1)
                            .allowsHitTesting(!sample.block.isLevel)
                            .accessibilityHidden(sample.block.isLevel)
                        if sample.block.isLevel { level }
                    }
                }
                if sample.canShowNote && (sample.layout == .desk || sample.noteSelected) {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Sample Guild note", systemImage: "text.bubble").font(.headline)
                        Text("Does the bell signal the gate closing?")
                        Text("Fixed example; no review runs in this prototype.").font(.caption).foregroundStyle(.secondary)
                        if sample.layout != .desk { Button("Close Note") { sample.noteSelected = false } }
                        Spacer()
                    }.padding(18).frame(width: 220, alignment: .leading)
                    .background(.regularMaterial)
                }
            }
            if let error = sample.error { Text(error).foregroundStyle(.red).padding() }
        }
        .frame(minWidth: 830, minHeight: 610)
        .onAppear { sample.start() }
        .task(id: sample.styleKey) { await sample.style() }
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            if sample.layout != .desk {
                Button { sample.showOutline.toggle() } label: { Label("Contents", systemImage: "list.bullet") }
                    .popover(isPresented: $sample.showOutline, arrowEdge: .bottom) { outline.frame(width: 302, height: 440) }
            }
            Button { sample.step(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous Block")
                .help(blockHint(-1, key: "⌥⌘←"))
                .disabled(sample.index == 0)
            Button { sample.step(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next Block")
                .help(blockHint(1, key: "⌥⌘→"))
                .disabled(sample.index == sample.blocks.count - 1)
            Text("\(sample.block.chapter) / \(sample.block.isLevel ? "Level · " : "")\(sample.block.title)")
                .font(.callout).lineLimit(1).foregroundStyle(.secondary)
            Spacer()
            if sample.layout != .desk && !sample.block.isLevel {
                Toggle("Formatting", isOn: $sample.showFormat).toggleStyle(.button)
            }
            Toggle(isOn: $sample.quiet) { Label("Quiet Time", systemImage: "moon") }
                .toggleStyle(.button).help("Hide Guild notes and marks, independently of layout (⌥⌘Q)")
        }.padding(.horizontal, 13).padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func blockHint(_ delta: Int, key: String) -> String {
        let index = sample.index + delta
        guard sample.blocks.indices.contains(index) else { return delta < 0 ? "First block" : "Last block" }
        let block = sample.blocks[index]
        return "\(block.chapter) / \(block.isLevel ? "Level · " : "")\(block.title) (\(key))"
    }

    private var outline: some View {
        let blocks = sample.blocks
        let starts = blocks.indices.filter { $0 == 0 || blocks[$0 - 1].chapter != blocks[$0].chapter }
        return List {
            ForEach(starts, id: \.self) { start in
                let end = starts.first { $0 > start } ?? blocks.count
                Section(blocks[start].chapter) {
                    ForEach(start..<end, id: \.self) { index in
                        let block = blocks[index]
                        Button {
                            sample.open(index)
                            sample.showOutline = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(block.isLevel ? "Level · " : "")\(block.title)")
                                    .fontWeight(index == sample.index ? .semibold : .regular)
                                if block.isLevel {
                                    Text(block.referenceState).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.listStyle(.sidebar).accessibilityLabel("Manuscript contents")
    }

    private var level: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(sample.block.chapter.uppercased()).font(.caption.bold()).tracking(2)
                .foregroundStyle(.secondary)
            Label("LEVEL · NOT PLAYABLE IN THIS WORKSPACE", systemImage: "square.stack.3d.up")
                .font(.caption.bold()).tracking(1.4).foregroundStyle(.secondary)
            Text(sample.block.title).font(.system(size: 31, design: .serif))
            Text("Story time \(sample.block.time) · \(sample.block.referenceState)").foregroundStyle(.secondary)
            Divider()
            Text("Intent note · not manuscript prose").font(.caption.bold()).foregroundStyle(.secondary)
            Text(sample.block.intent ?? "")
            if let reference = sample.block.reference { Text(reference).font(.body.monospaced()).textSelection(.enabled) }
        }.padding(26).frame(maxWidth: 525).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
            .accessibilityIdentifier("level-details")
    }
}

@main
@MainActor
private final class WritingSurfaceApp: NSObject, NSApplicationDelegate {
    private lazy var sample = Comparison()
    private var window: NSWindow?

    static func main() {
        let application = NSApplication.shared
        let delegate = WritingSurfaceApp()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1090, height: 750),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        self.window = window
        sample.window = window
        window.title = "The Tide Gate — Writing Surface Prototype"
        window.contentView = NSHostingView(rootView: Surface(sample: sample))
        window.minSize = NSSize(width: 830, height: 640)
        window.center()
        installMenu()
        sample.start()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let path = CommandLine.arguments.dropFirst().first, path.hasPrefix("/") {
            Task { await sample.smoke(in: URL(fileURLWithPath: path, isDirectory: true)) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func installMenu() {
        let menu = NSMenu()
        let application = NSMenuItem()
        application.submenu = NSMenu()
        application.submenu?.addItem(withTitle: "Quit Prototype", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(application)
        let manuscript = NSMenuItem()
        let actions = NSMenu(title: "Manuscript")
        for (label, action, key) in [
            ("Previous Block", #selector(previous), "\u{F702}"),
            ("Next Block", #selector(next), "\u{F703}"),
            ("Focus Prose", #selector(focusProse), "e"),
            ("Toggle Formatting", #selector(toggleFormat), "f"),
            ("Toggle Quiet Time", #selector(toggleQuiet), "q")
        ] {
            let item = actions.addItem(withTitle: label, action: action, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = [.command, .option]
        }
        manuscript.submenu = actions
        menu.addItem(manuscript)
        NSApp.mainMenu = menu
    }

    @objc private func previous() { sample.step(-1) }
    @objc private func next() { sample.step(1) }
    @objc private func focusProse() { sample.focusProse() }
    @objc private func toggleFormat() { sample.showFormat.toggle() }
    @objc private func toggleQuiet() { sample.quiet.toggle() }
}

private struct SmokeFailure: LocalizedError {
    let label: String
    init(_ label: String) { self.label = label }
    var errorDescription: String? { label }
}

@MainActor
private func wait(_ condition: () async throws -> Bool) async throws {
    for _ in 0..<120 {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw SmokeFailure("Timed out waiting for the native editor")
}

private extension Comparison {
    func smoke(in output: URL) async {
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            print("PROTOTYPE START: window=\(window != nil) web=\(web != nil)")
            fflush(nil)
            try await wait { self.editor.isLoaded && self.web?.window != nil }
            guard let web, let window, web.url?.path.hasPrefix(Bundle.main.bundleURL.path + "/") == true else {
                throw SmokeFailure("Actual native editor bundle did not load")
            }
            print("PROTOTYPE WINDOW ID \(window.windowNumber)")
            func js(_ expression: String) async throws -> Bool { (try await web.evaluateJavaScript(expression)) as? Bool == true }
            func snapshot(_ name: String, includeEditor: Bool = true) async throws {
                guard let content = window.contentView,
                      let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                    throw SmokeFailure("No native window content to capture")
                }
                let editorImage = includeEditor ? try await web.takeSnapshot(configuration: nil) : nil
                content.layoutSubtreeIfNeeded()
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let image = NSImage(size: content.bounds.size)
                image.lockFocus()
                bitmap.draw(in: content.bounds)
                if let editorImage {
                    var frame = content.convert(web.bounds, from: web)
                    if content.isFlipped { frame.origin.y = content.bounds.height - frame.maxY }
                    editorImage.draw(in: frame)
                }
                image.unlockFocus()
                guard let tiff = image.tiffRepresentation, let rendered = NSBitmapImageRep(data: tiff),
                      let png = rendered.representation(using: .png, properties: [:]) else {
                    throw SmokeFailure("No composited prototype snapshot")
                }
                try png.write(to: output.appendingPathComponent(name + ".png"))
            }
            func styled(_ variant: Layout) async throws {
                layout = variant
                try await wait { try await js("document.documentElement.dataset.prototypeLayout === '\(variant.key)'") }
                try await Task.sleep(for: .milliseconds(160))
            }
            for variant in Layout.allCases {
                try await styled(variant)
                try await snapshot(variant.key)
            }
            guard try await js("getComputedStyle(document.querySelector('#toolbar')).display !== 'none'") else {
                throw SmokeFailure("Book hid its formatting ribbon")
            }
            showFormat = true
            try await wait { try await js("getComputedStyle(document.querySelector('#toolbar')).opacity === '1'") }
            showFormat = false
            try await wait { try await js("!!document.querySelector('[data-annotation-id]')") }
            quiet = true
            try await wait { try await js("!document.querySelector('[data-annotation-id]')") }
            try await styled(.desk)
            guard quiet, try await js("!document.querySelector('[data-annotation-id]')") else {
                throw SmokeFailure("Layout switch changed Quiet Time")
            }
            quiet = false
            try await wait { try await js("!!document.querySelector('[data-annotation-id]')") }
            try await styled(.book)
            guard try await js("getComputedStyle(document.querySelector('[contenteditable] > p'), '::first-letter').float === 'left'") else {
                throw SmokeFailure("Book opener lacks its drop cap")
            }
            let before = try await editor.export()
            guard !before.html.contains("prototype-chapter") else { throw SmokeFailure("UI heading leaked into document export") }
            try await editor.setSelection(start: before.text.utf16.count, length: 0)
            focusProse()
            try await wait { try await js("document.activeElement.isContentEditable") }
            guard try await js("document.execCommand('insertText', false, ' Smoke edit.')") else { throw SmokeFailure("Native typing was rejected") }
            try await wait { try await self.editor.getText().hasSuffix(" Smoke edit.") }
            let selection = try await editor.getSelection()
            try await styled(.desk)
            guard try await editor.getSelection() == selection else {
                throw SmokeFailure("Layout switch changed the Wordgard selection")
            }
            guard try await editor.getText().hasSuffix(" Smoke edit.") else { throw SmokeFailure("Layout switch discarded the draft") }
            try await editor.applyFormatting(.undo)
            guard try await editor.getText() == before.text else { throw SmokeFailure("Layout switch discarded undo history") }
            try await styled(.book)
            open(2)
            try await wait { web.isHidden }
            guard block.isLevel && block.reference == nil else { throw SmokeFailure("Unbound Level navigation failed") }
            try await Task.sleep(for: .milliseconds(160))
            try await snapshot("level", includeEditor: false)
            step(1)
            try await wait { self.editor.loadedSceneID == self.block.id && self.editor.isLoaded }
            try await wait { try await js("document.querySelector('#prototype-chapter').hidden") }
            guard try await editor.getText().hasPrefix("The lock house") else { throw SmokeFailure("Next Scene did not load") }
            open(5)
            try await wait { self.editor.loadedSceneID == self.block.id && self.editor.isLoaded }
            try await wait { try await js("document.querySelector('#prototype-chapter span').textContent === 'Chapter 2' && document.documentElement.dataset.prototypeCap === 'no'") }
            try await snapshot("dialogue-opening")
            open(1)
            try await styled(.book)
            print("PROTOTYPE SMOKE PASS: packaged WKWebView; Book/Desk; formatting and independent Quiet Time; "
                  + "chapter and dialogue openers; text, selection, and undo; Level-to-Scene")
            fflush(nil)
        } catch {
            print("PROTOTYPE SMOKE FAIL: \(error.localizedDescription)")
            print("EDITOR: ready=\(editor.isReady) scene=\(editor.loadedSceneID ?? "none") url=\(web?.url?.path ?? "none")")
            print("BRIDGE: \(editor.lastError ?? self.error ?? "no reported error")")
            fflush(nil)
            exit(EXIT_FAILURE)
        }
    }
}
