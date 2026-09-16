import Foundation
import XCTest
import GuildCore
@testable import GuildAI

@MainActor
final class ModelBoundaryTests: XCTestCase {
    private func fixture(text: String = "Private Rowan stepped forward.") -> ReviewContext {
        let scene = Scene(id: "now", storyID: "story", title: "Now", order: 1, time: 5)
        var library = Library()
        library.worlds = [World(id: "world", name: "World"), World(id: "other-world", name: "Elsewhere")]
        library.stories = [Story(id: "story", worldID: "world", title: "Story", worldOffset: 100),
                           Story(id: "sibling", worldID: "world", title: "Other Story")]
        library.scenes = [scene, Scene(id: "future", storyID: "story", title: "Future", order: 0, time: 6),
                          Scene(id: "sibling-scene", storyID: "sibling", title: "Sibling", order: 0, time: 1)]
        library.entities = [Entity(id: "rowan", worldID: "world", name: "Rowan"),
                            Entity(id: "outsider", worldID: "other-world", name: "Rowan")]
        library.agents = [AgentDefinition(id: "guild.character", name: "Character", role: "State critic", categories: ["CHARACTER"], traits: ["Precise"])]
        library.facts = [CanonicalFact(id: "rank", worldID: "world", entityID: "rowan", property: "rank", value: "Corporal",
                                      evidence: EvidenceReference(id: "canon-rank", kind: "canon", sourceID: "rank", label: "Rank", quote: "Rowan is Corporal."))]
        return ReviewContext(library: library, scene: scene, manuscript: Manuscript(sceneID: scene.id, text: text, revision: 2))
    }

    private func prepared(_ context: ReviewContext) async throws -> (ReviewGrounding, ReviewPacket) {
        let grounding = try ReviewGrounding(context: context, range: NSRange(location: 0, length: context.manuscript.text.utf16.count))
        return (grounding, try await grounding.prepare())
    }

    private func observation(_ packet: ReviewPacket) throws -> ReviewSelection.Observation {
        .init(fact: try XCTUnwrap(packet.state.first?.id), passage: try XCTUnwrap(packet.current.first?.id),
              agentID: "guild.character", message: "Rowan's title differs from their established rank.",
              question: "Is the old rank intentional?", confidence: 0.9)
    }

    private func rejects(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await operation()
            XCTFail("Expected ungrounded output rejection", file: file, line: line)
        } catch AppleModelError.invalidOutput { }
        catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }

    func testPreparedReviewBuildsExactCitationsWithoutModelToolCalls() async throws {
        let context = fixture()
        let (grounding, packet) = try await prepared(context)
        let result = try await grounding.materialize(.init(claims: [], observations: [observation(packet)]))
        let actual = try XCTUnwrap(result.observations.first)
        XCTAssertEqual(actual.evidence.map(\.sourceID), [context.scene.id, "rank"])
        XCTAssertEqual(actual.evidence.last?.id, "canon-rank")
        XCTAssertEqual(actual.anchor.quote, context.manuscript.text)
        XCTAssertEqual(actual.anchor.revision, 2)
        XCTAssertEqual(packet.entities.map(\.id), ["rowan"])
        var invented = try observation(packet)
        invented.fact = "current"
        await rejects { _ = try await grounding.materialize(.init(claims: [], observations: [invented])) }
    }

    func testFutureAndSiblingEventsCannotGroundCurrentReview() async throws {
        var context = fixture()
        context.library.events = [
            StoryEvent(id: "future-event", storyID: "story", sceneID: "future", time: 6, entityID: "rowan", property: "rank", value: "Captain",
                       evidence: EvidenceReference(id: "future-evidence", kind: "event", sourceID: "future-event", label: "Future promotion", quote: "Captain")),
            StoryEvent(id: "sibling-event", storyID: "sibling", sceneID: "sibling-scene", time: 1, entityID: "rowan", property: "rank", value: "General",
                       evidence: EvidenceReference(id: "sibling-evidence", kind: "event", sourceID: "sibling-event", label: "Other story", quote: "General"))
        ]
        let (grounding, packet) = try await prepared(context)
        XCTAssertEqual(packet.state.map(\.value), ["Corporal"])
        let result = try await grounding.materialize(.init(claims: [], observations: [observation(packet)]))
        XCTAssertEqual(result.observations.first?.evidence.dropFirst().map(\.id), ["canon-rank"])
        var proposed = try observation(packet)
        proposed.fact = "future-evidence"
        await rejects { _ = try await grounding.materialize(.init(claims: [], observations: [proposed])) }
    }

    func testFutureCanonUsesAbsoluteWorldTime() async throws {
        var context = fixture()
        context.library.facts.append(CanonicalFact(id: "future-fact", worldID: "world", entityID: "rowan", property: "rank", value: "King", validFrom: 106,
                                                  evidence: EvidenceReference(id: "future-canon", kind: "canon", sourceID: "future-fact", label: "Future", quote: "King")))
        let (_, packet) = try await prepared(context)
        XCTAssertEqual(packet.state.map(\.value), ["Corporal"])
    }

    func testFutureSourceCannotExposeAuthorityOrRelatedEntities() async throws {
        var context = fixture()
        context.library.entities.append(Entity(id: "secret", worldID: "world", name: "Secret heir"))
        context.library.manuscripts.append(Manuscript(sceneID: "future", text: "Secret heir", revision: 0))
        context.library.facts[0].value = "secret"
        context.library.facts[0].evidence = EvidenceReference(id: "future-anchor", kind: "manuscript", sourceID: "future", label: "Future", quote: "Secret heir",
            anchor: TextAnchor(sceneID: "future", revision: 0, start: 0, length: 11, quote: "Secret heir"))
        let (_, packet) = try await prepared(context)
        XCTAssertTrue(packet.state.isEmpty)
        XCTAssertEqual(packet.entities.map(\.id), ["rowan"])
    }

    func testHallucinatedAgentAndOtherWorldIDsCannotBecomeClaimSubjects() async throws {
        let (grounding, packet) = try await prepared(fixture())
        var claim = ReviewSelection.Claim(entityID: "invented", passage: try XCTUnwrap(packet.current.first?.id),
            property: "rank", value: "Private", isTransition: false, confidence: 0.9)
        await rejects { _ = try await grounding.materialize(.init(claims: [claim], observations: [])) }
        claim.entityID = "guild.character"
        await rejects { _ = try await grounding.materialize(.init(claims: [claim], observations: [])) }
        claim.entityID = "outsider"
        await rejects { _ = try await grounding.materialize(.init(claims: [claim], observations: [])) }
    }

    func testWrongQuoteAndOutOfPassageAnchorAreRejected() async throws {
        let (grounding, packet) = try await prepared(fixture())
        let result = try await grounding.materialize(.init(claims: [], observations: [observation(packet)]))
        let actual = try XCTUnwrap(result.observations.first)
        var proposed = ProposedObservation(agentID: actual.agentID, category: actual.category, entityIDs: ["rowan"], confidence: 0.9,
            anchor: ProposedAnchor(start: 0, length: 13, quote: "Captain Rowan"), message: actual.message,
            question: "Intentional?", evidenceIDs: actual.evidence.map(\.id))
        await rejects { _ = try await grounding.validate(claims: [], observations: [proposed]) }
        proposed.anchor = ProposedAnchor(start: Int.max, length: 13, quote: "Private Rowan")
        await rejects { _ = try await grounding.validate(claims: [], observations: [proposed]) }
    }

    func testSwiftBuildsUTF16AnchorsAndClaimsNeverPromoteState() async throws {
        let context = fixture(text: "🗝\nPrivate Rowan stepped forward.")
        let (grounding, packet) = try await prepared(context)
        let passage = try XCTUnwrap(packet.current.first { $0.text.hasPrefix("Private") })
        var claim = ReviewSelection.Claim(entityID: "rowan", passage: passage.id, property: "rank", value: "Private", isTransition: false, confidence: 0.9)
        let result = try await grounding.materialize(.init(claims: [claim], observations: []))
        XCTAssertEqual(result.claims.first?.status, .conflict)
        XCTAssertEqual(result.claims.first?.anchor.start, 3)
        XCTAssertEqual(result.claims.first?.anchor.quote, passage.text)
        XCTAssertEqual(WorldState(library: context.library, scene: context.scene).value(entityID: "rowan", property: "rank")?.value, "Corporal")
        claim.isTransition = true
        let proposal = try await grounding.materialize(.init(claims: [claim], observations: []))
        XCTAssertEqual(proposal.claims.first?.status, .pending)
        claim.passage = "invented-passage"
        await rejects { _ = try await grounding.materialize(.init(claims: [claim], observations: [])) }
    }

    func testMemoryCannotSubstituteForAuthoritativeEvidence() async throws {
        var context = fixture()
        context.library.memories = [AgentMemory(id: "memory", agentID: "guild.character", worldID: "world", layer: "semantic", category: "CHARACTER", belief: "Rowan might be Private.")]
        let (grounding, packet) = try await prepared(context)
        var proposed = try observation(packet)
        proposed.fact = "memory"
        await rejects { _ = try await grounding.materialize(.init(claims: [], observations: [proposed])) }
    }

    func testNonfiniteConfidenceAndDisabledAgentAreRejected() async throws {
        var context = fixture()
        context.library.agents.append(AgentDefinition(id: "disabled", name: "Disabled", role: "State critic", categories: ["CHARACTER"], traits: [], enabled: false))
        let (grounding, packet) = try await prepared(context)
        var proposed = try observation(packet)
        proposed.confidence = .nan
        await rejects { _ = try await grounding.materialize(.init(claims: [], observations: [proposed])) }
        proposed.confidence = 0.9
        proposed.agentID = "disabled"
        await rejects { _ = try await grounding.materialize(.init(claims: [], observations: [proposed])) }
    }

    func testKnownEntityNeedsNoLoreToProposeUnacceptedClaim() async throws {
        var context = fixture()
        context.library.facts = []
        let (grounding, packet) = try await prepared(context)
        XCTAssertTrue(packet.state.isEmpty)
        let claim = ReviewSelection.Claim(entityID: "rowan", passage: try XCTUnwrap(packet.current.first?.id),
            property: "rank", value: "Private", isTransition: false, confidence: 0.9)
        let result = try await grounding.materialize(.init(claims: [claim], observations: []))
        XCTAssertEqual(result.claims.first?.status, .pending)
        XCTAssertTrue(result.observations.isEmpty)
    }

    func testEntityResolutionDoesNotMatchNameInsideAnotherWord() async throws {
        let (_, packet) = try await prepared(fixture(text: "Rowanette stepped forward."))
        XCTAssertTrue(packet.entities.isEmpty)
        XCTAssertTrue(packet.state.isEmpty)
    }

    func testStateSelectionCannotBeReusedForAnotherPassage() async throws {
        let (grounding, packet) = try await prepared(fixture(text:
            "Private Rowan stepped forward.\nPrivate Rowan saluted."))
        let firstFact = try XCTUnwrap(packet.state.first { $0.passage == "P1" })
        var proposed = try observation(packet)
        proposed.fact = firstFact.id
        proposed.passage = "P2"
        await rejects { _ = try await grounding.materialize(.init(claims: [], observations: [proposed])) }
    }

    func testCurrentSceneTransitionUsesStateBeforeItsSourcePassage() async throws {
        let library = Greyhaven.make()
        let scene = try XCTUnwrap(library.scenes.first { $0.id == "scene-8" })
        let manuscript = try XCTUnwrap(library.manuscripts.first { $0.sceneID == scene.id })
        let (_, packet) = try await prepared(ReviewContext(library: library, scene: scene, manuscript: manuscript))
        let passage = try XCTUnwrap(packet.current.first)
        let fact = try XCTUnwrap(packet.state.first {
            $0.entityID == "jonas" && $0.property == "knowledge.brothersKiller" && $0.passage == passage.id
        })

        XCTAssertEqual(fact.value, "false")
        XCTAssertEqual(fact.source, "Jonas initially does not know who killed his brother.")
        let transition = ReviewSelection.Claim(entityID: "jonas", passage: passage.id,
            property: fact.property, value: "true", isTransition: true, confidence: 0.9)
        XCTAssertFalse(needsReviewComparison(transition, against: fact))
    }

    func testComparisonCandidatesAreLimitedToConflictsAndRepeatedTransitions() {
        let fact = ReviewPacket.Fact(id: "state", entityID: "rowan", property: "rank",
            value: "Corporal", source: "Rowan was promoted.", passage: "P1")
        var claim = ReviewSelection.Claim(entityID: "rowan", passage: "P1",
            property: "rank", value: "Private", isTransition: false, confidence: 0.9)
        XCTAssertTrue(needsReviewComparison(claim, against: fact))
        claim.value = "corporal"
        XCTAssertFalse(needsReviewComparison(claim, against: fact))
        claim.isTransition = true
        XCTAssertTrue(needsReviewComparison(claim, against: fact))
        claim.value = "Captain"
        XCTAssertFalse(needsReviewComparison(claim, against: fact))
        claim.passage = "P2"
        XCTAssertFalse(needsReviewComparison(claim, against: fact))
    }

    func testPassagesPreserveComposedTextAndAbsoluteOffsets() {
        let text = String(repeating: "a", count: 1_199) + "🗝e\u{301}end"
        let passages = reviewPassages(text)
        XCTAssertEqual(passages.map { (text as NSString).substring(with: $0) }.joined(), text)
        XCTAssertEqual(passages, [NSRange(location: 0, length: 1_199), NSRange(location: 1_199, length: 7)])
    }

    func testReviewCopyNamesTheConflictAndAsksForOneDecision() {
        let conflict = reviewCopy(entityName: "Rowan", property: "rank", currentValue: "Private",
                                  establishedValue: "Corporal", isTransition: false)
        XCTAssertEqual(conflict.message,
                       "Rowan's rank is Private here; immediately beforehand it was Corporal.")
        XCTAssertEqual(conflict.question,
                       "Did rank change to Private between the cited source and this passage, or should this be Corporal?")
        let repeated = reviewCopy(entityName: "Rowan", property: "rank", currentValue: "Corporal",
                                  establishedValue: "Corporal", isTransition: true)
        XCTAssertEqual(repeated.message,
                       "Rowan's rank changes to Corporal again here, although it was already Corporal.")
        XCTAssertEqual(repeated.question,
                       "Is this a deliberate retelling of the earlier change, or should the passage describe the existing rank?")
    }

    #if !canImport(FoundationModels)
    func testSDKWithoutFoundationModelsExplicitlyThrowsUnavailable() async {
        let provider = AppleModelProvider()
        XCTAssertFalse(provider.isAvailable)
        do {
            _ = try await provider.review(fixture())
            XCTFail("Unavailable model must not return fabricated observations")
        } catch AppleModelError.unavailable { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
    #endif
}
