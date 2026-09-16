import Foundation
import Testing
@testable import GuildCore

struct StateTests {
    private func scene(_ id: ID, in library: Library) -> Scene { library.scenes.first { $0.id == id }! }
    private func evidence(_ id: String) -> EvidenceReference {
        EvidenceReference(id: id, kind: "manuscript", sourceID: "scene-4", label: id, quote: id)
    }

    @Test func futureKnowledgeDoesNotDependOnRetrievalOrder() {
        var library = Greyhaven.make()
        for _ in 0..<2 {
            let early = WorldState(library: library, scene: scene("scene-5", in: library))
            #expect(early.value(entityID: "jonas", property: "knowledge.brothersKiller")?.value == "false")
            #expect(early.value(entityID: "jonas", property: "knowledge.brothersKiller")?.evidence.contains { $0.id == "evidence-confession" } == false)
            let later = WorldState(library: library, scene: scene("scene-8", in: library))
            #expect(later.value(entityID: "jonas", property: "knowledge.brothersKiller")?.value == "true")
            #expect(later.value(entityID: "jonas", property: "knowledge.brothersKiller")?.evidence.last?.sourceID == "scene-8")
            library.events.reverse()
            library.scenes.reverse()
            library.manuscripts.reverse()
        }
    }

    @Test func flashbackUsesChronologyNotPresentationOrder() {
        let library = Greyhaven.make()
        let flashback = scene("scene-flashback", in: library)
        #expect(flashback.order > scene("scene-5", in: library).order)
        let state = WorldState(library: library, scene: flashback)
        #expect(state.value(entityID: "rowan", property: "rank")?.value == "Private")
        #expect(state.value(entityID: "brass-key", property: "owner")?.value == "elise")
    }

    @Test func storiesAndWorldsAreIsolated() {
        var library = Greyhaven.make()
        library.worlds.append(World(id: "elsewhere", name: "Elsewhere"))
        library.entities.append(Entity(id: "outsider", worldID: "elsewhere", name: "Outsider"))
        library.facts.append(CanonicalFact(id: "foreign", worldID: "elsewhere", entityID: "rowan", property: "rank", value: "King", evidence: evidence("foreign")))
        library.facts.append(CanonicalFact(id: "foreign-entity", worldID: "greyhaven", entityID: "outsider", property: "rank", value: "King", evidence: evidence("foreign-entity")))
        library.events.append(StoryEvent(id: "foreign-scene", storyID: "story-homecoming", sceneID: "scene-watch", time: 4, entityID: "rowan", property: "rank", value: "King", evidence: evidence("foreign-scene")))
        let home = WorldState(library: library, scene: scene("scene-5", in: library))
        let watch = WorldState(library: library, scene: scene("scene-watch", in: library))
        #expect(home.value(entityID: "rowan", property: "rank")?.value == "Corporal")
        #expect(home.value(entityID: "outsider", property: "rank") == nil)
        #expect(watch.value(entityID: "rowan", property: "rank")?.value == "Private")
        #expect(watch.value(entityID: "brass-key", property: "owner")?.value == "mara")
        #expect(watch.value(entityID: "party", property: "location") == nil)
    }

    @Test func canonValidityUsesWorldOffsetAndTimelinePrecedence() {
        var library = Greyhaven.make()
        library.facts += [
            CanonicalFact(id: "future-canon", worldID: "greyhaven", entityID: "rowan", property: "rank", value: "Captain", validFrom: 100, evidence: evidence("future-canon")),
            CanonicalFact(id: "equal-time-canon", worldID: "greyhaven", entityID: "rowan", property: "rank", value: "Sergeant", validFrom: 4, evidence: evidence("equal-time-canon"))
        ]
        #expect(WorldState(library: library, scene: scene("scene-5", in: library)).value(entityID: "rowan", property: "rank")?.value == "Corporal")
        #expect(WorldState(library: library, scene: scene("scene-watch", in: library)).value(entityID: "rowan", property: "rank")?.value == "Captain")
        library.facts.append(CanonicalFact(id: "later-canon", worldID: "greyhaven", entityID: "rowan", property: "rank", value: "Major", validFrom: 5, evidence: evidence("later-canon")))
        #expect(WorldState(library: library, scene: scene("scene-5", in: library)).value(entityID: "rowan", property: "rank")?.value == "Major")
    }

    @Test func sequenceCutoffIsExclusiveOnlyAtQueriedTime() {
        var library = Greyhaven.make()
        library.events.append(StoryEvent(id: "event-same-time", storyID: "story-homecoming", sceneID: "scene-5", time: 5, sequence: 2, entityID: "rowan", property: "rank", value: "Sergeant", evidence: evidence("same-time")))
        let late = scene("scene-5", in: library)
        #expect(WorldState(library: library, scene: late, beforeSequence: 0).value(entityID: "rowan", property: "rank")?.value == "Corporal")
        #expect(WorldState(library: library, scene: late, beforeSequence: 2).value(entityID: "rowan", property: "rank")?.value == "Corporal")
        #expect(WorldState(library: library, scene: late, beforeSequence: 3).value(entityID: "rowan", property: "rank")?.value == "Sergeant")
    }

    @Test func tiesAreStableAndEvidenceRetainsTransitionProvenance() {
        var library = Greyhaven.make()
        for (id, rank) in [("tie-a", "Sergeant"), ("tie-z", "Captain")] {
            library.events.append(StoryEvent(id: id, storyID: "story-homecoming", sceneID: "scene-5", time: 5, sequence: 1, entityID: "rowan", property: "rank", value: rank, evidence: evidence(id)))
        }
        let expected = WorldState(library: library, scene: scene("scene-5", in: library)).value(entityID: "rowan", property: "rank")
        library.events.reverse()
        library.facts.reverse()
        let reordered = WorldState(library: library, scene: scene("scene-5", in: library)).value(entityID: "rowan", property: "rank")
        #expect(expected == reordered)
        #expect(expected?.value == "Captain")
        #expect(expected?.evidence.map(\.id) == ["evidence-rank", "evidence-promotion", "tie-a", "tie-z"])
    }

    @Test func unacceptedAndAcceptedClaimsDoNotBecomeEvents() {
        var library = Greyhaven.make()
        let manuscript = library.manuscripts.first { $0.sceneID == "scene-5" }!
        let anchor = AnchorResolver.make(manuscript: manuscript, range: (manuscript.text as NSString).range(of: "Private Rowan"))
        for status in [ClaimStatus.pending, .conflict, .accepted] {
            library.claims.append(NarrativeClaim(storyID: "story-homecoming", sceneID: "scene-5", entityID: "rowan", property: "rank", value: "Private", isTransition: false, anchor: anchor, status: status))
        }
        #expect(WorldState(library: library, scene: scene("scene-5", in: library)).value(entityID: "rowan", property: "rank")?.value == "Corporal")
    }
}
