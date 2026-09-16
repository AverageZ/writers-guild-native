import Foundation
import GuildCore

let modelReviewCategories: Set<String> = ["CONTINUITY", "CHARACTER", "NAME"]

public enum AppleModelError: Error, LocalizedError, Sendable, Equatable {
    case unavailable(String)
    case invalidContext(String)
    case invalidOutput(String)
    case groundingLimit

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .invalidContext(let reason): return "Review context is invalid: \(reason)"
        case .invalidOutput(let reason): return "The model review was not grounded: \(reason)"
        case .groundingLimit: return "The model exceeded this passage's bounded evidence allowance. Review a smaller passage."
        }
    }
}

// These transport values deliberately have no manuscript replacement or accepted-state fields.
struct ProposedAnchor: Sendable {
    var start: Int
    var length: Int
    var quote: String
}

struct ProposedClaim: Sendable {
    var entityID: ID
    var property: String
    var value: String
    var isTransition: Bool
    var confidence: Double
    var anchor: ProposedAnchor
    var evidenceIDs: [ID]
}

struct ProposedObservation: Sendable {
    var agentID: ID
    var category: String
    var entityIDs: [ID]
    var confidence: Double
    var anchor: ProposedAnchor
    var message: String
    var question: String
    var evidenceIDs: [ID]
}

struct ReviewPacket: Encodable, Sendable {
    struct Subject: Encodable, Sendable {
        var id: ID
        var name: String
        var aliases: [String]
    }
    struct Passage: Encodable, Sendable { var id: String; var text: String }
    struct Fact: Encodable, Sendable {
        var id: String
        var entityID: ID
        var property: String
        var value: String
        var source: String
        var passage: String
    }
    struct Memory: Encodable, Sendable { var agentID: ID; var belief: String }
    var entities: [Subject] = []
    var current: [Passage] = []
    var state: [Fact] = []
    var propertyNames: [String] = []
    var memory: [Memory] = []
}

// Generated references are selections, not database IDs, citations, or text offsets.
struct ReviewSelection: Decodable, Sendable {
    struct Claim: Decodable, Sendable {
        var entityID: ID
        var passage: String
        var property: String
        var value: String
        var isTransition: Bool
        var confidence: Double
    }
    struct Observation: Decodable, Sendable {
        var fact: String
        var passage: String
        var agentID: ID
        var message: String
        var question: String
        var confidence: Double
    }
    var claims: [Claim]?
    var observations: [Observation]?
}

private struct FactSource: Sendable {
    var entityID: ID
    var evidenceIDs: [ID]
    var passageID: String
}

private struct Receipt: Sendable {
    var evidence: EvidenceReference
    var entityIDs: Set<ID>
    var authoritative: Bool
}

/// One actor per passage/session. Swift retrieves obligatory context before generation.
/// Only presented, world/story/time-scoped records can back a generated selection.
actor ReviewGrounding {
    let context: ReviewContext
    let range: NSRange
    let worldID: ID
    let state: WorldState
    private var returnedEntities: Set<ID> = []
    private var receipts: [ID: Receipt] = [:]
    private var passages: [String: (anchor: ProposedAnchor, evidenceID: ID)] = [:]
    private var factSources: [String: FactSource] = [:]

    init(context: ReviewContext, range: NSRange) throws {
        guard context.manuscript.sceneID == context.scene.id,
              let story = context.library.stories.first(where: { $0.id == context.scene.storyID }),
              context.library.worlds.contains(where: { $0.id == story.worldID }),
              context.library.scenes.contains(context.scene),
              Range(range, in: context.manuscript.text) != nil else {
            throw AppleModelError.invalidContext("Missing scope or invalid manuscript range.")
        }
        guard !story.worldOffset.addingReportingOverflow(context.scene.time).overflow else {
            throw AppleModelError.invalidContext("Chronology overflow.")
        }
        self.context = context
        self.range = range
        worldID = story.worldID
        state = WorldState(library: context.library, scene: context.scene)
    }

    func prepare() throws -> ReviewPacket {
        try Task.checkCancellation()
        let text = (context.manuscript.text as NSString).substring(with: range)
        let scopedEntities = context.library.entities.filter { $0.worldID == worldID }
        let mentions = try NSRegularExpression(pattern: "\\b(?:they|we|party|group)\\b", options: .caseInsensitive)
        let groups = scopedEntities.filter { $0.kind == "party" }
        var selected = try scopedEntities.filter { entity in
            try ([entity.name] + entity.aliases).contains { name in
                guard !name.isEmpty else { return false }
                let expression = try NSRegularExpression(
                    pattern: "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}_])",
                    options: .caseInsensitive)
                return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
        }
        if groups.count == 1, !selected.contains(where: { $0.id == groups[0].id }),
           mentions.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            selected.append(groups[0])
        }
        // Follow established entity-valued relationships, never manuscript proposals.
        // Two bounded hops cover an actor's location and that location's geography.
        for _ in 0..<2 {
            let known = Set(selected.map(\.id))
            let related = selected.flatMap { entity in
                properties(for: entity.id).compactMap { property -> String? in
                    guard let value = state.value(entityID: entity.id, property: property),
                          !value.evidence.isEmpty, value.evidence.allSatisfy(evidenceIsScoped) else { return nil }
                    return value.value
                }
            }
            selected += scopedEntities.filter { !known.contains($0.id) && related.contains($0.id) }
        }
        selected = Array(selected.prefix(8))
        var packet = ReviewPacket()
        packet.entities = selected.map {
            .init(id: $0.id, name: String($0.name.prefix(100)), aliases: $0.aliases.prefix(3).map { String($0.prefix(100)) })
        }
        returnedEntities.formUnion(selected.map(\.id))
        let lines = try NSRegularExpression(pattern: "[^\\r\\n]+")
        for match in lines.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let quote = (text as NSString).substring(with: match.range)
            guard !quote.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let id = "P\(packet.current.count + 1)"
            let anchor = ProposedAnchor(start: range.location + match.range.location, length: match.range.length, quote: quote)
            let reference = EvidenceReference(kind: "manuscript", sourceID: context.scene.id,
                label: "Current passage", quote: quote, anchor: try validateAnchor(anchor))
            passages[id] = (anchor, reference.id)
            try register(reference, entityID: nil, authoritative: false)
            packet.current.append(.init(id: id, text: quote))
        }
        let reviewedProperties = Dictionary(uniqueKeysWithValues: selected.map { entity in
            (entity.id, Array(properties(for: entity.id).prefix(3)))
        })
        packet.propertyNames = Set(reviewedProperties.values.flatMap { $0 }).sorted()
        let localEvents = context.library.events.compactMap { event -> (sequence: Int, start: Int)? in
            guard event.storyID == context.scene.storyID, event.sceneID == context.scene.id,
                  event.time == context.scene.time, event.evidence.sourceID == context.scene.id,
                  let source = event.evidence.anchor,
                  let relocated = AnchorResolver.relocate(source, in: context.manuscript) else { return nil }
            return (event.sequence, relocated.start)
        }
        for passage in packet.current {
            guard let current = passages[passage.id] else { continue }
            let cutoff = localEvents.filter { $0.start >= current.anchor.start }.map(\.sequence).min() ?? Int.max
            let passageState = WorldState(library: context.library, scene: context.scene, beforeSequence: cutoff)
            for entity in selected {
                for property in reviewedProperties[entity.id] ?? [] {
                    guard let value = passageState.value(entityID: entity.id, property: property),
                          property.count <= 100, value.value.count <= 300,
                          !value.evidence.isEmpty, value.evidence.allSatisfy(evidenceIsScoped) else { continue }
                    let id = "S\(packet.state.count + 1)"
                    // Keep complete provenance in Swift; the small model only needs the
                    // effective value and a short source excerpt, not nested anchor JSON.
                    for reference in value.evidence { try register(reference, entityID: entity.id, authoritative: true) }
                    factSources[id] = FactSource(entityID: entity.id, evidenceIDs: value.evidence.map(\.id),
                                                 passageID: passage.id)
                    packet.state.append(.init(id: id, entityID: entity.id, property: property,
                        value: value.value, source: String(value.evidence.last!.quote.prefix(160)), passage: passage.id))
                }
            }
        }
        packet.memory = context.library.memories.filter { memory in
            memory.worldID == worldID && memoryIsScoped(memory)
                && context.library.agents.contains { $0.id == memory.agentID && $0.enabled }
        }.sorted { $0.strength > $1.strength }.prefix(2).map {
            .init(agentID: $0.agentID, belief: String($0.belief.prefix(160)))
        }
        return packet
    }

    func materialize(_ selection: ReviewSelection) throws -> ReviewResult {
        let claims = try (selection.claims ?? []).map { claim in
            guard let passage = passages[claim.passage] else {
                throw AppleModelError.invalidOutput("Unknown passage selection.")
            }
            return ProposedClaim(entityID: claim.entityID, property: claim.property, value: claim.value,
                isTransition: claim.isTransition, confidence: claim.confidence,
                anchor: passage.anchor, evidenceIDs: [passage.evidenceID])
        }
        let observations = try (selection.observations ?? []).map { observation in
            guard let passage = passages[observation.passage], let source = factSources[observation.fact],
                  source.passageID == observation.passage,
                  let agent = context.library.agents.first(where: { $0.id == observation.agentID && $0.enabled }),
                  let category = agent.categories.first(where: { modelReviewCategories.contains($0) }) else {
                throw AppleModelError.invalidOutput("Unknown passage, state, or agent selection.")
            }
            return ProposedObservation(agentID: agent.id, category: category, entityIDs: [source.entityID],
                confidence: observation.confidence, anchor: passage.anchor, message: observation.message,
                question: observation.question, evidenceIDs: [passage.evidenceID] + source.evidenceIDs)
        }
        return try validate(claims: claims, observations: observations)
    }

    private func canonicalFacts(for entityID: ID) -> [CanonicalFact] {
        let story = context.library.stories.first { $0.id == context.scene.storyID }!
        let worldTime = story.worldOffset + context.scene.time // Overflow checked by init.
        return context.library.facts.filter {
            $0.worldID == worldID && $0.entityID == entityID && ($0.validFrom == nil || $0.validFrom! <= worldTime)
                && $0.property.count <= 100 && $0.value.count <= 300
        }
    }

    private func properties(for entityID: ID) -> [String] {
        let events = context.library.events.filter {
            $0.storyID == context.scene.storyID && $0.entityID == entityID && $0.time <= context.scene.time
        }
        return Set(canonicalFacts(for: entityID).map(\.property) + events.map(\.property)).sorted()
    }

    private func register(_ reference: EvidenceReference, entityID: ID?, authoritative: Bool) throws {
        if let existing = receipts[reference.id], existing.evidence != reference {
            throw AppleModelError.invalidContext("A citation ID identifies different sources.")
        }
        var receipt = receipts[reference.id] ?? Receipt(evidence: reference, entityIDs: [], authoritative: false)
        if let entityID { receipt.entityIDs.insert(entityID) }
        receipt.authoritative = receipt.authoritative || authoritative
        receipts[reference.id] = receipt
    }

    func validate(claims: [ProposedClaim], observations: [ProposedObservation]) throws -> ReviewResult {
        try Task.checkCancellation()
        guard claims.count <= 6, observations.count <= 4 else {
            throw AppleModelError.invalidOutput("Too many results for one passage.")
        }
        var result = ReviewResult()
        for claim in claims {
            try validateConfidence(claim.confidence)
            try validateEntities([claim.entityID])
            guard !claim.property.isEmpty, claim.property.count <= 100, !claim.value.isEmpty, claim.value.count <= 300 else {
                throw AppleModelError.invalidOutput("Invalid claim property or value.")
            }
            let anchor = try validateAnchor(claim.anchor)
            _ = try citedEvidence(claim.evidenceIDs, anchor: anchor, entities: [claim.entityID], requiresAuthority: false)
            let established = state.value(entityID: claim.entityID, property: claim.property)
            let conflict = !claim.isTransition && established.map { $0.value != claim.value } == true
            result.claims.append(NarrativeClaim(storyID: context.scene.storyID, sceneID: context.scene.id,
                                               entityID: claim.entityID, property: claim.property, value: claim.value,
                                               isTransition: claim.isTransition, anchor: anchor, status: conflict ? .conflict : .pending))
        }
        for observation in observations {
            try validateConfidence(observation.confidence)
            try validateEntities(observation.entityIDs)
            guard let agent = context.library.agents.first(where: { $0.id == observation.agentID && $0.enabled }),
                  agent.categories.contains(observation.category), modelReviewCategories.contains(observation.category),
                  !observation.message.isEmpty,
                  observation.message.count <= 600, observation.question.count <= 300 else {
                throw AppleModelError.invalidOutput("Invalid agent, category, or critique.")
            }
            let anchor = try validateAnchor(observation.anchor)
            let evidence = try citedEvidence(observation.evidenceIDs, anchor: anchor,
                                            entities: observation.entityIDs, requiresAuthority: true)
            guard observation.confidence >= agent.confidenceThreshold else { continue }
            result.observations.append(AgentObservation(agentID: agent.id, category: observation.category,
                                                       confidence: observation.confidence, anchor: anchor, message: observation.message,
                                                       question: observation.question.isEmpty ? nil : observation.question, evidence: evidence))
        }
        return result
    }

    private func validateConfidence(_ confidence: Double) throws {
        guard confidence.isFinite, (0...1).contains(confidence) else { throw AppleModelError.invalidOutput("Invalid confidence.") }
    }

    private func validateEntities(_ ids: [ID]) throws {
        guard !ids.isEmpty, ids.count <= 4, Set(ids).count == ids.count,
              ids.allSatisfy({ returnedEntities.contains($0) }) else {
            throw AppleModelError.invalidOutput("An entity was not included in this scoped review.")
        }
    }

    private func validateAnchor(_ proposed: ProposedAnchor) throws -> TextAnchor {
        guard proposed.start >= range.location, proposed.length > 0,
              proposed.start <= NSMaxRange(range), proposed.length <= NSMaxRange(range) - proposed.start else {
            throw AppleModelError.invalidOutput("Anchor is outside the reviewed passage.")
        }
        let span = NSRange(location: proposed.start, length: proposed.length)
        guard let indices = Range(span, in: context.manuscript.text),
              String(context.manuscript.text[indices]) == proposed.quote else {
            throw AppleModelError.invalidOutput("Anchor quote does not match its UTF-16 range.")
        }
        let prefix = String(context.manuscript.text[..<indices.lowerBound].suffix(24))
        let suffix = String(context.manuscript.text[indices.upperBound...].prefix(24))
        return TextAnchor(sceneID: context.scene.id, revision: context.manuscript.revision,
                          start: proposed.start, length: proposed.length, quote: proposed.quote, prefix: prefix, suffix: suffix)
    }

    private func citedEvidence(_ ids: [ID], anchor: TextAnchor, entities: [ID], requiresAuthority: Bool) throws -> [EvidenceReference] {
        guard !ids.isEmpty, ids.count <= 8, Set(ids).count == ids.count else {
            throw AppleModelError.invalidOutput("Missing or duplicate citations.")
        }
        let cited = try ids.map { id in
            guard let receipt = receipts[id] else { throw AppleModelError.invalidOutput("Citation was not included in this scoped review.") }
            return receipt
        }
        guard cited.contains(where: { receipt in
            guard !receipt.authoritative, let source = receipt.evidence.anchor else { return false }
            return source.sceneID == anchor.sceneID && source.revision == anchor.revision
                && source.start <= anchor.start && source.length >= anchor.length
                && anchor.start - source.start <= source.length - anchor.length
        }) else { throw AppleModelError.invalidOutput("No returned current-text citation covers the anchor.") }
        if requiresAuthority {
            guard entities.allSatisfy({ entity in cited.contains { $0.authoritative && $0.entityIDs.contains(entity) } }) else {
                throw AppleModelError.invalidOutput("Continuity requires returned canon or state evidence for each entity; memory is not authority.")
            }
        }
        return cited.map(\.evidence)
    }

    private func memoryIsScoped(_ memory: AgentMemory) -> Bool {
        // Memory has world scope in storage. Review-time recall additionally restricts its
        // feedback provenance so a future/sibling scene cannot leak through a fallible belief.
        !memory.sourceFeedbackIDs.isEmpty && memory.sourceFeedbackIDs.allSatisfy { id in
            guard let feedback = context.library.feedback.first(where: { $0.id == id }),
                  feedback.worldID == worldID, feedback.agentID == memory.agentID,
                  let observation = context.library.observations.first(where: { $0.id == feedback.observationID }),
                  observation.agentID == memory.agentID,
                  let scene = context.library.scenes.first(where: { $0.id == observation.anchor.sceneID }) else { return false }
            return scene.storyID == context.scene.storyID && scene.time <= context.scene.time
        }
    }

    private func evidenceIsScoped(_ evidence: EvidenceReference) -> Bool {
        if let sourceScene = context.library.scenes.first(where: { $0.id == evidence.sourceID }),
           sourceScene.storyID != context.scene.storyID || sourceScene.time > context.scene.time { return false }
        if let lore = context.library.lore.first(where: { $0.id == evidence.sourceID }), lore.worldID != worldID { return false }
        if let sourceEvent = context.library.events.first(where: { $0.id == evidence.sourceID }),
           sourceEvent.storyID != context.scene.storyID || sourceEvent.time > context.scene.time { return false }
        guard let anchor = evidence.anchor else { return true }
        guard let scene = context.library.scenes.first(where: { $0.id == anchor.sceneID }),
              scene.storyID == context.scene.storyID, scene.time <= context.scene.time else { return false }
        let manuscript = scene.id == context.scene.id ? context.manuscript : context.library.manuscripts.first { $0.sceneID == scene.id }
        guard let manuscript, manuscript.revision == anchor.revision, anchor.start >= 0, anchor.length > 0,
              anchor.start <= manuscript.text.utf16.count, anchor.length <= manuscript.text.utf16.count - anchor.start,
              let span = Range(NSRange(location: anchor.start, length: anchor.length), in: manuscript.text) else { return false }
        return String(manuscript.text[span]) == anchor.quote
    }
}
