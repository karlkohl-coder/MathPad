import Foundation

/// A cheap "does this actually work" check for the settings window: it proves the
/// endpoint, the key and the model name without sending a whole page.
@MainActor
enum ConnectionTest {

    static func run(_ settings: RecognitionSettings) async -> Result<String, Error> {
        switch settings.engine {
        case .vision:
            return .success("Apple Vision ist immer verfügbar — keine Einrichtung nötig.")

        case .claudeCode:
            ClaudeCodeLocator.refresh()
            guard let executable = ClaudeCodeLocator.path() else {
                return .failure(RecognitionError.notConfigured(
                    "Claude Code wurde nicht gefunden. Installation prüfen."))
            }
            do {
                var arguments = ["-p", "Antworte nur mit: OK", "--output-format", "json"]
                if !settings.claudeCodeModel.isEmpty {
                    arguments += ["--model", settings.claudeCodeModel]
                }
                let output = try await ProcessRunner.run(executable: executable,
                                                         arguments: arguments,
                                                         timeout: 60)
                if let data = output.data(using: .utf8),
                   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let text = root["result"] as? String ?? ""
                    if root["is_error"] as? Bool == true {
                        if text.lowercased().contains("authenticate") || text.lowercased().contains("oauth") {
                            return .failure(RecognitionError.notConfigured(
                                "Claude Code ist nicht angemeldet. Führe einmal „claude auth login“ im Terminal aus."))
                        }
                        return .failure(RecognitionError.badResponse(text))
                    }
                    return .success("Verbunden über \(executable). Antwort: \(text.prefix(40))")
                }
                return .failure(RecognitionError.badResponse(String(output.prefix(200))))
            } catch {
                return .failure(error)
            }

        case .remote:
            let recognizer = RemoteModelRecognizer(provider: settings.provider,
                                                   baseURL: settings.baseURL,
                                                   model: settings.model,
                                                   apiKey: settings.apiKey)
            if let reason = recognizer.unavailableReason() {
                return .failure(RecognitionError.notConfigured(reason))
            }
            do {
                let reply = try await recognizer.sendTextOnlyProbe()
                return .success("\(settings.provider.displayName) antwortet. Modell „\(settings.model)“ ist erreichbar. \(reply.prefix(40))")
            } catch {
                return .failure(error)
            }
        }
    }
}

extension RemoteModelRecognizer {
    /// Sends a two-word prompt with no image, purely to check endpoint and key.
    func sendTextOnlyProbe() async throws -> String {
        let base = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let probe = "Antworte nur mit: OK"

        var request: URLRequest
        var body: [String: Any]

        switch provider {
        case .anthropic:
            guard let url = URL(string: "\(base)/messages") else {
                throw RecognitionError.notConfigured("Ungültige Server-Adresse.")
            }
            request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": model, "max_tokens": 16,
                    "messages": [["role": "user", "content": probe]]]

        case .openAICompatible:
            guard let url = URL(string: "\(base)/chat/completions") else {
                throw RecognitionError.notConfigured("Ungültige Server-Adresse.")
            }
            request = URLRequest(url: url)
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            body = ["model": model, "max_tokens": 16,
                    "messages": [["role": "user", "content": probe]]]

        case .google:
            guard let url = URL(string: "\(base)/models/\(model):generateContent?key=\(apiKey)") else {
                throw RecognitionError.notConfigured("Ungültige Server-Adresse.")
            }
            request = URLRequest(url: url)
            body = ["contents": [["parts": [["text": probe]]]]]
        }

        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
            throw RecognitionError.transport(
                RemoteModelRecognizer.describeFailure(status: http.statusCode, body: data))
        }
        return String(data: data.prefix(80), encoding: .utf8) ?? ""
    }
}
