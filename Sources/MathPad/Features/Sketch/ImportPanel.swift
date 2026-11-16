import SwiftUI

/// The card that appears while a worksheet is being read, and afterwards to ask
/// where the recognised lines should go.
struct ImportPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    private var importer: WorksheetImporter { model.importer }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch importer.phase {
            case .working(let status): working(status)
            case .choosing: choosing
            case .failed(let message): failed(message)
            case .idle: EmptyView()
            }
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.28), radius: 34, y: 14)
    }

    // MARK: Running

    private func working(_ status: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Arbeitsblatt wird eingelesen", systemImage: "doc.viewfinder")

            HStack(spacing: 11) {
                ProgressView().controlSize(.small)
                Text(status).font(.system(size: 13))
                Spacer()
            }

            Text("Erkennung über \(importer.engineName)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Abbrechen") { importer.cancel() }
            }
        }
        .padding(20)
    }

    // MARK: Result

    private var choosing: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("„\(importer.sourceName)" + "“ gelesen", systemImage: "checkmark.circle")

            Text(importer.summary)
                .font(.system(size: 13, weight: .medium))

            preview

            if importer.skippedPages > 0 {
                note("Die Datei hat \(importer.skippedPages + 1) Seiten — es wurde nur die erste eingelesen.",
                     systemImage: "doc.on.doc")
            }
            if !importer.usedFormulaAwareEngine {
                note("Apple Vision liefert reinen Text: Brüche, Exponenten und Matrizen sind verloren gegangen. "
                     + "Für echte Formeln in den Einstellungen eine andere Erkennung wählen.",
                     systemImage: "exclamationmark.triangle")
            }

            HStack(spacing: 10) {
                Button("Verwerfen", role: .cancel) { importer.reset() }
                Spacer()
                Button("Hier einfügen") { model.applyImport(.insertAtCursor) }
                Button("Als neues Blatt") { model.applyImport(.newSheet) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(importer.blocks.prefix(6)) { block in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(block.kind.germanName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)
                    Text(block.kind == .table ? block.plainPreview : block.value)
                        .font(.system(size: 11, design: block.kind == .heading || block.kind == .paragraph ? .default : .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
            if importer.blocks.count > 6 {
                Text("… und \(importer.blocks.count - 6) weitere")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 82)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Failure

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Einlesen fehlgeschlagen", systemImage: "exclamationmark.triangle")

            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Spacer()
                Button("Einstellungen …") {
                    importer.reset()
                    openSettings()
                }
                Button("Schließen") { importer.reset() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    // MARK: Bits

    private func header(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 15, weight: .semibold))
    }

    private func note(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
