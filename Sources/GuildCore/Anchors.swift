import Foundation

public enum AnchorResolver {
    /// Ranges use the editor's plain-text UTF-16 coordinate space, not structural tokens.
    public static func make(manuscript: Manuscript, range: NSRange) -> TextAnchor {
        let count = manuscript.text.utf16.count
        precondition(range.location >= 0 && range.location <= count && range.length >= 0 && range.length <= count - range.location,
                     "Anchor range must be inside the manuscript")
        precondition(Range(range, in: manuscript.text) != nil, "Anchor must have valid UTF-16 character boundaries")
        let selected = Range(range, in: manuscript.text)!
        let prefix = String(manuscript.text[..<selected.lowerBound].suffix(40))
        let suffix = String(manuscript.text[selected.upperBound...].prefix(40))
        return TextAnchor(sceneID: manuscript.sceneID, revision: manuscript.revision,
                          start: range.location, length: range.length,
                          quote: String(manuscript.text[selected]), prefix: prefix, suffix: suffix)
    }

    /// Exact quote plus surviving context only. A tied match is obsolete, never guessed.
    public static func relocate(_ anchor: TextAnchor, in manuscript: Manuscript) -> TextAnchor? {
        guard anchor.sceneID == manuscript.sceneID, !anchor.quote.isEmpty else { return nil }
        let text = manuscript.text as NSString
        if manuscript.revision == anchor.revision {
            guard anchor.start >= 0, anchor.start <= text.length, anchor.length >= 0,
                  anchor.length <= text.length - anchor.start else { return nil }
            let range = NSRange(location: anchor.start, length: anchor.length)
            guard Range(range, in: manuscript.text) != nil, text.substring(with: range) == anchor.quote else { return nil }
            return make(manuscript: manuscript, range: range)
        }
        var candidates: [(NSRange, Int)] = []
        var offset = 0
        while offset < text.length {
            let range = text.range(of: anchor.quote, options: .literal, range: NSRange(location: offset, length: text.length - offset))
            if range.location == NSNotFound { break }
            if let swiftRange = Range(range, in: manuscript.text) {
                let before = manuscript.text[..<swiftRange.lowerBound]
                let after = manuscript.text[swiftRange.upperBound...]
                let prefixMatches = anchor.prefix.isEmpty ? range.location == 0 : before.hasSuffix(anchor.prefix)
                let suffixMatches = anchor.suffix.isEmpty ? NSMaxRange(range) == text.length : after.hasPrefix(anchor.suffix)
                let score = (prefixMatches ? max(1, anchor.prefix.utf16.count) : 0)
                    + (suffixMatches ? max(1, anchor.suffix.utf16.count) : 0)
                if score > 0 { candidates.append((range, score)) }
            }
            offset = range.location + max(1, range.length)
        }
        guard let best = candidates.max(by: { $0.1 < $1.1 }),
              candidates.filter({ $0.1 == best.1 }).count == 1 else { return nil }
        return make(manuscript: manuscript, range: best.0)
    }
}
