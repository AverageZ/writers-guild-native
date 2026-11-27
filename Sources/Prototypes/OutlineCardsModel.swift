// Throwaway issue #9 fixture. No library, persistence, gameplay, AI, or event-authoring path.
import Foundation
import GuildCore

struct OutlineFixture {
    enum Kind: String, CaseIterable, Identifiable { case scene = "Scene", level = "Level"; var id: Self { self } }
    struct Block: Identifiable {
        var id: String
        var kind: Kind
        var title: String
        var time: Int
        var note = ""
        var reference = ""
        var prose: Manuscript? = nil
        var referenceState: String { reference.isEmpty ? "Unbound" : "Reference supplied—not verified" }
    }
    struct Chapter: Identifiable {
        var id: String
        var title: String
        var blocks: [String]

        func block(after id: String) -> String? {
            guard let index = blocks.firstIndex(of: id), index + 1 < blocks.count else { return nil }
            return blocks[index + 1]
        }
    }
    struct Idea: Identifiable { var id: String; var title: String; var note: String }
    struct Slot: Hashable { var chapter: String; var before: String? = nil }
    struct Ghost: Identifiable {
        let id = UUID().uuidString
        var text: String
        var lastAnchor: TextAnchor
        var state: State = .active
        enum State: String { case active = "Active", unplaced = "Needs placement" }
    }

    var chapters = [Chapter(id: "A", title: "The crossing", blocks: ["S1", "L1", "S2"]),
                    Chapter(id: "B", title: "What the tide took", blocks: ["S3"])]
    var blocks: [String: Block] = [
        "S1": .init(id: "S1", kind: .scene, title: "At the tide gate", time: 4,
                    note: "Mara weighs whether to risk the crossing.", prose: scene("S1", [
                        "Mara reached the tide gate just as the bell let go of its last note.",
                        "She took the brass key from her pocket and waited for the lamps to pass."
                    ])),
        "L1": .init(id: "L1", kind: .level, title: "Cross the lock", time: 5,
                    note: "Separate Mara from the town before the tide turns."),
        "S2": .init(id: "S2", kind: .scene, title: "A note under the door", time: 6,
                    prose: scene("S2", ["The lock house smelled of rain. A note lay face down beneath the door."])),
        "S3": .init(id: "S3", kind: .scene, title: "The first flood", time: 1,
                    prose: scene("S3", ["Nine years earlier, Mara watched the lower road disappear beneath the tide."])),
    ]
    var ideas = [Idea(id: "I1", title: "A second key", note: "What if Mara finds a second key in the lock house?")]
    var ghosts: [String: Ghost] = [:] // One open passage note per Scene in this experiment.
    var resolvedGhosts: [String: [Ghost]] = [:]
    private(set) var priorOrder: [Chapter]?

    init() {
        let prose = blocks["S1"]!.prose!
        let range = (prose.text as NSString).range(of: "the bell let go of its last note.")
        ghosts["S1"] = Ghost(text: "Let the silence do the work here.", lastAnchor: AnchorResolver.make(manuscript: prose, range: range))
    }

    var presentation: [String] { chapters.flatMap(\.blocks) }
    var chronology: [Block] { blocks.values.sorted { ($0.time, $0.id) < ($1.time, $1.id) } }
    var slots: [Slot] { chapters.flatMap { chapter in chapter.blocks.map { Slot(chapter: chapter.id, before: $0) } + [Slot(chapter: chapter.id)] } }

    func chapterLabel(_ id: String) -> String {
        guard let index = chapters.firstIndex(where: { $0.id == id }) else { return id }
        return "Chapter \(index + 1) · \(chapters[index].title)"
    }

    func slotLabel(_ slot: Slot) -> String {
        let label = chapterLabel(slot.chapter)
        return slot.before.flatMap { blocks[$0]?.title }.map { "\(label) · before \($0)" } ?? "\(label) · at end"
    }

    func placement(_ id: String) -> String {
        guard let chapter = chapters.first(where: { $0.blocks.contains(id) }),
              let index = chapter.blocks.firstIndex(of: id) else { return "Not in manuscript" }
        return "\(chapterLabel(chapter.id)) · block \(index + 1)"
    }

    mutating func move(_ id: String, to slot: Slot) -> Bool {
        guard let source = chapters.firstIndex(where: { $0.blocks.contains(id) }),
              let target = chapterIndex(for: slot), slot.before != id else { return false }
        let old = chapters
        chapters[source].blocks.removeAll { $0 == id }
        let index = slot.before.flatMap { chapters[target].blocks.firstIndex(of: $0) } ?? chapters[target].blocks.endIndex
        chapters[target].blocks.insert(id, at: index)
        guard chapters[target].blocks != old[target].blocks || source != target else { return false }
        priorOrder = old
        return true
    }

    mutating func undoMove() {
        if let priorOrder { chapters = priorOrder; self.priorOrder = nil }
    }

    mutating func create(kind: Kind, title: String, time: Int, note: String, reference: String, at slot: Slot, ideaID: String?) -> String? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let chapter = chapterIndex(for: slot),
              ideaID == nil || ideas.contains(where: { $0.id == ideaID }) else { return nil }
        let id = UUID().uuidString
        blocks[id] = Block(id: id, kind: kind, title: title, time: time, note: note,
                           reference: kind == .level ? reference : "", prose: kind == .scene ? Self.scene(id, []) : nil)
        let index = slot.before.flatMap { chapters[chapter].blocks.firstIndex(of: $0) } ?? chapters[chapter].blocks.endIndex
        chapters[chapter].blocks.insert(id, at: index)
        ideas.removeAll { $0.id == ideaID }
        priorOrder = nil
        return id
    }

    mutating func receive(_ draft: Manuscript) {
        guard let old = blocks[draft.sceneID]?.prose, old != draft else { return }
        blocks[draft.sceneID]?.prose = draft
        guard var ghost = ghosts[draft.sceneID], ghost.state == .active else { return }
        if let anchor = Self.track(ghost.lastAnchor, from: old, to: draft) { ghost.lastAnchor = anchor }
        else { ghost.state = .unplaced }
        ghosts[draft.sceneID] = ghost
    }

    private func chapterIndex(for slot: Slot) -> Int? {
        guard let index = chapters.firstIndex(where: { $0.id == slot.chapter }),
              slot.before.map(chapters[index].blocks.contains) ?? true else { return nil }
        return index
    }

    private static func scene(_ id: String, _ paragraphs: [String]) -> Manuscript {
        Manuscript(sceneID: id, html: paragraphs.map { "<p>\($0)</p>" }.joined(), text: paragraphs.joined(separator: "\n"))
    }

    // Probe ordinary typing around an intact quote. If a replacement touches the
    // passage or admits two placements, retain the note without guessing a location.
    private static func track(_ anchor: TextAnchor, from old: Manuscript, to draft: Manuscript) -> TextAnchor? {
        let before = Array(old.text.utf16), after = Array(draft.text.utf16)
        let end = anchor.start + anchor.length
        let prefix = zip(before, after).prefix { $0 == $1 }.count
        let suffix = zip(before.reversed(), after.reversed()).prefix { $0 == $1 }.count
        let unchanged = prefix >= end ? anchor.start : nil
        let shifted = suffix >= before.count - anchor.start ? anchor.start + after.count - before.count : nil
        if let unchanged, let shifted, unchanged != shifted { return nil }
        guard let start = unchanged ?? shifted else { return nil }
        let range = NSRange(location: start, length: anchor.length)
        guard let stringRange = Range(range, in: draft.text), draft.text[stringRange] == anchor.quote else { return nil }
        return AnchorResolver.make(manuscript: draft, range: range)
    }
}
