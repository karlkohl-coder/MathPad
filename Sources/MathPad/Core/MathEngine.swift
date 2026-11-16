import Foundation

/// Anything that can *do something* with a formula rather than just display it:
/// a computer-algebra backend, a numeric evaluator, or — later — a model that
/// answers questions about it.
///
/// Nothing implements this yet. It exists so that the sketch editor already has
/// a place to send a formula to, and so a second feature can be added without
/// reshaping the document model.
protocol MathEngine: Sendable {
    /// Stable identifier, e.g. `"cas.local"` or `"ai.claude"`.
    var id: String { get }
    var displayName: String { get }

    /// Answer a question about a LaTeX expression.
    func respond(to request: MathRequest) async throws -> MathResponse
}

struct MathRequest: Sendable {
    /// The block the user is working on, as LaTeX.
    var latex: String
    /// Surrounding blocks, so an engine can resolve `x` defined three lines up.
    var context: [String]
    /// Free-form intent: `"simplify"`, `"solve"`, `"explain"`, …
    var intent: String
}

struct MathResponse: Sendable {
    /// LaTeX to offer as a result block, if any.
    var latex: String?
    /// Prose explanation, if any.
    var text: String?
}

/// Registry so features can look engines up by id instead of importing them.
@MainActor
final class MathEngineRegistry {
    static let shared = MathEngineRegistry()
    private(set) var engines: [String: any MathEngine] = [:]

    func register(_ engine: any MathEngine) { engines[engine.id] = engine }
    func engine(id: String) -> (any MathEngine)? { engines[id] }
}
