import Foundation
import Testing
@testable import GuildCore

struct MemoryTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let day = 86_400.0

    private func library() -> Library {
        var library = Library()
        library.worlds = [World(id: "world", name: "World"), World(id: "other", name: "Other")]
        library.stories = [Story(id: "story", worldID: "world", title: "Story")]
        library.scenes = [Scene(id: "scene", storyID: "story", title: "Scene", order: 0, time: 1)]
        library.agents = [
            AgentDefinition(id: "guild.style", name: "Style", role: "Style review", categories: ["STYLE"], traits: [], patternThreshold: 3),
            AgentDefinition(id: "guild.continuity", name: "Continuity", role: "Continuity review", categories: ["CONTINUITY"], traits: [], patternThreshold: 3)
        ]
        let evidence = EvidenceReference(id: "canon-source", kind: "lore", sourceID: "lore", label: "Rank", quote: "Rowan is a Private.")
        library.facts = [CanonicalFact(id: "rank", worldID: "world", entityID: "rowan", property: "rank", value: "Private", evidence: evidence)]
        library.events = [StoryEvent(id: "promotion", storyID: "story", sceneID: "scene", time: 1, entityID: "rowan", property: "rank", value: "Corporal", evidence: evidence)]
        return library
    }

    private func experience(_ id: String, action: ObservationStatus = .markedIntentional, world: ID = "world", category: String = "STYLE", at date: Date? = nil, in library: inout Library) {
        let agentID = category == "CONTINUITY" ? "guild.continuity" : "guild.style"
        let observation = AgentObservation(
            id: "observation-\(id)", agentID: agentID, category: category, confidence: 0.9,
            anchor: TextAnchor(sceneID: "scene", revision: 1, start: 0, length: 7, quote: "Perhaps"),
            message: "A cluster of hedges may weaken this paragraph.", evidence: [], createdAt: date ?? epoch
        )
        let feedback = FeedbackEvent(id: id, observationID: observation.id, agentID: agentID, worldID: world, category: category, action: action, createdAt: date ?? epoch)
        AgentMemoryEngine.record(feedback: feedback, observation: observation, in: &library)
    }

    @Test func recordingIsIdempotentAndNeverEstablishesFacts() throws {
        var library = library()
        let facts = library.facts
        let events = library.events
        let claims = library.claims
        experience("accepted", action: .accepted, in: &library)
        let recorded = library
        experience("accepted", action: .accepted, in: &library)
        #expect(library == recorded)
        let episode = try #require(library.memories.first)
        #expect(episode.layer == "episodic")
        #expect(episode.sourceFeedbackIDs == ["accepted"])
        #expect(episode.createdAt == epoch)
        #expect(library.facts == facts)
        #expect(library.events == events)
        #expect(library.claims == claims)
    }

    @Test func consolidationRequiresRepeatedFeedbackAndDoesNotRenewOldExperience() throws {
        var library = library()
        experience("one", in: &library)
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch)
        #expect(!library.memories.contains { $0.layer == "semantic" })
        experience("two", action: .dismissed, in: &library)
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch)
        let belief = try #require(library.memories.first { $0.layer == "semantic" })
        #expect(Set(belief.sourceFeedbackIDs) == Set(["one", "two"]))
        let consolidated = library
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch)
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch.addingTimeInterval(day * 500))
        #expect(library == consolidated)
        #expect(AgentMemoryEngine.adjustedAgents(in: library, worldID: "world", now: epoch.addingTimeInterval(day * 500)) == library.agents)
        #expect(AgentMemoryEngine.recall(agentID: "guild.style", worldID: "world", category: "STYLE", in: &library, now: epoch.addingTimeInterval(day * 500)).isEmpty)
        #expect(library == consolidated)
    }

    @Test func recallDecaysThenReinforcesAtTheRequestedTime() throws {
        var library = library()
        experience("one", in: &library)
        let original = try #require(library.memories.first)
        let now = epoch.addingTimeInterval(day * 5)
        let expectedDecay = exp(-original.decayRate * 5)
        #expect(abs(AgentMemoryEngine.effectiveStrength(of: original, at: now) - expectedDecay) < 0.000_001)
        let recalled = AgentMemoryEngine.recall(agentID: "guild.style", worldID: "world", category: "style", in: &library, now: now)
        let memory = try #require(recalled.first)
        #expect(abs(memory.strength - (expectedDecay + 0.15 * original.salience)) < 0.000_001)
        #expect(memory.recallCount == 1)
        #expect(memory.lastRecalledAt == now)
        #expect(memory.sourceFeedbackIDs == original.sourceFeedbackIDs)
        #expect(AgentMemoryEngine.effectiveStrength(of: memory, at: now.addingTimeInterval(day)) < memory.strength)
        let snapshot = library
        #expect(AgentMemoryEngine.recall(agentID: "guild.style", worldID: "world", category: "STYLE", in: &library, now: epoch).isEmpty)
        #expect(library == snapshot)
    }

    @Test func intentionalFeedbackChangesSubsequentStyleAnalysis() async throws {
        var library = library()
        let scene = try #require(library.scenes.first)
        let manuscript = Manuscript(sceneID: scene.id, html: "<p>Perhaps Rowan seemed almost ready.</p>", text: "Perhaps Rowan seemed almost ready.", revision: 1)
        let before = try await DeterministicAnalyzer().analyze(ReviewContext(library: library, scene: scene, manuscript: manuscript))
        #expect(before.observations.contains { $0.category == "STYLE" })
        experience("one", in: &library)
        experience("two", action: .dismissed, in: &library)
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch)
        let originalAgents = library.agents
        library.agents = AgentMemoryEngine.adjustedAgents(in: library, worldID: "world", now: epoch)
        #expect(library.agents[0].patternThreshold == 4)
        #expect(library.agents[0].confidenceThreshold == originalAgents[0].confidenceThreshold)
        let after = try await DeterministicAnalyzer().analyze(ReviewContext(library: library, scene: scene, manuscript: manuscript))
        #expect(!after.observations.contains { $0.category == "STYLE" })
    }

    @Test func acceptanceReinforcesUsefulConcernsAndConflictingFeedbackIsInspectable() throws {
        var library = library()
        experience("one", action: .accepted, in: &library)
        experience("two", action: .accepted, in: &library)
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch)
        let accepted = try #require(library.memories.first { $0.layer == "semantic" })
        #expect(AgentMemoryEngine.adjustedAgents(in: library, worldID: "world", now: epoch)[0].patternThreshold == 2)
        experience("three", action: .dismissed, in: &library)
        experience("four", in: &library)
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch)
        let mixed = try #require(library.memories.first { $0.layer == "semantic" })
        #expect(mixed.id == accepted.id)
        #expect(mixed.confidence < accepted.confidence)
        #expect(mixed.strength > accepted.strength)
        #expect(Set(mixed.sourceFeedbackIDs) == Set(["one", "two", "three", "four"]))
        #expect(AgentMemoryEngine.adjustedAgents(in: library, worldID: "world", now: epoch) == library.agents)
        let reinforced = library
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch)
        #expect(library == reinforced)
    }

    @Test func memoryCannotSuppressContinuityOrCrossWorldBoundaries() {
        var library = library()
        experience("other-one", action: .accepted, world: "other", in: &library)
        experience("other-two", action: .accepted, world: "other", in: &library)
        AgentMemoryEngine.consolidate(worldID: "other", in: &library, now: epoch)
        let otherMemories = library.memories.filter { $0.worldID == "other" }
        for id in ["one", "two", "three", "four"] {
            experience(id, in: &library)
            experience("continuity-\(id)", category: "CONTINUITY", in: &library)
        }
        let facts = library.facts
        let events = library.events
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch)
        let adjusted = AgentMemoryEngine.adjustedAgents(in: library, worldID: "world", now: epoch)
        #expect(adjusted[0].patternThreshold == 5)
        #expect(adjusted[1] == library.agents[1])
        #expect(AgentMemoryEngine.adjustedAgents(in: library, worldID: "other", now: epoch)[0].patternThreshold == 2)
        #expect(AgentMemoryEngine.adjustedAgents(in: library, worldID: "unknown", now: epoch) == library.agents)
        let recalled = AgentMemoryEngine.recall(agentID: "guild.style", worldID: "world", category: "STYLE", in: &library, now: epoch)
        #expect(Set(recalled.flatMap(\.sourceFeedbackIDs)) == Set(["one", "two", "three", "four"]))
        #expect(library.memories.filter { $0.worldID == "other" } == otherMemories)
        #expect(library.facts == facts)
        #expect(library.events == events)
    }

    @Test func futureFeedbackCannotAffectEarlierReview() {
        var library = library()
        let tomorrow = epoch.addingTimeInterval(day)
        experience("one", at: tomorrow, in: &library)
        experience("two", at: tomorrow, in: &library)
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: epoch)
        #expect(AgentMemoryEngine.adjustedAgents(in: library, worldID: "world", now: epoch) == library.agents)
        #expect(AgentMemoryEngine.recall(agentID: "guild.style", worldID: "world", category: "STYLE", in: &library, now: epoch).isEmpty)
        AgentMemoryEngine.consolidate(worldID: "world", in: &library, now: tomorrow)
        #expect(AgentMemoryEngine.adjustedAgents(in: library, worldID: "world", now: tomorrow)[0].patternThreshold == 4)
    }

    @Test func workingMemoryIsBoundedDeduplicatedAndReviewScoped() {
        var review = WorkingMemory(capacity: 2)
        let first = EvidenceReference(id: "first", kind: "text", sourceID: "scene", label: "First", quote: "One")
        let second = EvidenceReference(id: "second", kind: "text", sourceID: "scene", label: "Second", quote: "Two")
        let third = EvidenceReference(id: "third", kind: "text", sourceID: "scene", label: "Third", quote: "Three")
        review.remember(first)
        review.remember(second)
        review.remember(first)
        review.remember(third)
        #expect(review.evidence == [first, third])
        #expect(WorkingMemory().evidence.isEmpty)
        review.clear()
        #expect(review.evidence.isEmpty)
        var disabled = WorkingMemory(capacity: 0)
        disabled.remember(first)
        #expect(disabled.evidence.isEmpty)
    }
}
