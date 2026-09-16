import Foundation
import Testing
@testable import GuildCore

struct AnalysisTests {
    private func context(_ text: String? = nil, library: Library = Greyhaven.make(), sceneID: ID = "scene-5") -> ReviewContext {
        let scene = library.scenes.first { $0.id == sceneID }!
        var manuscript = library.manuscripts.first { $0.sceneID == sceneID }!
        if let text { manuscript.text = text; manuscript.revision += 1 }
        return ReviewContext(library: library, scene: scene, manuscript: manuscript)
    }

    @Test func requiredGreyhavenMistakesCarryPriorAndCurrentEvidence() async throws {
        let context = context()
        let result = try await DeterministicAnalyzer().analyze(context)
        let geography = try #require(result.observations.first { $0.id.contains(":direction-") })
        #expect(geography.anchor.quote == "headed south toward Old Town")
        #expect(Set(geography.evidence.map(\.sourceID)).isSuperset(of: ["lore-geography", "scene-1", "scene-5"]))
        let rank = try #require(result.observations.first { $0.id.contains(":rank-") })
        #expect(rank.anchor.quote == "Private Rowan")
        #expect(rank.evidence.contains { $0.sourceID == "scene-4" && $0.quote == "Rowan was promoted to Corporal." })
        let promotion = try #require(result.observations.first { $0.id.contains(":promotion-") })
        #expect(promotion.anchor.quote == "Rowan was promoted to Corporal")
        #expect(promotion.evidence.contains { $0.sourceID == "scene-4" })
        let possession = try #require(result.observations.first { $0.id.contains(":owner-") })
        #expect(possession.anchor.quote == "Mara unlocked the door with the brass key")
        #expect(possession.evidence.contains { $0.sourceID == "scene-2" && $0.anchor != nil })
        let name = try #require(result.observations.first { $0.category == "NAME" })
        #expect(name.anchor.quote == "Marenn Vale")
        #expect(name.evidence.contains { $0.sourceID == "maren" && $0.quote == "Maren Vale" })
        #expect(result.observations.contains { $0.category == "TENSE" && $0.anchor.quote.contains("Mara steps into the light") })
        #expect(result.observations.contains { $0.id.contains(":hedges:") && $0.anchor.quote.contains("somewhat") })
        #expect(result.observations.contains { $0.id.contains(":opening-the bell:") })
        for observation in result.observations {
            #expect((context.manuscript.text as NSString).substring(with: NSRange(location: observation.anchor.start, length: observation.anchor.length)) == observation.anchor.quote)
            #expect(observation.evidence.contains { $0.sourceID == context.scene.id && $0.anchor == observation.anchor })
            for reference in observation.evidence where reference.kind == "manuscript" {
                let source = try #require(context.library.manuscripts.first { $0.sceneID == reference.sourceID })
                #expect(source.text.contains(reference.quote))
            }
        }
    }

    @Test func claimsAreUnacceptedAndDoNotMutateSnapshot() async throws {
        let input = context("Private Rowan stepped forward. Rowan was promoted to Corporal. Mara held the brass key.")
        let original = input.library
        let result = try await DeterministicAnalyzer().analyze(input)
        #expect(result.claims.contains { $0.entityID == "rowan" && $0.property == "rank" && $0.value == "Private" && $0.status == .conflict && !$0.isTransition })
        #expect(result.claims.contains { $0.entityID == "rowan" && $0.value == "Corporal" && $0.isTransition && $0.status == .pending })
        #expect(result.claims.contains { $0.entityID == "brass-key" && $0.value == "mara" && $0.status == .conflict })
        #expect(result.claims.allSatisfy { $0.status != .accepted })
        #expect(input.library == original)
        #expect(WorldState(library: input.library, scene: input.scene).value(entityID: "rowan", property: "rank")?.value == "Corporal")
    }

    @Test func returnedKeySuppressesPossessionConcernOnlyWhenChronologicallyPrior() async throws {
        var library = Greyhaven.make()
        let quote = "Elise returned the brass key to Mara."
        let index = library.manuscripts.firstIndex { $0.sceneID == "scene-4" }!
        library.manuscripts[index].text += "\n" + quote
        library.manuscripts[index].html += "<p>\(quote)</p>"
        let manuscript = library.manuscripts[index]
        let source = EvidenceReference(id: "return-source", kind: "manuscript", sourceID: "scene-4", label: "Chapter 4", quote: quote,
                                       anchor: AnchorResolver.make(manuscript: manuscript, range: (manuscript.text as NSString).range(of: quote)))
        library.events.append(StoryEvent(id: "returned-key", storyID: "story-homecoming", sceneID: "scene-4", time: 4, sequence: 1,
                                        entityID: "brass-key", property: "owner", value: "mara", previousValue: "elise", evidence: source))
        let returned = try await DeterministicAnalyzer().analyze(context("Mara unlocked the door with the brass key.", library: library))
        #expect(!returned.observations.contains { $0.id.contains(":owner-") })
        #expect(returned.claims.first?.status == .pending)
        library.events[library.events.count - 1].time = 8
        let notYet = try await DeterministicAnalyzer().analyze(context("Mara unlocked the door with the brass key.", library: library))
        #expect(notYet.observations.contains { $0.id.contains(":owner-") })
    }

    @Test func namesAndAliasesAreGenericNotFixtureSpecialCases() async throws {
        var library = Greyhaven.make()
        library.entities[library.entities.firstIndex { $0.id == "rowan" }!].name = "Tessa Quinn"
        library.entities[library.entities.firstIndex { $0.id == "rowan" }!].aliases = ["Tess"]
        library.entities[library.entities.firstIndex { $0.id == "old-town" }!].name = "New Harbor"
        library.entities[library.entities.firstIndex { $0.id == "old-town" }!].aliases = ["the Harbor"]
        library.entities[library.entities.firstIndex { $0.id == "brass-key" }!].name = "copper token"
        library.entities[library.entities.firstIndex { $0.id == "brass-key" }!].aliases = ["token"]
        let result = try await DeterministicAnalyzer().analyze(context("Private Tess waited. Tessa Quinn was promoted to Corporal. They headed south toward New Harbor. Mara held the copper token. Tesssa Quinn nodded.", library: library))
        #expect(result.observations.contains { $0.anchor.quote == "Private Tess" })
        #expect(result.observations.contains { $0.id.contains(":promotion-") })
        #expect(result.observations.contains { $0.id.contains(":direction-") })
        #expect(result.observations.contains { $0.id.contains(":owner-") })
        #expect(result.observations.contains { $0.category == "NAME" && $0.anchor.quote == "Tesssa Quinn" })
    }

    @Test func correctStateAliasesAndDirectionDoNotTriggerContinuityWarnings() async throws {
        let result = try await DeterministicAnalyzer().analyze(context("Corporal Rowan Ash waited. They headed north toward Old Town. Elise held the brass key. Maren waited beside Maren Vale."))
        #expect(!result.observations.contains { ["CONTINUITY", "CHARACTER", "NAME"].contains($0.category) })
        let flashback = try await DeterministicAnalyzer().analyze(context(sceneID: "scene-flashback"))
        #expect(!flashback.observations.contains { $0.category == "CHARACTER" })
        let otherStory = try await DeterministicAnalyzer().analyze(context(sceneID: "scene-watch"))
        #expect(!otherStory.observations.contains { ["CONTINUITY", "CHARACTER"].contains($0.category) })
    }

    @Test func foreignEntitiesCannotSupplyNameOrRelationshipEvidence() async throws {
        var library = Greyhaven.make()
        library.entities.append(Entity(id: "foreign-name", worldID: "foreign", name: "Davina"))
        let result = try await DeterministicAnalyzer().analyze(context("Davinna waited by the gate.", library: library))
        #expect(!result.observations.contains { $0.category == "NAME" })
    }

    @Test func profilesControlEnablementConfidenceAndPatternThreshold() async throws {
        var library = Greyhaven.make()
        for index in library.agents.indices { library.agents[index].enabled = false }
        let disabled = try await DeterministicAnalyzer().analyze(context(library: library))
        #expect(disabled.observations.isEmpty)
        #expect(disabled.claims.contains { $0.property == "rank" })
        for index in library.agents.indices {
            library.agents[index].enabled = true
            library.agents[index].confidenceThreshold = 1
        }
        #expect(try await DeterministicAnalyzer().analyze(context(library: library)).observations.isEmpty)
        library.agents = DeterministicAnalyzer.defaultAgents
        library.agents[library.agents.firstIndex { $0.id == "guild.style" }!].patternThreshold = 6
        let raised = try await DeterministicAnalyzer().analyze(context(library: library))
        #expect(!raised.observations.contains { $0.category == "STYLE" })
        #expect(raised.observations.contains { $0.category == "CHARACTER" })
    }

    @Test func tenseRequiresSustainedNarrationAndSkipsQuotedDialogue() async throws {
        let isolated = try await DeterministicAnalyzer().analyze(context("Rowan opens the door. Mara waited. Elise held the key."))
        #expect(!isolated.observations.contains { $0.category == "TENSE" })
        let dialogue = try await DeterministicAnalyzer().analyze(context("“Rowan opens the door.” “Mara steps aside.” “Elise watches the road.”"))
        #expect(!dialogue.observations.contains { $0.category == "TENSE" })
        let passage = "Rowan opens the door. Mara steps aside. Elise watches the road."
        let sustained = try await DeterministicAnalyzer().analyze(context(passage))
        #expect(sustained.observations.first { $0.category == "TENSE" }?.anchor.quote == passage)
        var presentContext = context("Rowan opened the door. Mara stepped aside. Elise watched the road.")
        presentContext.scene.expectedTense = "present"
        #expect(try await DeterministicAnalyzer().analyze(presentContext).observations.contains { $0.category == "TENSE" })
    }

    @Test func hedgeClustersAreParagraphLocalAndRepetitionIsMeaningful() async throws {
        let scattered = try await DeterministicAnalyzer().analyze(context("Perhaps the rain would stop.\nThe road seemed empty.\nMaybe dawn would help."))
        #expect(!scattered.observations.contains { $0.id.contains(":hedges:") })
        let cluster = try await DeterministicAnalyzer().analyze(context("Perhaps the room seemed almost safe."))
        #expect(cluster.observations.contains { $0.id.contains(":hedges:") })
        let repeated = try await DeterministicAnalyzer().analyze(context("Silence filled the room, silence hid the fear, and silence greeted the dawn."))
        #expect(repeated.observations.contains { $0.id.contains(":word-silence:") })
        let common = try await DeterministicAnalyzer().analyze(context("They walked with care. They spoke with warmth. They rested with hope."))
        #expect(!common.observations.contains { $0.id.contains(":word-with:") })
    }

    @Test func acceptedPromotionDoesNotFlagItsOwnSourceButLaterRepeatDoes() async throws {
        let established = try await DeterministicAnalyzer().analyze(context(sceneID: "scene-4"))
        #expect(!established.observations.contains { $0.id.contains(":promotion-") })
        #expect(!established.claims.contains { $0.isTransition && $0.property == "rank" })
        var library = Greyhaven.make()
        let manuscriptIndex = library.manuscripts.firstIndex { $0.sceneID == "scene-4" }!
        let prose = "Private Rowan waited. Rowan was promoted to Corporal. Private Rowan objected. Rowan was promoted to Corporal."
        library.manuscripts[manuscriptIndex].text = prose
        library.manuscripts[manuscriptIndex].revision += 1
        let eventIndex = library.events.firstIndex { $0.id == "event-promotion" }!
        let sourceRange = (prose as NSString).range(of: "Rowan was promoted to Corporal.")
        library.events[eventIndex].evidence.anchor = AnchorResolver.make(manuscript: library.manuscripts[manuscriptIndex], range: sourceRange)
        let result = try await DeterministicAnalyzer().analyze(context(library: library, sceneID: "scene-4"))
        let promotions = result.observations.filter { $0.id.contains(":promotion-") }
        #expect(promotions.count == 1)
        #expect(promotions.first?.anchor.start == (prose as NSString).range(of: "Rowan was promoted", options: .backwards).location)
        let ranks = result.observations.filter { $0.id.contains(":rank-") }
        #expect(ranks.count == 1)
        #expect(ranks.first?.anchor.start == (prose as NSString).range(of: "Private Rowan", options: .backwards).location)
    }

    @Test func pronounGeographyRequiresOneLocatedGroupButNamedGroupsRemainResolvable() async throws {
        var library = Greyhaven.make()
        library.entities[library.entities.firstIndex { $0.id == "party" }!].kind = "group"
        let single = try await DeterministicAnalyzer().analyze(context("They headed south toward Old Town.", library: library))
        #expect(single.observations.contains { $0.id.contains(":direction-") })
        library.entities.append(Entity(id: "second-group", worldID: "greyhaven", name: "The scouts", kind: "group"))
        let evidence = EvidenceReference(id: "scout-location", kind: "lore", sourceID: "lore-geography", label: "Scouts", quote: "The scouts wait at the southern exit.")
        library.facts.append(CanonicalFact(id: "scout-location", worldID: "greyhaven", entityID: "second-group", property: "location", value: "south-exit", evidence: evidence))
        let ambiguous = try await DeterministicAnalyzer().analyze(context("They headed south toward Old Town.", library: library))
        #expect(!ambiguous.observations.contains { $0.id.contains(":direction-") })
        let explicit = try await DeterministicAnalyzer().analyze(context("The scouts headed south toward Old Town.", library: library))
        #expect(explicit.observations.contains { $0.id.contains(":direction-second-group-") })
    }

    @Test func repeatedReviewsHaveStableObservationIdentity() async throws {
        var input = context()
        let first = try await DeterministicAnalyzer().analyze(input)
        input.library.events.reverse()
        input.library.entities.reverse()
        input.library.facts.reverse()
        let reordered = try await DeterministicAnalyzer().analyze(input)
        #expect(first.observations.map(\.id) == reordered.observations.map(\.id))
        #expect(first.observations.map(\.evidence) == reordered.observations.map(\.evidence))
        #expect(first.claims == reordered.claims)
    }
}
