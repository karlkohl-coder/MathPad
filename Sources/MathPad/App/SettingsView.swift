import SwiftUI

/// ⌘, — picks how a worksheet gets read, and where the key for that lives.
struct SettingsView: View {
    @State private var settings = RecognitionSettings.shared
    @State private var key = ""
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle
        case running
        case ok(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section("Arbeitsblatt einlesen") {
                Picker("Erkennung", selection: Binding(
                    get: { settings.engine },
                    set: { settings.engine = $0; testState = .idle }
                )) {
                    ForEach(RecognitionEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(settings.engine.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch settings.engine {
            case .claudeCode: claudeCodeSection
            case .remote: remoteSection
            case .vision: EmptyView()
            }

            Section {
                HStack(spacing: 10) {
                    Button("Verbindung testen") { runTest() }
                        .disabled(testState == .running)
                    if testState == .running { ProgressView().controlSize(.small) }
                    Spacer()
                }
                switch testState {
                case .ok(let message):
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                default:
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { key = settings.apiKey }
    }

    // MARK: Claude Code

    @ViewBuilder
    private var claudeCodeSection: some View {
        Section("Claude Code") {
            if let path = ClaudeCodeLocator.path() {
                LabeledContent("Gefunden unter") {
                    Text(path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            } else {
                Label("Claude Code wurde auf diesem Mac nicht gefunden.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            TextField("Modell (leer = Voreinstellung von Claude Code)",
                      text: Binding(get: { settings.claudeCodeModel },
                                    set: { settings.claudeCodeModel = $0 }))

            Text("Läuft über deine bestehende Claude-Code-Anmeldung, also ohne API-Schlüssel und "
                 + "ohne Zusatzkosten; es zählt auf dein normales Nutzungskontingent. "
                 + "Falls der Test „nicht angemeldet“ meldet, im Terminal einmal „claude auth login“ ausführen.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Remote

    @ViewBuilder
    private var remoteSection: some View {
        Section("Anbieter") {
            Picker("Dienst", selection: Binding(
                get: { settings.provider },
                set: { settings.provider = $0; key = settings.apiKey; testState = .idle }
            )) {
                ForEach(ModelProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            TextField("Server-Adresse", text: Binding(
                get: { settings.baseURL }, set: { settings.baseURL = $0 }
            ))
            .font(.system(size: 12, design: .monospaced))

            TextField("Modell", text: Binding(
                get: { settings.model }, set: { settings.model = $0 }
            ))
            .font(.system(size: 12, design: .monospaced))

            SecureField("API-Schlüssel", text: $key)
                .onSubmit { settings.apiKey = key }

            HStack {
                Button("Schlüssel sichern") { settings.apiKey = key }
                    .disabled(key == settings.apiKey)
                Button("Löschen") { key = ""; settings.apiKey = "" }
                    .disabled(key.isEmpty && !settings.hasAPIKey)
                Spacer()
            }

            Text("Schlüssel holen: \(settings.provider.keyHint)\n"
                 + "Der Schlüssel liegt im macOS-Schlüsselbund, nicht in den Einstellungen der App.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.provider == .openAICompatible {
                Text("Für einen lokalen Server: Adresse z. B. http://localhost:11434/v1 (Ollama) "
                     + "oder http://localhost:1234/v1 (LM Studio), Schlüssel bleibt leer. "
                     + "Das Modell muss Bilder verstehen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Test

    private func runTest() {
        settings.apiKey = key
        testState = .running
        Task {
            switch await ConnectionTest.run(settings) {
            case .success(let message): testState = .ok(message)
            case .failure(let error): testState = .failed(error.localizedDescription)
            }
        }
    }
}
