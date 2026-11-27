// Issue #9: chapter list, presentation-only reorder, explicit promotion, and fixed passage ghosts in Wordgard.
import AppKit
import EditorHost
import GuildCore
import SwiftUI
import WebKit
import UniformTypeIdentifiers

@MainActor
final class OutlineSession: ObservableObject {
    struct Creation: Identifiable {
        let id = UUID()
        var slot: OutlineFixture.Slot
        var ideaID: String?
        var kind: OutlineFixture.Kind?
        var title = ""
        var time = 7
        var note = ""
        var reference = ""
    }
    @Published var fixture = OutlineFixture()
    @Published private(set) var selected = "S1"
    @Published var feedback = "Drag a row to change reading order, not story time."
    @Published var creation: Creation?
    @Published var showGhost = false
    @Published var showResolved = false
    @Published var drag = OutlineDrag()
    @Published var error: String?
    let editor = EditorController()
    weak var window: NSWindow?

    var block: OutlineFixture.Block { fixture.blocks[selected]! }
    var ghost: OutlineFixture.Ghost? { fixture.ghosts[selected] }
    var resolved: [OutlineFixture.Ghost] { fixture.resolvedGhosts[selected] ?? [] }
    var adjacent: (previous: String?, next: String?) {
        let ids = fixture.presentation
        let position = ids.firstIndex(of: selected)!
        return (position > 0 ? ids[position - 1] : nil, position + 1 < ids.count ? ids[position + 1] : nil)
    }

    init() {
        editor.onChange = { [weak self] draft in
            guard let self, self.fixture.blocks[draft.sceneID]?.prose != draft else { return }
            let wasActive = self.ghost?.state == .active
            self.fixture.receive(draft)
            if draft.sceneID == self.selected, wasActive && self.ghost?.state == .unplaced {
                self.refreshGhost()
                self.showGhost = true
                self.feedback = "The passage changed. Its ghost note is still here, but needs placement."
            }
        }
        editor.onError = { [weak self] in self?.error = $0 }
        editor.onAnnotationClick = { [weak self] id in
            if self?.ghost?.id == id { self?.showGhost = true }
        }
        editor.load(block.prose!)
        refreshGhost()
    }

    func open(_ id: String) {
        guard id != selected, let block = fixture.blocks[id], !editor.isLoading else { return }
        selected = id
        showGhost = false
        showResolved = false
        if let prose = block.prose { editor.load(prose) }
        refreshGhost()
    }

    func drop(_ payload: String, at slot: OutlineFixture.Slot) -> Bool {
        if let idea = fixture.ideas.first(where: { $0.id == payload }) {
            creation = Creation(slot: slot, ideaID: idea.id, title: idea.title, note: idea.note)
            return true
        }
        guard fixture.blocks[payload] != nil else { return false }
        if fixture.move(payload, to: slot) {
            feedback = "Moved \(fixture.blocks[payload]!.title) to \(fixture.placement(payload)). Story time unchanged."
        } else { feedback = "No move. The card is already there, or that destination is no longer available." }
        return true
    }

    func undoMove() {
        fixture.undoMove()
        feedback = "Restored the previous manuscript order. Story time unchanged."
    }

    func create(_ draft: Creation) {
        guard let kind = draft.kind,
              let id = fixture.create(kind: kind, title: draft.title, time: draft.time, note: draft.note,
                                      reference: draft.reference, at: draft.slot, ideaID: draft.ideaID) else { return }
        creation = nil
        feedback = "\(draft.ideaID == nil ? "Created" : "Promoted as") \(kind.rawValue) · \(fixture.placement(id))."
        open(id)
    }

    func refreshGhost() {
        // Borrow only the existing decoration transport. This is a writer note, not a Guild finding.
        if let ghost, ghost.state == .active {
            editor.annotate([AgentObservation(id: ghost.id, agentID: "scratch-writer-note", category: "Ghost note",
                                              confidence: 1, anchor: ghost.lastAnchor, message: ghost.text, evidence: [])])
        } else { editor.annotate([]) }
    }

    func resolveGhost() {
        guard let ghost = fixture.ghosts.removeValue(forKey: selected) else { return }
        fixture.resolvedGhosts[selected, default: []].append(ghost)
        showGhost = false
        showResolved = true
        refreshGhost()
        feedback = "Resolved the ghost note. It is still available under Resolved Notes."
    }

    func placeGhost(text: String?) async {
        let id = selected
        guard editor.loadedSceneID == id, editor.isLoaded else { return }
        do {
            let selection = try await editor.getSelection()
            let prose = try await editor.export()
            guard selected == id, prose.sceneID == id else { return }
            let range = NSRange(location: selection.start, length: selection.length)
            guard !selection.text.isEmpty, !selection.text.contains("\n"),
                  let match = Range(range, in: prose.text), prose.text[match] == selection.text else {
                feedback = "Select a passage within one paragraph first."; return
            }
            fixture.receive(prose)
            let anchor = AnchorResolver.make(manuscript: prose, range: range)
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ghost == nil {
                fixture.ghosts[id] = OutlineFixture.Ghost(text: text, lastAnchor: anchor)
            } else if ghost?.state == .unplaced {
                fixture.ghosts[id]?.lastAnchor = anchor
                fixture.ghosts[id]?.state = .active
            } else { return }
            refreshGhost()
            showGhost = true
            feedback = "Attached a ghost note. Manuscript text unchanged."
        } catch { self.error = error.localizedDescription }
    }

    func beginDrag(_ id: String) { drag = OutlineDrag(source: id) }
    func endDrag() { drag = OutlineDrag() }
}

private struct OutlineRoot: View {
    @State var session: OutlineSession
    var body: some View {
        OutlineSurface(session: session, editor: session.editor, reset: {
            let replacement = OutlineSession()
            replacement.window = session.window
            session = replacement
        })
            .id(ObjectIdentifier(session))
    }
}

private struct OutlineSurface: View {
    @ObservedObject var session: OutlineSession
    @ObservedObject var editor: EditorController
    var reset: () -> Void
    @State private var showGuide = false
    @State private var showReset = false
    @State private var ghostDraft: String?
    @State private var inlineGhost = true
    @State private var ideaTitle = ""
    @State private var ideaNote = ""
    @State private var ideaEditor = false
    @State private var showsChronology = true
    private var dragGap: OutlineFixture.Slot? { session.drag.gap }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CARDS & NOTES  /  ISSUE 9").font(.caption.bold()).tracking(2)
                    Text("Can you plan a manuscript without changing what happened?").font(.headline)
                }
                Spacer()
                Text("Sample story · nothing saved").foregroundStyle(.secondary)
                Button("Walkthrough") { showGuide = true }
                Button("Reset Sample") { showReset = true }
            }.padding(16)
            Divider()
            HSplitView {
                planning.frame(minWidth: 465, idealWidth: 550)
                workspace.frame(minWidth: 420, idealWidth: 550)
            }
            Divider()
            Text(session.error ?? session.feedback)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: session.selected) { ghostDraft = nil }
        .onChange(of: canDraft, initial: true) {
            guard let window = session.window, let web = findOutlineWeb(in: window.contentView) else { return }
            if !canDraft, let responder = window.firstResponder as? NSView,
               responder === web || responder.isDescendant(of: web) {
                window.makeFirstResponder(nil)
            }
            web.isHidden = !canDraft
        }
        .sheet(item: $session.creation) { draft in
            CreationForm(draft: draft, fixture: session.fixture, create: session.create) { session.creation = nil }
        }
        .sheet(isPresented: $showGuide) { guide }
        .sheet(isPresented: $ideaEditor) {
            VStack(alignment: .leading, spacing: 12) {
                Text("New loose idea").font(.title2)
                TextField("Title", text: $ideaTitle)
                TextField("Idea note", text: $ideaNote, axis: .vertical).lineLimit(3...5)
                HStack {
                    Button("Cancel") { ideaEditor = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Park Idea") {
                        session.fixture.ideas.append(.init(id: UUID().uuidString, title: ideaTitle, note: ideaNote))
                        ideaEditor = false
                        session.feedback = "Parked a loose idea. It has no manuscript position or story time."
                    }.keyboardShortcut(.defaultAction).disabled(ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(22).frame(width: 390)
        }
        .confirmationDialog("Discard these sample changes?", isPresented: $showReset) {
            Button("Reset Sample", role: .destructive, action: reset)
        }
    }

    private var planning: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Manuscript order").font(.title3.bold())
                Spacer()
                Button("Undo Move", action: session.undoMove).disabled(session.fixture.priorOrder == nil)
            }.padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.fixture.chapters) { chapter in chapterGroup(chapter) }
                }.padding(12)
            }
            Divider()
            ideas
            Divider()
            DisclosureGroup("Story time · independent of manuscript order", isExpanded: $showsChronology) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(session.fixture.chronology) { block in
                            Button { session.open(block.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("T\(block.time) · \(block.kind.rawValue)").font(.caption.bold())
                                    Text(block.title).lineLimit(1)
                                }.padding(7)
                            }.buttonStyle(.borderless).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 5))
                        }
                    }.padding(.top, 5)
                }
            }.padding(10).background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func chapterGroup(_ chapter: OutlineFixture.Chapter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.fixture.chapterLabel(chapter.id)).font(.headline)
                Spacer()
                Button("Add Block…") { session.creation = .init(slot: .init(chapter: chapter.id)) }
            }.padding(.bottom, 4)
            if chapter.blocks.isEmpty {
                let slot = OutlineFixture.Slot(chapter: chapter.id)
                Text("Empty chapter").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: ManuscriptRowDrop.height, alignment: .leading)
                    .background(dragGap == slot ? Color.accentColor.opacity(0.15) : .clear)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if dragGap == slot { insertionLine }
                    }
                    .onDrop(of: [UTType.plainText], delegate: ManuscriptRowDrop(
                        above: slot, below: slot, session: session
                    ))
            }
            ForEach(chapter.blocks, id: \.self) { id in
                let above = OutlineFixture.Slot(chapter: chapter.id, before: id)
                let below = OutlineFixture.Slot(chapter: chapter.id, before: chapter.block(after: id))
                manuscriptRow(session.fixture.blocks[id]!, above: above, below: below)
            }
        }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
    }

    private func manuscriptRow(_ block: OutlineFixture.Block, above: OutlineFixture.Slot,
                               below: OutlineFixture.Slot) -> some View {
        let selected = session.selected == block.id
        return ZStack {
            HStack(spacing: 8) {
                dragGrip(block.id, title: block.title)
                Button { session.open(block.id) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: block.kind == .scene ? "text.alignleft" : "gamecontroller")
                            .frame(width: 17).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.title).font(.callout.bold()).lineLimit(1)
                            Text(summary(block)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(block.kind.rawValue) · Story time \(block.time)")
                            if block.kind == .level { Text(block.referenceState) }
                        }.font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Menu {
                    moveOptions(block)
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Move \(block.title)").menuStyle(.borderlessButton).fixedSize()
            }.padding(.horizontal, 8)
                .frame(height: 35)
                .background(selected ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 5))
                .offset(y: dragGap == above ? 7 : dragGap == below ? -7 : 0)
                .contextMenu {
                    Button("Open \(block.kind.rawValue)") { session.open(block.id) }
                    Menu("Move To") { moveOptions(block) }
                    Divider()
                    Button("Add Block Above…") { session.creation = .init(slot: above) }
                    Button("Add Block Below…") { session.creation = .init(slot: below) }
                }
        }
        .frame(height: ManuscriptRowDrop.height)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if dragGap == above { insertionLine }
        }
        .overlay(alignment: .bottom) {
            if below.before == nil, dragGap == below { insertionLine }
        }
        .animation(.easeOut(duration: 0.13), value: dragGap)
        .onDrop(of: [UTType.plainText], delegate: ManuscriptRowDrop(
            above: above, below: below, session: session
        ))
    }

    private var insertionLine: some View {
        Capsule().fill(Color.accentColor).frame(height: 2).padding(.horizontal, 8).allowsHitTesting(false)
    }

    private func dragGrip(_ id: String, title: String) -> some View {
        OutlineDragGrip(id: id, begin: session.beginDrag, end: session.endDrag)
            .frame(width: 20, height: 27)
            .help("Drag to move \(title)")
            .accessibilityHidden(true)
    }

    private func moveOptions(_ block: OutlineFixture.Block) -> some View {
        ForEach(session.fixture.slots.filter { $0.before != block.id }, id: \.self) { slot in
            Button(session.fixture.slotLabel(slot)) { _ = session.drop(block.id, at: slot) }
        }
    }

    private func summary(_ block: OutlineFixture.Block) -> String {
        if !block.note.isEmpty { return block.note }
        if let prose = block.prose, !prose.text.isEmpty { return String(prose.text.prefix { $0 != "\n" }) }
        return block.kind == .level ? "No intent note yet" : "Empty draft"
    }

    private var ideas: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Loose ideas").font(.headline)
                Spacer()
                Button("New Idea…") { ideaTitle = ""; ideaNote = ""; ideaEditor = true }
            }
            Text("Not in the manuscript · no story time").font(.caption).foregroundStyle(.secondary)
            if session.fixture.ideas.isEmpty {
                Text("No parked ideas").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(session.fixture.ideas) { idea in ideaCard(idea) }
                    }
                }
            }
        }.padding(10).background(Color(nsColor: .controlBackgroundColor))
    }

    private func ideaCard(_ idea: OutlineFixture.Idea) -> some View {
        HStack(alignment: .top) {
            dragGrip(idea.id, title: idea.title)
            VStack(alignment: .leading, spacing: 3) {
                Text(idea.title).font(.callout.bold()).lineLimit(1)
                if !idea.note.isEmpty { Text(idea.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            Menu("Promote…") {
                promotionOptions(idea)
            }.menuStyle(.borderlessButton).fixedSize()
        }.frame(width: 335).padding(6).background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .contextMenu { Menu("Promote To") { promotionOptions(idea) } }
            .onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
                guard let id = session.drag.source, id != idea.id,
                      let source = session.fixture.ideas.firstIndex(where: { $0.id == id }) else { return false }
                session.endDrag()
                let moved = session.fixture.ideas.remove(at: source)
                let target = session.fixture.ideas.firstIndex(where: { $0.id == idea.id })!
                session.fixture.ideas.insert(moved, at: target)
                session.feedback = "Reordered loose ideas. Neither gained a manuscript position."
                return true
            }
    }

    private func promotionOptions(_ idea: OutlineFixture.Idea) -> some View {
        ForEach(session.fixture.slots, id: \.self) { slot in
            Button(session.fixture.slotLabel(slot)) { _ = session.drop(idea.id, at: slot) }
        }
    }

    private var canDraft: Bool { session.block.kind == .scene && editor.isLoaded && editor.loadedSceneID == session.selected }
    private var workspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.fixture.placement(session.selected)).font(.caption).foregroundStyle(.secondary)
                    Text(session.block.title).font(.title2.bold())
                    Text("\(session.block.kind.rawValue) · Story time \(session.block.time)").foregroundStyle(.secondary)
                }
                Spacer()
                let adjacent = session.adjacent
                Button { if let id = adjacent.previous { session.open(id) } } label: { Image(systemName: "chevron.left") }
                    .disabled(adjacent.previous == nil || editor.isLoading).help("Previous manuscript block").accessibilityLabel("Previous manuscript block")
                Button { if let id = adjacent.next { session.open(id) } } label: { Image(systemName: "chevron.right") }
                    .disabled(adjacent.next == nil || editor.isLoading).help("Next manuscript block").accessibilityLabel("Next manuscript block")
            }.padding(14)
            Divider()
            ZStack(alignment: .topLeading) {
                ManuscriptEditor(controller: editor).opacity(canDraft ? 1 : 0)
                    .allowsHitTesting(canDraft).accessibilityHidden(!canDraft)
                    .task(id: appearance) { await renderGhost() }
                if session.block.kind == .level { levelDetails }
                else if !canDraft { ProgressView("Loading Scene…").padding() }
            }.frame(maxHeight: .infinity)
            if session.block.kind == .scene {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Outline note (list only)", text: binding(\.note), axis: .vertical).lineLimit(2...4)
                        .accessibilityLabel("Outline note (list only)")
                    HStack {
                        if let ghost = session.ghost {
                            Button("Ghost note · \(ghost.state.rawValue)") { session.showGhost.toggle() }
                        } else {
                            Button("Attach Ghost to Selection…") { ghostDraft = "" }.disabled(!canDraft)
                        }
                        Spacer()
                        if !session.resolved.isEmpty {
                            Button("Resolved Notes (\(session.resolved.count))") { session.showResolved.toggle() }
                        }
                        if session.ghost?.state == .active {
                            Toggle("Show inline", isOn: $inlineGhost).toggleStyle(.checkbox)
                        }
                    }
                    if let ghost = session.ghost, session.showGhost { ghostDetails(ghost) }
                    if session.showResolved, !session.resolved.isEmpty { resolvedNotes }
                    if ghostDraft != nil {
                        TextField("Ghost note for this selection", text: Binding(get: { ghostDraft ?? "" }, set: { ghostDraft = $0 }))
                        HStack {
                            Button("Cancel") { ghostDraft = nil }
                            Button("Attach") {
                                let text = ghostDraft
                                ghostDraft = nil
                                Task { await session.placeGhost(text: text) }
                            }.disabled(ghostDraft?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                        }
                    }
                }.padding(12).id(session.selected)
            }
        }
    }

    private var levelDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Level · nonplayable in this workspace", systemImage: "gamecontroller").font(.headline)
                Text(session.block.referenceState).font(.callout).foregroundStyle(.secondary)
                TextField("Title", text: binding(\.title))
                TextField("Intent note (optional)", text: binding(\.note), axis: .vertical).lineLimit(3...6)
                Stepper("Story time \(session.block.time)", value: binding(\.time))
                TextField("Gameplay reference (optional)", text: binding(\.reference))
                HStack {
                    Button("Copy Reference") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.block.reference, forType: .string)
                    }
                    Button("Clear Reference") { session.fixture.blocks[session.selected]?.reference = "" }
                }.disabled(session.block.reference.isEmpty)
                Text("A reference is only a locator. It does not verify gameplay or record a story event.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(16)
        }.background(.background)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<OutlineFixture.Block, T>) -> Binding<T> {
        let id = session.selected
        return Binding(get: { session.fixture.blocks[id]![keyPath: keyPath] },
                       set: { session.fixture.blocks[id]?[keyPath: keyPath] = $0 })
    }

    private func ghostDetails(_ ghost: OutlineFixture.Ghost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ghost.text).font(.callout)
            Text("\(ghost.state == .active ? "Passage" : "Last passage"): “\(ghost.lastAnchor.quote)”")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if ghost.state == .active {
                    Button("Go to Passage") { editor.scrollTo(ghost.id) }
                } else {
                    Button("Attach to Selection") { Task { await session.placeGhost(text: nil) } }
                }
                Spacer()
                Button("Resolve", action: session.resolveGhost).help("Hide inline; keep the note with this Scene")
            }
        }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 6))
    }

    private var resolvedNotes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                Text("Resolved · retained with this Scene, not shown inline").font(.caption.bold())
                ForEach(session.resolved.reversed()) { ghost in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ghost.text)
                        Text("Last passage: “\(ghost.lastAnchor.quote)”").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
        }.frame(maxHeight: 105)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 6))
    }

    private var appearance: String {
        "\(canDraft)\(session.selected)\(session.ghost?.id ?? "")\(session.ghost?.state.rawValue ?? "")\(inlineGhost)"
    }

    private func renderGhost() async {
        guard canDraft, let web = findOutlineWeb(in: session.window?.contentView) else { return }
        let ghost = session.ghost.flatMap { $0.state == .active ? $0 : nil }
        do {
            _ = try await web.callAsyncJavaScript("""
                // Decorations only. No node or text is inserted into Wordgard's document.
                const root = document.documentElement;
                if (!document.getElementById('outline-ghost-style')) {
                    const sheet = document.createElement('style'); sheet.id = 'outline-ghost-style';
                    sheet.textContent = `[data-ghost-mark] { background: transparent !important;
                      border-bottom: 1px dotted currentColor; }
                      [data-ghost-copy]::after { content: ' [Ghost: ' attr(data-ghost-copy) ']';
                        color: GrayText; font-style: italic; white-space: normal; user-select: none; }`;
                    document.head.append(sheet);
                    const decorate = () => {
                        const marks = Array.from(document.querySelectorAll('[data-annotation-id]'));
                        for (const mark of marks) {
                            if (mark.dataset.annotationId === root.dataset.ghostId) {
                                mark.dataset.ghostMark = '';
                                mark.title = 'Open writer ghost note';
                            }
                            delete mark.dataset.ghostCopy;
                        }
                        const last = marks.findLast(mark => mark.dataset.annotationId === root.dataset.ghostId);
                        if (last && root.dataset.ghostText) last.dataset.ghostCopy = root.dataset.ghostText;
                    };
                    new MutationObserver(decorate).observe(document.getElementById('editor'), { childList: true, subtree: true });
                    root.addEventListener('outline-ghost-update', decorate);
                }
                root.dataset.ghostId = id; root.dataset.ghostText = note;
                root.dispatchEvent(new Event('outline-ghost-update'));
                return true;
                """, arguments: ["id": ghost?.id ?? "", "note": inlineGhost ? ghost?.text ?? "" : ""],
                in: nil, contentWorld: .page)
        } catch { if !Task.isCancelled { session.error = error.localizedDescription } }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Try the manuscript list").font(.title2.bold())
            Text("1. Grab the handle on ‘The first flood’ and hover over the top of ‘At the tide gate’. "
                 + "Compare both orders, then Undo Move. Right-click a row to try Move To instead.")
            Text("2. Drag ‘A second key’ by its handle above or below a row. Cancel once, then promote it as a Scene.")
            Text("3. Use Next from ‘At the tide gate’ to enter ‘Cross the lock’, then Next again. Try recording and clearing a reference.")
            Text("4. In ‘At the tide gate’, type past the ghost note, then Resolve and reopen Resolved Notes. "
                 + "After Reset, replace the marked passage and see what happens.")
            Text("What surprised you? Try ‘Show inline’ off to compare a passage marker without note text.")
                .foregroundStyle(.secondary)
            Button("Done") { showGuide = false }.keyboardShortcut(.defaultAction)
        }.padding(24).frame(width: 510)
    }
}

struct OutlineDrag {
    var source: String?
    var gap: OutlineFixture.Slot?
    var hoveredRow: OutlineFixture.Slot?
}

private struct ManuscriptRowDrop: DropDelegate {
    static let height: CGFloat = 42
    let above: OutlineFixture.Slot
    let below: OutlineFixture.Slot
    let session: OutlineSession

    private func slot(_ info: DropInfo) -> OutlineFixture.Slot {
        info.location.y < Self.height / 2 ? above : below
    }

    func validateDrop(info: DropInfo) -> Bool { session.drag.source != nil }
    func dropEntered(info: DropInfo) { _ = dropUpdated(info: info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard session.drag.source != nil else { return DropProposal(operation: .forbidden) }
        let target = slot(info)
        if session.drag.gap != target || session.drag.hoveredRow != above {
            session.drag.gap = target
            session.drag.hoveredRow = above
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard session.drag.hoveredRow == above else { return }
        session.drag.gap = nil
        session.drag.hoveredRow = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let source = session.drag.source else { return false }
        session.endDrag()
        return session.drop(source, at: slot(info))
    }
}

// AppKit reports drag completion even on Escape or release outside the list.
private struct OutlineDragGrip: NSViewRepresentable {
    let id: String
    let begin: (String) -> Void
    let end: () -> Void

    func makeNSView(context: Context) -> Grip {
        let grip = Grip()
        grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        grip.contentTintColor = .secondaryLabelColor
        return grip
    }

    func updateNSView(_ grip: Grip, context: Context) {
        grip.id = id
        grip.begin = begin
        grip.end = end
    }

    final class Grip: NSImageView, NSDraggingSource {
        var id = ""
        var begin: ((String) -> Void)?
        var end: (() -> Void)?
        private var dragging = false

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) { }
        override func mouseDragged(with event: NSEvent) {
            guard !dragging, let image else { return }
            dragging = true
            begin?(id)
            let item = NSDraggingItem(pasteboardWriter: id as NSString)
            let pointer = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: pointer.x - 10, y: pointer.y - 10, width: 20, height: 20), contents: image)
            let session = beginDraggingSession(with: [item], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = false
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            dragging = false
            end?()
        }
    }
}

private struct CreationForm: View {
    @State var draft: OutlineSession.Creation
    var fixture: OutlineFixture
    var create: (OutlineSession.Creation) -> Void
    var cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.ideaID == nil ? "Add Manuscript Block" : "Promote Loose Idea").font(.title2.bold())
            Text("Choose a block type explicitly. The note stays out of prose and establishes no story event.")
                .foregroundStyle(.secondary)
            HStack {
                Text("Type")
                Picker("Type", selection: $draft.kind) {
                    Text("Choose…").tag(nil as OutlineFixture.Kind?)
                    ForEach(OutlineFixture.Kind.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }.labelsHidden().pickerStyle(.segmented)
            }
            Picker("Manuscript placement", selection: $draft.slot) {
                ForEach(fixture.slots, id: \.self) { Text(fixture.slotLabel($0)).tag($0) }
            }
            Stepper("Story time \(draft.time)", value: $draft.time)
            TextField("Title", text: $draft.title)
            TextField(draft.kind == .level ? "Intent note (optional)" : "Outline note (optional)", text: $draft.note, axis: .vertical).lineLimit(2...4)
            if draft.kind == .level { TextField("Gameplay reference (optional)", text: $draft.reference) }
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(draft.ideaID == nil ? "Create Block" : "Promote Idea") { create(draft) }
                    .disabled(draft.kind == nil || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 445)
    }
}

@MainActor
func findOutlineWeb(in view: NSView?) -> WKWebView? {
    guard let view else { return nil }
    if let web = view as? WKWebView { return web }
    for child in view.subviews { if let web = findOutlineWeb(in: child) { return web } }
    return nil
}

@main
@MainActor
private final class OutlineCardsApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    static func main() {
        let app = NSApplication.shared
        let delegate = OutlineCardsApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let session = OutlineSession()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 730),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        self.window = window
        session.window = window
        window.backgroundColor = .windowBackgroundColor
        window.title = "The Tide Gate — Outline Cards Prototype"
        window.contentView = NSHostingView(rootView: OutlineRoot(session: session))
        window.minSize = NSSize(width: 910, height: 590)
        window.center()
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit Outline Cards Prototype", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (label, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(withTitle: label, action: action, keyEquivalent: key)
        }
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let path = CommandLine.arguments.dropFirst().first, path.hasPrefix("/") {
            Task { await runOutlineSmoke(session, window: window, output: URL(fileURLWithPath: path, isDirectory: true)) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
