import Foundation

/// Temporary evidence for one review. Deliberately not Codable or part of Library.
public struct WorkingMemory: Sendable {
    public let capacity: Int
    public private(set) var evidence: [EvidenceReference] = []

    public init(capacity: Int = 8) {
        self.capacity = min(32, max(0, capacity))
    }

    public mutating func remember(_ reference: EvidenceReference) {
        guard capacity > 0 else { return }
        evidence.removeAll { $0.id == reference.id }
        if evidence.count == capacity { evidence.removeFirst() }
        evidence.append(reference)
    }

    public mutating func clear() {
        evidence.removeAll(keepingCapacity: true)
    }
}

public enum AgentMemoryEngine {
    private static let secondsPerDay = 86_400.0
    private static let inactiveStrength = 0.1

    /// Records experience only; accepting an observation does not establish story state.
    public static func record(feedback: FeedbackEvent, observation: AgentObservation, in library: inout Library) {
        guard !library.feedback.contains(where: { $0.id == feedback.id }) else { return }
        library.feedback.append(feedback)
        library.memories.append(AgentMemory(
            agentID: feedback.agentID,
            worldID: feedback.worldID,
            layer: "episodic",
            category: normalized(feedback.category),
            belief: "Writer \(feedback.action.rawValue) this concern: \(observation.message)",
            salience: feedback.action == .markedIntentional ? 0.8 : 0.6,
            strength: 1,
            confidence: observation.confidence,
            decayRate: 0.04,
            createdAt: feedback.createdAt,
            lastRecalledAt: feedback.createdAt,
            sourceFeedbackIDs: [feedback.id]
        ))
    }

    /// Decay is evaluated lazily, not reapplied to stored strength on every session end.
    /// Weak memories remain inspectable but are retired from recall and behavior.
    public static func effectiveStrength(of memory: AgentMemory, at now: Date = Date()) -> Double {
        guard memory.createdAt <= now else { return 0 }
        let elapsed = max(0, now.timeIntervalSince(memory.lastRecalledAt)) / secondsPerDay
        return max(0, memory.strength) * exp(-max(0, memory.decayRate) * elapsed)
    }

    @discardableResult
    public static func consolidate(worldID: ID, in library: inout Library, now: Date = Date()) -> String {
        var seen = Set<ID>()
        let feedback = library.feedback.filter {
            $0.worldID == worldID && $0.createdAt <= now && isDecision($0.action) && seen.insert($0.id).inserted
        }
        let groups = Dictionary(grouping: feedback) { Group(agentID: $0.agentID, category: normalized($0.category)) }
        var created = 0
        var reinforced = 0
        var mixed = 0

        for key in groups.keys.sorted(by: { ($0.agentID, $0.category) < ($1.agentID, $1.category) }) {
            guard let events = groups[key], events.count >= 2 else { continue }
            let sources = events.map(\.id).sorted()
            let accepted = events.filter { $0.action == .accepted }.count
            let intentional = events.filter { $0.action == .markedIntentional }.count
            let dismissed = events.filter { $0.action == .dismissed }.count
            if accepted > 0 && intentional + dismissed > 0 { mixed += 1 }
            let belief = semanticBelief(category: key.category, accepted: accepted, intentional: intentional, dismissed: dismissed)
            let confidence = 0.55 + 0.4 * Double(abs(intentional + dismissed - accepted)) / Double(events.count)
            if let index = library.memories.firstIndex(where: {
                $0.worldID == worldID && $0.agentID == key.agentID && normalized($0.category) == key.category && $0.layer == "semantic"
            }) {
                let previous = library.memories[index]
                let previousSources = Set(previous.sourceFeedbackIDs)
                let newEvents = events.filter { !previousSources.contains($0.id) }
                // Crucially, rereading the same episodes cannot strengthen a belief.
                guard !newEvents.isEmpty else { continue }
                let reinforcement = newEvents.reduce(0.0) { $0 + feedbackWeight($1, at: now, rate: previous.decayRate) * 0.5 }
                library.memories[index].strength = min(2, effectiveStrength(of: previous, at: now) + reinforcement)
                // Consolidation activates the belief; recallCount counts explicit recalls only.
                library.memories[index].lastRecalledAt = max(previous.lastRecalledAt, now)
                library.memories[index].sourceFeedbackIDs = sources
                library.memories[index].belief = belief
                library.memories[index].confidence = confidence
                reinforced += 1
            } else {
                let strength = min(2, events.reduce(0.0) { $0 + feedbackWeight($1, at: now, rate: 0.02) * 0.5 })
                library.memories.append(AgentMemory(
                    agentID: key.agentID, worldID: worldID, layer: "semantic", category: key.category,
                    belief: belief, salience: 0.8, strength: strength, confidence: confidence, decayRate: 0.02,
                    createdAt: now, lastRecalledAt: now, sourceFeedbackIDs: sources
                ))
                created += 1
            }
        }
        let inactive = library.memories.filter {
            $0.worldID == worldID && $0.createdAt <= now && effectiveStrength(of: $0, at: now) < inactiveStrength
        }.count
        return "Consolidated \(created) new beliefs; reinforced \(reinforced) with new feedback. \(mixed) mixed-feedback beliefs remain tentative. \(inactive) decayed memories are inactive and retained for inspection. Canon and story state are unchanged."
    }

    /// Only stylistic pattern sensitivity is learned. Authority and confidence gates are untouched.
    public static func adjustedAgents(in library: Library, worldID: ID, now: Date = Date()) -> [AgentDefinition] {
        var feedbackByID: [ID: FeedbackEvent] = [:]
        for feedback in library.feedback where feedback.worldID == worldID && feedback.createdAt <= now {
            if feedbackByID[feedback.id] == nil { feedbackByID[feedback.id] = feedback }
        }
        return library.agents.map { original in
            let categories = original.categories.map(normalized)
            guard categories.contains("STYLE"), !categories.contains("CONTINUITY") else { return original }
            var score = 0.0
            var counted = Set<ID>()
            for memory in library.memories where memory.agentID == original.id && memory.worldID == worldID && memory.layer == "semantic" && normalized(memory.category) == "STYLE" {
                let strength = effectiveStrength(of: memory, at: now)
                guard strength >= inactiveStrength else { continue }
                for source in memory.sourceFeedbackIDs {
                    guard let feedback = feedbackByID[source], feedback.agentID == original.id,
                          normalized(feedback.category) == "STYLE", counted.insert(source).inserted else { continue }
                    let weight = feedbackWeight(feedback, at: memory.lastRecalledAt, rate: memory.decayRate) * min(1, strength)
                    switch feedback.action {
                    case .dismissed, .markedIntentional: score += weight
                    case .accepted: score -= weight
                    default: break
                    }
                }
            }
            let adjustment = Int(max(-2, min(4, (score / 2).rounded())))
            guard adjustment != 0 else { return original }
            var adjusted = original
            adjusted.patternThreshold = max(1, original.patternThreshold + adjustment)
            return adjusted
        }
    }

    public static func recall(agentID: ID, worldID: ID, category: String, in library: inout Library, now: Date = Date()) -> [AgentMemory] {
        let category = normalized(category)
        var recalled: [AgentMemory] = []
        for index in library.memories.indices {
            let memory = library.memories[index]
            guard memory.agentID == agentID, memory.worldID == worldID, normalized(memory.category) == category,
                  memory.layer == "episodic" || memory.layer == "semantic", now >= memory.lastRecalledAt else { continue }
            let strength = effectiveStrength(of: memory, at: now)
            guard strength >= inactiveStrength else { continue }
            library.memories[index].strength = min(2, strength + 0.15 * max(0, min(1, memory.salience)))
            library.memories[index].lastRecalledAt = now
            library.memories[index].recallCount += 1
            recalled.append(library.memories[index])
        }
        return recalled.sorted {
            let left = $0.strength * $0.salience
            let right = $1.strength * $1.salience
            return left == right ? $0.id < $1.id : left > right
        }
    }

    private struct Group: Hashable {
        var agentID: ID
        var category: String
    }

    private static func normalized(_ category: String) -> String {
        category.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func isDecision(_ action: ObservationStatus) -> Bool {
        action == .accepted || action == .dismissed || action == .markedIntentional
    }

    private static func feedbackWeight(_ feedback: FeedbackEvent, at now: Date, rate: Double) -> Double {
        exp(-max(0, rate) * max(0, now.timeIntervalSince(feedback.createdAt)) / secondsPerDay)
    }

    private static func semanticBelief(category: String, accepted: Int, intentional: Int, dismissed: Int) -> String {
        let counts = "\(accepted) accepted, \(intentional) intentional, \(dismissed) dismissed"
        let conclusion: String
        if accepted > 0 && intentional + dismissed > 0 {
            conclusion = "Feedback conflicts; do not assume a universal preference."
        } else if accepted > 0 {
            conclusion = "The writer may find these concerns useful."
        } else {
            conclusion = "The writer may prefer fewer concerns of this kind."
        }
        let rule = category == "STYLE"
            ? "STYLE threshold uses age-weighted (intentional + dismissed − accepted) / 2, rounded, bounded −2…+4, and attenuated by memory strength."
            : "This belief never changes authoritative continuity thresholds."
        return "Tentative \(category) belief: \(counts). \(conclusion) \(rule) Not canon. Inspect source feedback for context."
    }
}
