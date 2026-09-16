import Foundation
import XCTest
@testable import GuildCore

final class CoordinatorTests: XCTestCase {
    @MainActor
    func testCancelledNonCooperativeProviderCannotPublishOldScene() async throws {
        let library = Greyhaven.make()
        let scene = try XCTUnwrap(library.scenes.first { $0.id == "scene-5" })
        let manuscript = try XCTUnwrap(library.manuscripts.first { $0.sceneID == scene.id })
        let context = ReviewContext(library: library, scene: scene, manuscript: manuscript)
        let gate = ProviderGate()
        let coordinator = ReviewCoordinator()
        var delivered = false
        coordinator.review(context, model: SuspendedProvider(gate: gate)) { _, _ in delivered = true }
        for _ in 0..<100 {
            if await gate.isWaiting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let reachedProvider = await gate.isWaiting
        XCTAssertTrue(reachedProvider)
        coordinator.cancel()
        await gate.release()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(delivered, "A stale provider must not publish after a scene switch or edit")
    }

    @MainActor
    func testModelFailureStillDeliversDeterministicConcerns() async throws {
        let library = Greyhaven.make()
        let scene = try XCTUnwrap(library.scenes.first { $0.id == "scene-5" })
        let manuscript = try XCTUnwrap(library.manuscripts.first { $0.sceneID == scene.id })
        let coordinator = ReviewCoordinator()
        let outcome: (ReviewResult, String?) = await withCheckedContinuation { continuation in
            coordinator.review(ReviewContext(library: library, scene: scene, manuscript: manuscript), model: FailingProvider()) { result, error in
                continuation.resume(returning: (result, error))
            }
        }
        XCTAssertTrue(outcome.0.observations.contains { $0.category == "CHARACTER" })
        XCTAssertTrue(outcome.0.observations.contains { $0.category == "CONTINUITY" })
        XCTAssertNotNil(outcome.1)
    }
}

private actor ProviderGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func pause() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
private struct SuspendedProvider: ModelProvider {
    let gate: ProviderGate
    let isAvailable = true
    let availabilityDescription = "Controlled delayed provider"
    func review(_ context: ReviewContext) async throws -> ReviewResult {
        await gate.pause()
        return ReviewResult()
    }
}
private struct FailingProvider: ModelProvider {
    let isAvailable = true
    let availabilityDescription = "Controlled provider error"
    struct Failure: Error {}
    func review(_ context: ReviewContext) async throws -> ReviewResult { throw Failure() }
}
