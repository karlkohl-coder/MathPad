import AppKit
import Observation
import SwiftUI

/// The one object the UI and the menu bar both talk to.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let store = SheetStore()
    let editor = EditorController()
    let importer = WorksheetImporter()

    var isPaletteOpen = false
    var isCheatsheetOpen = false

    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey) }
    }

    private static let fontSizeKey = "MathPad.fontSize"

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = stored > 0 ? stored : 21

        editor.onChange = { [weak self] sheetID, blocks in
            guard let self, var sheet = self.store.sheets.first(where: { $0.id == sheetID }) else { return }
            sheet.blocks = blocks
            self.store.update(sheet)
        }
        editor.onEscape = { [weak self] in
            self?.closePalette()
        }
        editor.onRequestPalette = { [weak self] in
            self?.openPalette()
        }
    }

    // MARK: Sheets

    func showSelectedSheet() {
        guard let sheet = store.selectedSheet else { return }
        editor.show(sheet)
    }

    func newSheet(in group: String? = nil) {
        store.newSheet(in: group)
        showSelectedSheet()
        editor.focusEditor()
    }

    /// Makes a group and puts the current sheet in it, so the command does
    /// something visible rather than creating an empty section.
    func newGroup() {
        let name = store.createGroup(named: store.uniqueGroupName())
        if let id = store.selectedSheetID { store.move(id, toGroup: name) }
    }

    func duplicateSheet() {
        guard let id = store.selectedSheetID else { return }
        store.duplicate(id)
        showSelectedSheet()
    }

    func deleteSheet() {
        guard let id = store.selectedSheetID else { return }
        store.delete(id)
        showSelectedSheet()
    }

    // MARK: Import

    /// Read a worksheet from a PDF page or a picture.
    func importWorksheet() {
        guard !importer.isBusy else { return }
        importer.pickAndStart()
    }

    /// Same, for a file dropped onto the sheet.
    func importWorksheet(from url: URL) {
        guard !importer.isBusy else { return }
        importer.start(url: url)
    }

    /// Called once the user has picked where the recognised lines should land.
    func applyImport(_ destination: WorksheetImporter.Destination) {
        let blocks = importer.blocks
        guard !blocks.isEmpty else { return importer.reset() }

        switch destination {
        case .newSheet:
            store.newSheet(in: store.selectedSheet?.group,
                           blocks: blocks,
                           title: importer.sourceName)
            showSelectedSheet()
        case .insertAtCursor:
            editor.insert(blocks: blocks)
        }
        importer.reset()
        editor.focusEditor()
    }

    // MARK: Palette

    func openPalette() {
        withAnimation(.easeOut(duration: 0.12)) { isPaletteOpen = true }
    }

    func closePalette() {
        guard isPaletteOpen else { return }
        withAnimation(.easeOut(duration: 0.10)) { isPaletteOpen = false }
        editor.focusEditor()
    }

    func insert(symbol: MathSymbol) {
        editor.insert(latex: symbol.latex)
        closePalette()
    }

    // MARK: Blocks

    func setBlockKind(_ kind: BlockKind) { editor.setKind(kind) }
    func newBlock(_ kind: BlockKind) { editor.newBlock(kind) }

    func insertTable(rows: Int = 3, columns: Int = 3) {
        editor.insertTable(rows: rows, columns: columns)
        editor.focusEditor()
    }

    // MARK: Zoom

    func zoomIn() { fontSize = min(fontSize + 2, 44) }
    func zoomOut() { fontSize = max(fontSize - 2, 13) }
    func zoomReset() { fontSize = 21 }

    // MARK: Copy & export

    func copyFocusedLaTeX() {
        Task { Exporter.copyToClipboard(await editor.focusedLatex()) }
    }

    func copyFocusedMathML() {
        Task { Exporter.copyToClipboard(await editor.focusedMathML()) }
    }

    func copyFocusedASCII() {
        Task { Exporter.copyToClipboard(await editor.focusedASCIIMath()) }
    }

    func copySheetLaTeX() {
        guard let sheet = store.selectedSheet else { return }
        Exporter.copyToClipboard(sheet.asLaTeX())
    }

    func copySheetMarkdown() {
        guard let sheet = store.selectedSheet else { return }
        Exporter.copyToClipboard(sheet.asMarkdown())
    }

    func exportLaTeXFile() {
        guard let sheet = store.selectedSheet else { return }
        Exporter.saveText(sheet.asLaTeX(),
                          suggestedName: Exporter.fileName(for: sheet, extension: "tex"),
                          type: .plainText)
    }

    func exportMarkdownFile() {
        guard let sheet = store.selectedSheet else { return }
        Exporter.saveText(sheet.asMarkdown(),
                          suggestedName: Exporter.fileName(for: sheet, extension: "md"),
                          type: .plainText)
    }

    func exportPDF() {
        guard let sheet = store.selectedSheet else { return }
        Task {
            let blocks = await editor.currentBlocks() ?? sheet.blocks
            await Exporter.savePDF(blocks: blocks,
                                   suggestedName: Exporter.fileName(for: sheet, extension: "pdf"))
        }
    }
}
