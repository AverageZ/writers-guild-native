import Foundation
import Testing
@testable import GuildCore

struct AnchorTests {
    @Test func unicodeOffsetsRoundTripAndRelocateAcrossInsertedBlocks() {
        let original = Manuscript(sceneID: "s", text: "A lantern 🏮 lit the café.\nMara held the 🗝️ key.\nThe road waited.", revision: 1)
        let range = (original.text as NSString).range(of: "Mara held the 🗝️ key.")
        let anchor = AnchorResolver.make(manuscript: original, range: range)
        #expect(anchor.start == range.location)
        #expect(anchor.length == range.length)
        #expect(anchor.quote == "Mara held the 🗝️ key.")
        #expect(AnchorResolver.relocate(anchor, in: original) == anchor)
        let prefix = "👩🏽‍🚀 A new paragraph.\n"
        let edited = Manuscript(sceneID: "s", text: prefix + original.text, revision: 2)
        let relocated = AnchorResolver.relocate(anchor, in: edited)
        #expect(relocated?.start == range.location + prefix.utf16.count)
        #expect(relocated?.quote == anchor.quote)
        #expect(relocated?.revision == 2)
    }

    @Test func duplicateQuotesRequireDistinctContext() {
        let original = Manuscript(sceneID: "s", text: "At dawn, Rowan waited by the river.\nAt dusk, Rowan waited by the gate.", revision: 1)
        let second = (original.text as NSString).range(of: "Rowan waited", options: .backwards)
        let anchor = AnchorResolver.make(manuscript: original, range: second)
        let edited = Manuscript(sceneID: "s", text: "A note.\n" + original.text, revision: 2)
        let moved = AnchorResolver.relocate(anchor, in: edited)
        #expect(moved?.start == second.location + "A note.\n".utf16.count)
        #expect(moved?.suffix.hasPrefix(" by the gate.") == true)
    }

    @Test func indistinguishableDuplicateContextsAreRejected() {
        let prefix = String(repeating: "a", count: 45)
        let suffix = String(repeating: "b", count: 45)
        let passage = prefix + "Rowan waited" + suffix
        let original = Manuscript(sceneID: "s", text: passage, revision: 1)
        let anchor = AnchorResolver.make(manuscript: original, range: (original.text as NSString).range(of: "Rowan waited"))
        let duplicate = Manuscript(sceneID: "s", text: passage + "\n" + passage, revision: 2)
        #expect(AnchorResolver.relocate(anchor, in: duplicate) == nil)
    }

    @Test func deletionDoesNotLandOnUnrelatedIdenticalQuote() {
        let oldContext = String(repeating: "a", count: 45)
        let original = Manuscript(sceneID: "s", text: oldContext + "Rowan waited" + oldContext, revision: 1)
        let anchor = AnchorResolver.make(manuscript: original, range: (original.text as NSString).range(of: "Rowan waited"))
        #expect(AnchorResolver.relocate(anchor, in: Manuscript(sceneID: "s", text: "Nothing remains.", revision: 2)) == nil)
        #expect(AnchorResolver.relocate(anchor, in: Manuscript(sceneID: "s", text: "Elsewhere Rowan waited for a different reason.", revision: 2)) == nil)
        #expect(AnchorResolver.relocate(anchor, in: Manuscript(sceneID: "other", text: original.text, revision: 2)) == nil)
    }

    @Test func editedQuoteAndInvalidStoredRangeBecomeObsolete() {
        let original = Manuscript(sceneID: "s", text: "Mara held the key.", revision: 1)
        let anchor = AnchorResolver.make(manuscript: original, range: NSRange(location: 0, length: original.text.utf16.count))
        #expect(AnchorResolver.relocate(anchor, in: Manuscript(sceneID: "s", text: "Mara dropped the key.", revision: 2)) == nil)
        var invalid = anchor
        invalid.start = Int.max
        #expect(AnchorResolver.relocate(invalid, in: original) == nil)
        let empty = AnchorResolver.make(manuscript: original, range: NSRange(location: 0, length: 0))
        #expect(AnchorResolver.relocate(empty, in: original) == nil)
    }

    @Test func decomposedUnicodeRetainsExactSourceSpelling() {
        let original = Manuscript(sceneID: "s", text: "Here is Cafe\u{301}, beside the river.", revision: 1)
        let range = (original.text as NSString).range(of: "Cafe\u{301}", options: .literal)
        let anchor = AnchorResolver.make(manuscript: original, range: range)
        #expect(Array(anchor.quote.utf16) == Array("Cafe\u{301}".utf16))
        let edited = Manuscript(sceneID: "s", text: "Note. " + original.text, revision: 2)
        #expect(AnchorResolver.relocate(anchor, in: edited)?.start == range.location + 6)
    }
}
