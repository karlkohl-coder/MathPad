import AppKit
import Observation

/// Drives one import: file → page image → recognizer → blocks.
///
/// It deliberately stops before touching a sheet. Where the result goes is the
/// user's call, and `AppModel` makes it once the choice dialog comes back.
@MainActor
@Observable
final class WorksheetImporter {

    enum Phase: Equatable {
        case idle
        /// Something is running; the string is what to show the user.
        case working(String)
        /// Recognition finished, waiting for "new sheet or insert here".
        case choosing
        case failed(String)
    }

    enum Destination {
        case newSheet
        case insertAtCursor
    }

    private(set) var phase: Phase = .idle
    private(set) var blocks: [Block] = []
    private(set) var sourceName = ""
    private(set) var skippedPages = 0
    private(set) var engineName = ""
    private(set) var usedFormulaAwareEngine = true

    private var task: Task<Void, Never>?

    var isBusy: Bool { if case .working = phase { true } else { false } }

    // MARK: Starting

    /// Shows the open panel, then imports what was chosen.
    func pickAndStart() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = WorksheetImageLoader.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Arbeitsblatt als PDF (erste Seite) oder Bild wählen"
        panel.prompt = "Einlesen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        start(url: url)
    }

    func start(url: URL) {
        task?.cancel()
        let settings = RecognitionSettings.shared
        let recognizer = settings.makeRecognizer()
        engineName = settings.engine.displayName
        usedFormulaAwareEngine = settings.engine.understandsFormulas

        if let reason = recognizer.unavailableReason() {
            phase = .failed(reason)
            return
        }

        phase = .working("Seite wird vorbereitet …")
        blocks = []
        sourceName = url.deletingPathExtension().lastPathComponent
        skippedPages = 0

        task = Task { [weak self] in
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    try WorksheetImageLoader.load(from: url)
                }.value
                guard !Task.isCancelled else { return }

                self?.skippedPages = image.skippedPages
                self?.sourceName = image.sourceName
                self?.phase = .working("Wird gelesen – das dauert meist 10 bis 40 Sekunden …")

                let found = try await recognizer.recognize(image)
                guard !Task.isCancelled else { return }

                self?.blocks = found
                self?.phase = .choosing
            } catch is CancellationError {
                self?.phase = .idle
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func reset() {
        task = nil
        blocks = []
        phase = .idle
    }

    // MARK: Summary for the UI

    var summary: String {
        let count = blocks.count
        var parts = ["\(count) \(count == 1 ? "Zeile" : "Zeilen") erkannt"]
        let formulas = blocks.filter { $0.kind.isLaTeX }.count
        if formulas > 0 { parts.append("davon \(formulas) mit Formel") }
        return parts.joined(separator: ", ")
    }
}
