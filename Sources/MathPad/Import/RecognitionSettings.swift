import Foundation
import Observation

/// Which engine reads a worksheet.
enum RecognitionEngine: String, CaseIterable, Identifiable, Sendable {
    /// The Claude Code CLI already installed and signed in on this Mac.
    case claudeCode
    /// Any hosted or self-hosted model endpoint.
    case remote
    /// On-device OCR, no setup at all.
    case vision

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code (lokal)"
        case .remote: "KI-Dienst (API)"
        case .vision: "Apple Vision (auf dem Gerät)"
        }
    }

    var summary: String {
        switch self {
        case .claudeCode:
            "Nutzt die Claude-Code-Installation auf diesem Mac und damit dein bestehendes Abo. "
            + "Kein API-Schlüssel nötig — einmalig „claude auth login“ im Terminal genügt."
        case .remote:
            "Beliebiger Anbieter mit Bild-Unterstützung: Anthropic, OpenAI, Gemini, OpenRouter, "
            + "oder ein lokaler Server wie Ollama. Wird pro Anfrage abgerechnet."
        case .vision:
            "Läuft offline und kostenlos. Erkennt Fließtext gut, Formeln nur als Zeichenkette — "
            + "Brüche, Exponenten und Matrizen gehen dabei verloren."
        }
    }

    /// Whether this engine produces real LaTeX rather than plain text.
    var understandsFormulas: Bool { self != .vision }
}

@MainActor
@Observable
final class RecognitionSettings {
    static let shared = RecognitionSettings()

    var engine: RecognitionEngine { didSet { defaults.set(engine.rawValue, forKey: Key.engine) } }
    var provider: ModelProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: Key.provider)
            // Each provider keeps its own endpoint, model and key, so switching
            // back and forth does not lose what you typed.
            baseURL = defaults.string(forKey: Key.baseURL(provider)) ?? provider.defaultBaseURL
            model = defaults.string(forKey: Key.model(provider)) ?? provider.defaultModel
        }
    }
    var baseURL: String { didSet { defaults.set(baseURL, forKey: Key.baseURL(provider)) } }
    var model: String { didSet { defaults.set(model, forKey: Key.model(provider)) } }
    /// Empty means "whatever Claude Code is configured to use".
    var claudeCodeModel: String { didSet { defaults.set(claudeCodeModel, forKey: Key.claudeModel) } }

    private let defaults = UserDefaults.standard

    private enum Key {
        static let engine = "MathPad.recognition.engine"
        static let provider = "MathPad.recognition.provider"
        static let claudeModel = "MathPad.recognition.claudeModel"
        static func baseURL(_ p: ModelProvider) -> String { "MathPad.recognition.baseURL.\(p.rawValue)" }
        static func model(_ p: ModelProvider) -> String { "MathPad.recognition.model.\(p.rawValue)" }
    }

    private init() {
        let storedProvider = ModelProvider(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .anthropic
        provider = storedProvider
        baseURL = defaults.string(forKey: Key.baseURL(storedProvider)) ?? storedProvider.defaultBaseURL
        model = defaults.string(forKey: Key.model(storedProvider)) ?? storedProvider.defaultModel
        claudeCodeModel = defaults.string(forKey: Key.claudeModel) ?? ""

        if let stored = defaults.string(forKey: Key.engine),
           let known = RecognitionEngine(rawValue: stored) {
            engine = known
        } else {
            // First run: prefer the path that costs nothing and needs no key.
            engine = ClaudeCodeLocator.path() != nil ? .claudeCode : .vision
        }
    }

    // MARK: API key

    var apiKey: String {
        get { Keychain.read(account: provider.keychainAccount) ?? "" }
        set { Keychain.write(newValue, account: provider.keychainAccount) }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    // MARK: Building the recognizer

    func makeRecognizer() -> any WorksheetRecognizer {
        switch engine {
        case .claudeCode:
            ClaudeCodeRecognizer(model: claudeCodeModel.isEmpty ? nil : claudeCodeModel)
        case .remote:
            RemoteModelRecognizer(provider: provider,
                                  baseURL: baseURL,
                                  model: model,
                                  apiKey: apiKey)
        case .vision:
            VisionRecognizer()
        }
    }

    /// Why the current choice cannot run, or `nil`.
    func unavailableReason() -> String? { makeRecognizer().unavailableReason() }
}
