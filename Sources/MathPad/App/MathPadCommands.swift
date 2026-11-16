import SwiftUI

/// The menu bar. Every shortcut in the app is listed here, so the menus double
/// as documentation.
struct MathPadCommands: Commands {
    let model: AppModel

    var body: some Commands {
        // Replace the stock "New window" item.
        CommandGroup(replacing: .newItem) {
            Button("Neues Blatt") { model.newSheet() }
                .keyboardShortcut("n")
            Button("Neue Gruppe") { model.newGroup() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Blatt duplizieren") { model.duplicateSheet() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button("Arbeitsblatt einlesen …") { model.importWorksheet() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("Blatt löschen") { model.deleteSheet() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Menu("Exportieren") {
                Button("Als PDF sichern …") { model.exportPDF() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Als LaTeX sichern …") { model.exportLaTeXFile() }
                Button("Als Markdown sichern …") { model.exportMarkdownFile() }
            }
        }

        // The stock items act on whichever text field has focus; the sheet needs
        // one history that also covers deleting a line or changing its kind.
        CommandGroup(replacing: .undoRedo) {
            Button("Widerrufen") { model.editor.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("Wiederholen") { model.editor.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Formel als LaTeX kopieren") { model.copyFocusedLaTeX() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Formel als MathML kopieren") { model.copyFocusedMathML() }
                .keyboardShortcut("c", modifiers: [.command, .shift, .option])
            Button("Formel als Text kopieren") { model.copyFocusedASCII() }
            Divider()
            Button("Blatt als LaTeX kopieren") { model.copySheetLaTeX() }
            Button("Blatt als Markdown kopieren") { model.copySheetMarkdown() }
        }

        CommandMenu("Format") {
            ForEach(TextFormat.allCases) { format in
                Button(format.germanName) { model.editor.apply(format) }
                    .keyboardShortcut(format.shortcut, modifiers: .command)
            }

            Divider()

            Menu("Schriftfarbe") {
                ForEach(ColorPalette.ink) { choice in
                    Button {
                        model.editor.setInkColor(choice.hex)
                    } label: {
                        Label { Text(choice.name) } icon: {
                            Image(nsImage: choice.swatch(filled: true))
                        }
                    }
                }
            }
            Menu("Textmarker") {
                ForEach(ColorPalette.highlight) { choice in
                    Button {
                        model.editor.setHighlight(choice.hex)
                    } label: {
                        Label { Text(choice.name) } icon: {
                            Image(nsImage: choice.swatch(filled: false))
                        }
                    }
                }
            }

            Divider()

            Button("Formatierung entfernen") { model.editor.clearFormatting() }
        }

        CommandMenu("Formel") {
            Button("Symbol einfügen …") { model.openPalette() }
                .keyboardShortcut("k")
            Button("LaTeX-Quelltext dieser Zeile") { model.editor.toggleSource() }
                .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            ForEach(Array(BlockKind.selectable.enumerated()), id: \.element.rawValue) { index, kind in
                Button("Zeile: \(kind.germanName)") { model.setBlockKind(kind) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                      modifiers: [.command, .option])
            }

            Divider()

            Button("Neue Textzeile") { model.newBlock(.paragraph) }
                .keyboardShortcut(.return, modifiers: [.command])
            Button("Zeile duplizieren") { model.editor.duplicateBlock() }
                .keyboardShortcut("d", modifiers: [.command])
            Button("Zeile löschen") { model.editor.deleteBlock() }
                .keyboardShortcut(.delete, modifiers: [.command])

            Divider()

            Button("Zeile nach oben") { model.editor.moveBlockUp() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .control])
            Button("Zeile nach unten") { model.editor.moveBlockDown() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .control])
        }

        CommandMenu("Tabelle") {
            Button("Tabelle einfügen") { model.insertTable() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            TableMenuItems(editor: model.editor)
                .disabled(model.editor.focusedKind != .table)
        }

        CommandGroup(after: .toolbar) {
            Button("Größer") { model.zoomIn() }
                .keyboardShortcut("+", modifiers: [.command])
            Button("Kleiner") { model.zoomOut() }
                .keyboardShortcut("-", modifiers: [.command])
            Button("Originalgröße") { model.zoomReset() }
                .keyboardShortcut("0", modifiers: [.command])
        }

        CommandGroup(replacing: .help) {
            Button("Tastatur-Spickzettel") { model.isCheatsheetOpen = true }
                .keyboardShortcut("/", modifiers: [.command])
        }
    }
}
