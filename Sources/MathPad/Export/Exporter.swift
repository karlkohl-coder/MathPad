import AppKit
import UniformTypeIdentifiers
import WebKit

/// Everything that leaves the app: clipboard and files.
@MainActor
enum Exporter {

    static func copyToClipboard(_ string: String) {
        guard !string.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Ask for a location and write UTF-8 text.
    static func saveText(_ text: String, suggestedName: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// The sheet on A4 pages, set for paper rather than copied from the screen
    /// (see `PDFRenderer`).
    static func savePDF(blocks: [Block], suggestedName: String) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try await PDFRenderer.render(blocks: blocks)
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "PDF konnte nicht erstellt werden"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// A file name that is safe on disk.
    static func fileName(for sheet: Sheet, extension ext: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let base = sheet.displayTitle
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (base.isEmpty ? "Blatt" : base) + "." + ext
    }
}
