import Foundation

/// Recognition through the Claude Code CLI that is already installed and signed
/// in on this Mac.
///
/// This is the one path that needs no API key and no extra billing: it runs
/// under the same login (and the same usage limits) as Claude Code itself.
struct ClaudeCodeRecognizer: WorksheetRecognizer {
    let id = "claude-code"
    let displayName = "Claude Code (lokal installiert)"

    var model: String?

    func unavailableReason() -> String? {
        ClaudeCodeLocator.path() == nil
            ? "Claude Code wurde nicht gefunden. Installiere es und melde dich einmal mit „claude auth login“ an."
            : nil
    }

    func recognize(_ image: WorksheetImage) async throws -> [Block] {
        guard let executable = ClaudeCodeLocator.path() else {
            throw RecognitionError.notConfigured(unavailableReason() ?? "Claude Code fehlt.")
        }

        // The CLI reads the picture from disk with its Read tool.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathPad-Import", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(UUID().uuidString).png")
        try image.pngData.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let prompt = """
        \(RecognitionPrompt.instruction)

        Das Bild liegt unter diesem Pfad — lies es mit dem Read-Tool:
        \(file.path)
        """

        var arguments = ["-p", prompt,
                         "--output-format", "json",
                         "--allowedTools", "Read"]
        if let model, !model.isEmpty { arguments += ["--model", model] }

        let output = try await ProcessRunner.run(executable: executable,
                                                 arguments: arguments,
                                                 timeout: 240)
        return try Self.parse(cliOutput: output)
    }

    private struct CLIResult: Decodable {
        let result: String?
        let is_error: Bool?
        let subtype: String?
    }

    static func parse(cliOutput: String) throws -> [Block] {
        guard let data = cliOutput.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(CLIResult.self, from: data) else {
            throw RecognitionError.badResponse(String(cliOutput.prefix(200)))
        }
        let text = envelope.result ?? ""
        if envelope.is_error == true {
            if text.lowercased().contains("authenticate") || text.lowercased().contains("oauth") {
                throw RecognitionError.notConfigured(
                    "Claude Code ist nicht angemeldet. Führe einmal „claude auth login“ im Terminal aus."
                )
            }
            throw RecognitionError.badResponse(text.isEmpty ? "Unbekannter Fehler" : text)
        }
        return try RecognitionPrompt.blocks(fromModelOutput: text)
    }
}

/// Finds the `claude` binary. A GUI app inherits a bare PATH, so the usual
/// install locations are checked directly before falling back to a login shell.
enum ClaudeCodeLocator {
    private static var cached: String??

    static func path() -> String? {
        if let cached { return cached }
        let found = locate()
        cached = found
        return found
    }

    /// Forget the cached answer — used after the user installs or logs in.
    static func refresh() { cached = nil }

    private static func locate() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        // Last resort: ask a login shell, which sources the user's profile.
        guard let output = try? ProcessRunner.runSync(executable: "/bin/zsh",
                                                      arguments: ["-lc", "command -v claude"],
                                                      timeout: 8) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: trimmed) ? trimmed : nil
    }
}
