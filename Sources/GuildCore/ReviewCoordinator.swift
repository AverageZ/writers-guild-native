import Foundation

/// The single launch point for reviews. A generation token prevents even non-cooperative
/// providers from publishing results after a cancellation or a document switch.
@MainActor
public final class ReviewCoordinator {
    private var task: Task<Void, Never>?
    private var generation = 0
    public init() {}

    public func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    public func review(_ context: ReviewContext, delay: Duration = .zero, model: (any ModelProvider)? = nil,
                       completion: @escaping @MainActor (ReviewResult, String?) -> Void) {
        cancel()
        let token = generation
        task = Task {
            do {
                if delay != .zero { try await Task.sleep(for: delay) }
                try Task.checkCancellation()
                var result = try await DeterministicAnalyzer().analyze(context)
                var modelError: String?
                if let model {
                    do {
                        let semantic = try await model.review(context)
                        result.observations += semantic.observations
                        result.claims += semantic.claims
                    } catch is CancellationError { throw CancellationError() }
                    catch { modelError = "Local semantic review: \(error.localizedDescription)" }
                }
                try Task.checkCancellation()
                guard token == generation else { return }
                completion(result, modelError)
            } catch is CancellationError { }
            catch {
                guard token == generation else { return }
                completion(ReviewResult(), error.localizedDescription)
            }
        }
    }
}
