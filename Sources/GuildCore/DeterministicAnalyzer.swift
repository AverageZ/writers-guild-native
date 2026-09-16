import Foundation

/// Conservative English-language checks, not a parser or a source of story authority.
/// Properties: `rank` is a display string; `owner` and `location` contain entity IDs;
/// `northOf`/`southOf`/`eastOf`/`westOf` relate a location to another location ID.
/// `knowledge.<topic>` is available through WorldState, never inferred from future prose.
public struct DeterministicAnalyzer: Analyzer {
    public init() {}

    public static var defaultAgents: [AgentDefinition] {
        [
            AgentDefinition(id: "guild.continuity", name: "The Cartographer", role: "Geography and possession continuity", categories: ["CONTINUITY"], traits: ["Evidence-led", "Chronology-aware"]),
            AgentDefinition(id: "guild.character", name: "The Chronicler", role: "Character state and transitions", categories: ["CHARACTER"], traits: ["Precise", "Patient"]),
            AgentDefinition(id: "guild.names", name: "The Registrar", role: "Names and terminology", categories: ["NAME"], traits: ["Attentive", "Conservative"]),
            AgentDefinition(id: "guild.tense", name: "The Timekeeper", role: "Sustained narrative tense", categories: ["TENSE"], traits: ["Pattern-minded", "Dialogue-aware"]),
            AgentDefinition(id: "guild.style", name: "The Stylist", role: "Hedges and repetition", categories: ["STYLE"], traits: ["Gentle", "Pattern-minded"])
        ]
    }

    public func analyze(_ context: ReviewContext) async throws -> ReviewResult {
        guard context.manuscript.sceneID == context.scene.id,
              let story = context.library.stories.first(where: { $0.id == context.scene.storyID }) else { return ReviewResult() }
        let text = context.manuscript.text as NSString
        let state = WorldState(library: context.library, scene: context.scene)
        let entities = context.library.entities.filter { $0.worldID == story.worldID }.sorted { $0.id < $1.id }
        let profiles = context.library.agents.sorted { $0.id < $1.id }
        var result = ReviewResult()
        var emitted = Set<String>()
        let localEvents: [(event: StoryEvent, anchor: TextAnchor)] = context.library.events.compactMap { event in
            guard event.storyID == story.id, event.sceneID == context.scene.id, event.time == context.scene.time,
                  event.evidence.sourceID == context.scene.id, let source = event.evidence.anchor,
                  let relocated = AnchorResolver.relocate(source, in: context.manuscript) else { return nil }
            return (event, relocated)
        }
        var stateByCutoff: [Int: WorldState] = [Int.max: state]
        func stateAt(_ offset: Int) -> WorldState {
            // An anchored same-scene transition is not prior evidence for prose before it.
            let cutoff = localEvents.filter { $0.anchor.start >= offset }.map { $0.event.sequence }.min() ?? Int.max
            if let cached = stateByCutoff[cutoff] { return cached }
            let snapshot = WorldState(library: context.library, scene: context.scene, beforeSequence: cutoff)
            stateByCutoff[cutoff] = snapshot
            return snapshot
        }
        func isEstablished(_ entityID: ID, _ property: String, _ value: String, _ range: NSRange) -> Bool {
            localEvents.contains {
                $0.event.entityID == entityID && $0.event.property == property
                    && $0.event.value.caseInsensitiveCompare(value) == .orderedSame
                    && $0.anchor.start == range.location
                    && $0.anchor.quote.trimmingCharacters(in: CharacterSet(charactersIn: ".!?").union(.whitespacesAndNewlines))
                        == text.substring(with: range)
            }
        }

        var expressions: [String: NSRegularExpression] = [:]
        func matches(_ pattern: String, text: NSString, range: NSRange) -> [NSTextCheckingResult] {
            let expression: NSRegularExpression
            if let cached = expressions[pattern] {
                expression = cached
            } else {
                // Fixed patterns with escaped entity labels: invalid syntax is a programmer error.
                do { expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) }
                catch { preconditionFailure("Invalid deterministic analyzer pattern: \(error)") }
                expressions[pattern] = expression
            }
            return expression.matches(in: text as String, range: range)
        }
        func profile(_ category: String) -> AgentDefinition? {
            profiles.first { $0.enabled && $0.categories.contains { $0.caseInsensitiveCompare(category) == .orderedSame } }
        }
        func anchor(_ range: NSRange) -> TextAnchor { AnchorResolver.make(manuscript: context.manuscript, range: range) }
        func currentEvidence(_ range: NSRange) -> EvidenceReference {
            let a = anchor(range)
            return EvidenceReference(id: "text:\(context.scene.id):\(context.manuscript.revision):\(range.location):\(range.length)", kind: "manuscript", sourceID: context.scene.id,
                                     label: "\(context.scene.chapter) · \(context.scene.title)", quote: a.quote, anchor: a)
        }
        func emit(_ category: String, _ rule: String, _ range: NSRange, _ confidence: Double,
                  _ message: String, _ question: String, _ evidence: [EvidenceReference] = []) {
            guard let agent = profile(category), confidence >= agent.confidenceThreshold else { return }
            let id = "\(context.scene.id):\(context.manuscript.revision):\(rule):\(range.location)"
            guard emitted.insert(id).inserted else { return }
            result.observations.append(AgentObservation(id: id, agentID: agent.id, category: category,
                confidence: confidence, anchor: anchor(range), message: message, question: question,
                evidence: evidence + [currentEvidence(range)]))
        }
        func claim(_ entity: Entity, _ property: String, _ value: String, _ transition: Bool, _ range: NSRange, _ conflicts: Bool = false) {
            let id = "claim:\(context.scene.id):\(context.manuscript.revision):\(entity.id):\(property):\(range.location)"
            guard !result.claims.contains(where: { $0.id == id }) else { return }
            result.claims.append(NarrativeClaim(id: id, storyID: story.id, sceneID: context.scene.id, entityID: entity.id,
                property: property, value: value, isTransition: transition, anchor: anchor(range), status: conflicts ? .conflict : .pending))
        }
        func aliases(_ entity: Entity) -> String {
            ([entity.name] + entity.aliases).filter { !$0.isEmpty }.sorted { $0.count > $1.count }
                .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        }
        func named(_ entity: Entity, in range: NSRange) -> Bool {
            !matches("(?<![\\p{L}\\p{N}])(?:\(aliases(entity)))(?![\\p{L}\\p{N}])", text: text, range: range).isEmpty
        }
        let whole = NSRange(location: 0, length: text.length)
        let sentences = matches("[^.!?\\n]+[.!?]?", text: text, range: whole).map(\.range).map { Self.trim($0, text: text) }.filter { $0.length > 0 }
        let paragraphs = matches("[^\\n]+", text: text, range: whole).map(\.range)
        let rankWords = Set(["private", "corporal", "sergeant", "lieutenant", "captain", "major", "colonel", "general", "commander", "admiral"] + entities.compactMap { state.value(entityID: $0.id, property: "rank")?.value.lowercased() })
        let ranks = rankWords.sorted().map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")

        for entity in entities where entity.kind == "character" {
            let names = aliases(entity)
            for match in matches("\\b(\(ranks))\\s+(?:\(names))(?![\\p{L}\\p{N}])", text: text, range: whole) {
                let rank = text.substring(with: match.range(at: 1))
                let current = stateAt(match.range.location).value(entityID: entity.id, property: "rank")
                let conflict = current.map { $0.value.caseInsensitiveCompare(rank) != .orderedSame } ?? false
                claim(entity, "rank", rank, false, match.range, conflict)
                if conflict, let current {
                    emit("CHARACTER", "rank-\(entity.id)", match.range, 0.98,
                         "\(entity.name) is called \(rank), but the established rank here is \(current.value).",
                         "Is this an intentional reference to an earlier rank?", current.evidence)
                }
            }
            for match in matches("(?<![\\p{L}\\p{N}])(?:\(names))\\s+(?:(?:was|is|had been|has been)\\s+)?promoted\\s+to\\s+(\(ranks))\\b", text: text, range: whole) {
                let rank = text.substring(with: match.range(at: 1))
                guard !isEstablished(entity.id, "rank", rank, match.range) else { continue }
                let current = stateAt(match.range.location).value(entityID: entity.id, property: "rank")
                claim(entity, "rank", rank, true, match.range)
                if let current, current.value.caseInsensitiveCompare(rank) == .orderedSame {
                    emit("CHARACTER", "promotion-\(entity.id)", match.range, 0.97,
                         "\(entity.name) is already \(current.value) at this point; this appears to repeat the promotion.",
                         "Is this a recollection, or a second depiction of the same event?", current.evidence)
                }
            }
        }

        let directions = [("south", "southOf", "north"), ("north", "northOf", "south"), ("east", "eastOf", "west"), ("west", "westOf", "east")]
        for sentence in sentences {
            let state = stateAt(sentence.location)
            let groups = entities.filter { ["party", "group"].contains($0.kind) && state.value(entityID: $0.id, property: "location") != nil }
            let pronounGroup = groups.count == 1 && !matches("\\bthey\\b", text: text, range: sentence).isEmpty ? groups.first?.id : nil
            let located = entities.filter { state.value(entityID: $0.id, property: "location") != nil && (named($0, in: sentence) || $0.id == pronounGroup) }
            for traveler in located {
                guard let location = state.value(entityID: traveler.id, property: "location") else { continue }
                for target in entities where target.kind == "location" {
                    for (direction, relation, expected) in directions {
                        guard let geography = state.value(entityID: location.value, property: relation), geography.value == target.id else { continue }
                        for match in matches("\\b(?:headed|head|went|walked|traveled|travelled|marched|rode|go)\\s+\(direction)\\s+(?:towards?|to)\\s+(?:the\\s+)?(?:\(aliases(target)))(?![\\p{L}\\p{N}])", text: text, range: sentence) {
                            claim(traveler, "heading", direction, true, match.range, true)
                            emit("CONTINUITY", "direction-\(traveler.id)-\(target.id)", match.range, 0.96,
                                 "From the established location, \(target.name) lies \(expected), not \(direction).",
                                 "Has the party moved, or should this direction change?", location.evidence + geography.evidence)
                        }
                    }
                }
            }
            for item in entities where item.kind == "object" && named(item, in: sentence) {
                guard let ownership = state.value(entityID: item.id, property: "owner") else { continue }
                // Require a named actor immediately governing a use/carry action; a recipient elsewhere in a sentence is not its actor.
                for actor in entities where actor.kind == "character" {
                    let pattern = "(?<![\\p{L}\\p{N}])(?:\(aliases(actor)))\\s+(?:unlocked|opened|carried|carries|held|holds|used|uses|gripped|grips)\\b[^.!?\\n]*?(?:\(aliases(item)))(?![\\p{L}\\p{N}])"
                    for match in matches(pattern, text: text, range: sentence) {
                        let conflict = ownership.value != actor.id
                        claim(item, "owner", actor.id, false, match.range, conflict)
                        if conflict {
                            let owner = entities.first(where: { $0.id == ownership.value })?.name ?? ownership.value
                            emit("CONTINUITY", "owner-\(item.id)", match.range, 0.9,
                                 "\(actor.name) uses \(item.name), but the last established owner is \(owner).",
                                 "Was the object returned or borrowed in an intervening event?", ownership.evidence)
                        }
                    }
                }
            }
        }

        // Compare whole name-sized windows. Exact canonical names and aliases always win over fuzzy suggestions.
        let tokens = matches("\\b\\p{L}+(?:['’’-]\\p{L}+)*\\b", text: text, range: whole)
        let knownNames = Set(entities.flatMap { [$0.name] + $0.aliases }.map { $0.lowercased() })
        for entity in entities where entity.kind == "character" {
            let canonicalWords = entity.name.split(separator: " ")
            guard !canonicalWords.isEmpty, entity.name.count >= 4, tokens.count >= canonicalWords.count else { continue }
            for index in 0...(tokens.count - canonicalWords.count) {
                let start = tokens[index].range.location
                let end = NSMaxRange(tokens[index + canonicalWords.count - 1].range)
                let range = NSRange(location: start, length: end - start)
                let candidate = text.substring(with: range)
                guard candidate.first?.isUppercase == true, !candidate.contains("\n"), !knownNames.contains(candidate.lowercased()),
                      Self.editDistance(candidate.lowercased(), entity.name.lowercased()) == 1 else { continue }
                let reference = EvidenceReference(id: "entity:\(entity.id)", kind: "entity", sourceID: entity.id, label: "Canonical name", quote: entity.name)
                emit("NAME", "name-\(entity.id)", range, 0.88,
                     "“\(candidate)” is one edit from the canonical name “\(entity.name)”.",
                     "Is this the same character or a distinct name?", [reference])
            }
        }

        if let agent = profile("TENSE") {
            let expectedPast = context.scene.expectedTense.lowercased() == "past"
            let expectedPresent = context.scene.expectedTense.lowercased() == "present"
            let present = "\\b(?:is|are|walks|steps|turns|looks|opens|reaches|takes|runs|stands|watches|hears|sees|moves|holds|waits|nods|says|feels|knows|follows|rises)\\b"
            let past = "\\b(?:was|were|walked|stepped|turned|looked|opened|reached|took|ran|stood|watched|heard|saw|moved|held|waited|nodded|said|felt|knew|followed)\\b"
            var run: [NSRange] = []
            func flush() {
                guard run.count >= max(2, agent.patternThreshold), let first = run.first, let last = run.last else { run.removeAll(); return }
                let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
                let reference = EvidenceReference(id: "tense:\(context.scene.id)", kind: "scene", sourceID: context.scene.id, label: "Scene narrative tense", quote: context.scene.expectedTense)
                emit("TENSE", "tense", range, 0.84,
                     "A sustained passage uses \(expectedPast ? "present" : "past")-tense signals in a \(context.scene.expectedTense)-tense scene.",
                     "Is this a deliberate change of narrative time?", [reference])
                run.removeAll()
            }
            for sentence in sentences {
                let passage = text.substring(with: sentence)
                let dialogue = passage.contains("\"") || passage.contains("“") || passage.contains("”")
                let mismatch = (expectedPast || expectedPresent) && !dialogue
                    && !matches(expectedPast ? present : past, text: text, range: sentence).isEmpty
                    && matches(expectedPast ? past : present, text: text, range: sentence).isEmpty
                if mismatch { run.append(sentence) } else { flush() }
            }
            flush()
        }

        if let agent = profile("STYLE") {
            let threshold = max(2, agent.patternThreshold)
            for paragraph in paragraphs {
                let hedges = matches("\\b(?:perhaps|seemed|almost|somewhat|maybe)\\b", text: text, range: paragraph)
                if hedges.count >= threshold, let first = hedges.first, let last = hedges.last {
                    let range = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
                    emit("STYLE", "hedges", range, 0.86,
                         "\(hedges.count) hedges cluster in this paragraph, softening several nearby statements.",
                         "Does this uncertainty serve the viewpoint, or dilute the moment?")
                }
                let words = matches("\\b\\p{L}{4,}\\b", text: text, range: paragraph)
                let excluded: Set<String> = ["that", "this", "with", "from", "have", "were", "they", "their", "there", "then", "into", "some", "would", "could", "should", "perhaps", "seemed", "almost", "somewhat", "maybe"]
                let groups = Dictionary(grouping: words, by: { text.substring(with: $0.range).lowercased() })
                for word in groups.keys.sorted() {
                    guard !excluded.contains(word), !knownNames.contains(word), let repeats = groups[word], repeats.count >= max(3, threshold), let first = repeats.first, let last = repeats.last else { continue }
                    let range = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
                    emit("STYLE", "word-\(word)", range, 0.78,
                         "“\(word)” repeats \(repeats.count) times in one paragraph.", "Is the repeated emphasis intentional?")
                }
            }
            var openings: [String: [NSRange]] = [:]
            for sentence in sentences {
                let firstWords = matches("\\b\\p{L}+\\b", text: text, range: sentence).prefix(2)
                guard firstWords.count == 2 else { continue }
                let key = firstWords.map { text.substring(with: $0.range).lowercased() }.joined(separator: " ")
                openings[key, default: []].append(sentence)
            }
            for key in openings.keys.sorted() {
                guard let repeats = openings[key], repeats.count >= max(3, threshold), let first = repeats.first, let last = repeats.last else { continue }
                let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
                emit("STYLE", "opening-\(key)", range, 0.8,
                     "\(repeats.count) sentences begin “\(key)”.", "Is this parallel rhythm deliberate?")
            }
        }
        result.observations.sort { $0.anchor.start == $1.anchor.start ? $0.id < $1.id : $0.anchor.start < $1.anchor.start }
        result.claims.sort { $0.anchor.start == $1.anchor.start ? $0.id < $1.id : $0.anchor.start < $1.anchor.start }
        return result
    }


    private static func trim(_ range: NSRange, text: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, let scalar = UnicodeScalar(text.character(at: start)), CharacterSet.whitespacesAndNewlines.contains(scalar) { start += 1 }
        while end > start, let scalar = UnicodeScalar(text.character(at: end - 1)), CharacterSet.whitespacesAndNewlines.contains(scalar) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Only distances zero, one, and greater-than-one matter; scan without a quadratic matrix.
    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let leftCount = lhs.count, rightCount = rhs.count
        guard abs(leftCount - rightCount) <= 1 else { return 2 }
        var left = lhs.startIndex, right = rhs.startIndex, edits = 0
        while left < lhs.endIndex && right < rhs.endIndex {
            if lhs[left] == rhs[right] {
                lhs.formIndex(after: &left)
                rhs.formIndex(after: &right)
            } else {
                edits += 1
                if edits > 1 { return 2 }
                if leftCount >= rightCount { lhs.formIndex(after: &left) }
                if rightCount >= leftCount { rhs.formIndex(after: &right) }
            }
        }
        return edits + ((left < lhs.endIndex || right < rhs.endIndex) ? 1 : 0)
    }
}
