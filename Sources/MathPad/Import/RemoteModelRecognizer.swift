import Foundation

/// Which HTTP dialect a model endpoint speaks.
///
/// The OpenAI-compatible case is the important one: OpenRouter, Groq, Together,
/// Mistral, LM Studio and Ollama all serve it, so "another AI" is usually just a
/// different base URL and model name rather than new code.
enum ModelProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case anthropic
    case openAICompatible
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude API)"
        case .openAICompatible: "OpenAI-kompatibel (OpenAI, OpenRouter, Groq, Ollama …)"
        case .google: "Google (Gemini)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1"
        case .openAICompatible: "https://api.openai.com/v1"
        case .google: "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-5"
        case .openAICompatible: "gpt-4o"
        case .google: "gemini-2.5-pro"
        }
    }

    /// Where to get a key, shown next to the field.
    var keyHint: String {
        switch self {
        case .anthropic: "console.anthropic.com → API Keys"
        case .openAICompatible: "Beim jeweiligen Anbieter. Lokale Server (Ollama, LM Studio) brauchen meist keinen."
        case .google: "aistudio.google.com → API Key"
        }
    }

    var keychainAccount: String { "apikey.\(rawValue)" }
}

/// Sends the page to a hosted (or locally served) vision model.
struct RemoteModelRecognizer: WorksheetRecognizer {
    let provider: ModelProvider
    let baseURL: String
    let model: String
    let apiKey: String

    var id: String { "remote.\(provider.rawValue)" }
    var displayName: String { provider.displayName }

    func unavailableReason() -> String? {
        if model.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Es ist kein Modellname eingetragen."
        }
        if URL(string: baseURL) == nil {
            return "Die Server-Adresse ist ungültig."
        }
        // A local server legitimately needs no key; a hosted one does.
        if apiKey.isEmpty, provider != .openAICompatible {
            return "Es ist kein API-Schlüssel hinterlegt."
        }
        return nil
    }

    func recognize(_ image: WorksheetImage) async throws -> [Block] {
        if let reason = unavailableReason() { throw RecognitionError.notConfigured(reason) }
        let request = try makeRequest(for: image)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RecognitionError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RecognitionError.badResponse("keine HTTP-Antwort")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RecognitionError.transport(Self.describeFailure(status: http.statusCode, body: data))
        }
        let text = try extractText(from: data)
        return try RecognitionPrompt.blocks(fromModelOutput: text)
    }

    // MARK: Request

    private func makeRequest(for image: WorksheetImage) throws -> URLRequest {
        let base = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url: URL
        var body: [String: Any]
        var headers: [String: String] = ["Content-Type": "application/json"]

        switch provider {
        case .anthropic:
            guard let made = URL(string: "\(base)/messages") else {
                throw RecognitionError.notConfigured("Ungültige Server-Adresse.")
            }
            url = made
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
            body = [
                "model": model,
                "max_tokens": 8000,
                "messages": [[
                    "role": "user",
                    "content": [
                        ["type": "image",
                         "source": ["type": "base64", "media_type": "image/png", "data": image.base64]],
                        ["type": "text", "text": RecognitionPrompt.instruction],
                    ],
                ]],
            ]

        case .openAICompatible:
            guard let made = URL(string: "\(base)/chat/completions") else {
                throw RecognitionError.notConfigured("Ungültige Server-Adresse.")
            }
            url = made
            if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
            body = [
                "model": model,
                "max_tokens": 8000,
                "messages": [[
                    "role": "user",
                    "content": [
                        ["type": "text", "text": RecognitionPrompt.instruction],
                        ["type": "image_url",
                         "image_url": ["url": "data:image/png;base64,\(image.base64)"]],
                    ],
                ]],
            ]

        case .google:
            guard let made = URL(string: "\(base)/models/\(model):generateContent?key=\(apiKey)") else {
                throw RecognitionError.notConfigured("Ungültige Server-Adresse.")
            }
            url = made
            body = [
                "contents": [[
                    "parts": [
                        ["text": RecognitionPrompt.instruction],
                        ["inline_data": ["mime_type": "image/png", "data": image.base64]],
                    ],
                ]],
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: Response

    private func extractText(from data: Data) throws -> String {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let root = object else {
            throw RecognitionError.badResponse(String(data: data.prefix(200), encoding: .utf8) ?? "")
        }

        switch provider {
        case .anthropic:
            let parts = root["content"] as? [[String: Any]] ?? []
            let text = parts.compactMap { $0["text"] as? String }.joined()
            guard !text.isEmpty else { throw RecognitionError.badResponse("leere Antwort") }
            return text

        case .openAICompatible:
            let choices = root["choices"] as? [[String: Any]] ?? []
            guard let message = choices.first?["message"] as? [String: Any] else {
                throw RecognitionError.badResponse("keine choices in der Antwort")
            }
            // Some servers return a plain string, others the content-part array.
            if let text = message["content"] as? String { return text }
            if let parts = message["content"] as? [[String: Any]] {
                return parts.compactMap { $0["text"] as? String }.joined()
            }
            throw RecognitionError.badResponse("unbekanntes Antwortformat")

        case .google:
            let candidates = root["candidates"] as? [[String: Any]] ?? []
            guard let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                throw RecognitionError.badResponse("keine candidates in der Antwort")
            }
            return parts.compactMap { $0["text"] as? String }.joined()
        }
    }

    /// Turns an HTTP failure into something worth reading.
    static func describeFailure(status: Int, body: Data) -> String {
        var detail = ""
        if let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
                detail = message
            } else if let message = root["message"] as? String {
                detail = message
            }
        }
        if detail.isEmpty {
            detail = String(data: body.prefix(200), encoding: .utf8) ?? ""
        }
        let hint: String
        switch status {
        case 401, 403: hint = "Der API-Schlüssel wurde abgelehnt."
        case 404: hint = "Adresse oder Modellname stimmen nicht."
        case 429: hint = "Zu viele Anfragen oder Guthaben aufgebraucht."
        default: hint = "HTTP \(status)."
        }
        return detail.isEmpty ? hint : "\(hint) \(detail)"
    }
}
