import Foundation
import LLM

final class TextCleaner {
    private let cleanupManager: TextCleanupManager

    static let systemPrompt = """
    Clean up this speech transcription. Remove filler words (um, uh, like, you know, so, basically, literally, right, I mean). \
    If the speaker corrects themselves (e.g. "actually let's say X", "no wait X", "I mean X", "sorry, X"), keep only the final correction. \
    Do not change the meaning, tone, or add any words. If the text is already clean or very short, return it unchanged. \
    Output only the cleaned text, nothing else.
    """

    private static let timeoutSeconds: TimeInterval = 3.0

    init(cleanupManager: TextCleanupManager) {
        self.cleanupManager = cleanupManager
    }

    /// Cleans up transcribed text using the local LLM.
    /// Returns the cleaned text, or the original text if cleanup fails or times out.
    @MainActor
    func clean(text: String) async -> String {
        guard let llm = cleanupManager.llm else { return text }

        // Reset history for each cleanup (no conversation memory needed)
        llm.history = []

        do {
            let result = try await withTimeout(seconds: Self.timeoutSeconds) {
                await llm.respond(to: text)
                return llm.output
            }
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? text : cleaned
        } catch {
            return text
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
