import SwiftUI
import UniformTypeIdentifiers

/// The sheet itself, plus everything that floats above it.
struct EditorArea: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTarget = false
    @State private var isTablePickerOpen = false

    var body: some View {
        MathSheetView(controller: model.editor,
                      isDark: colorScheme == .dark,
                      fontSize: model.fontSize)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) { statusBar }
            .overlay { paletteLayer }
            .overlay { importLayer }
            .overlay { dropHighlight }
            .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
                handleDrop(providers)
            }
            .navigationTitle(model.store.selectedSheet?.displayTitle ?? "MathPad")
            .toolbar { toolbarContent }
            .onAppear { model.showSelectedSheet() }
            .onChange(of: model.store.selectedSheetID) { _, _ in model.showSelectedSheet() }
            .sheet(isPresented: Binding(get: { model.isCheatsheetOpen },
                                        set: { model.isCheatsheetOpen = $0 })) {
                CheatsheetView { model.isCheatsheetOpen = false }
            }
    }

    // MARK: Palette

    @ViewBuilder
    private var paletteLayer: some View {
        if model.isPaletteOpen {
            ZStack {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture { model.closePalette() }
                CommandPalette(
                    onInsert: { model.insert(symbol: $0) },
                    onClose: { model.closePalette() }
                )
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    // MARK: Import

    @ViewBuilder
    private var importLayer: some View {
        if model.importer.phase != .idle {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                ImportPanel()
            }
            .transition(.opacity)
        }
    }

    /// Visible edge while a file hovers over the sheet.
    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .padding(8)
                .allowsHitTesting(false)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            let type = UTType(filenameExtension: url.pathExtension)
            guard let type, WorksheetImageLoader.supportedTypes.contains(where: { type.conforms(to: $0) })
            else { return }
            Task { @MainActor in model.importWorksheet(from: url) }
        }
        return true
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            keyHint("/", "Bruch")
            keyHint("^", "hoch")
            keyHint("_", "tief")
            keyHint("⌘K", "Symbole")
            keyHint("↩", "neue Zeile")
            Spacer()
            Button {
                model.isCheatsheetOpen = true
            } label: {
                Label("Alle Kürzel", systemImage: "keyboard")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
    }

    /// Menu row: a colour dot plus its name. A highlighter swatch is drawn as an
    /// outlined chip so it reads as a background rather than as ink.
    private func swatchLabel(_ choice: ColorChoice, filled: Bool) -> some View {
        Label {
            Text(choice.name)
        } icon: {
            Image(nsImage: choice.swatch(filled: filled))
        }
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            // In a table the line-kind menu has nothing to switch to, so the
            // same spot offers what does make sense there.
            if model.editor.focusedKind == .table {
                Menu {
                    TableMenuItems(editor: model.editor)
                } label: {
                    Label("Tabelle", systemImage: "tablecells")
                        .labelStyle(.titleAndIcon)
                }
                .frame(width: 140)
                .help("Zeilen, Spalten, Ausrichtung und Linien dieser Tabelle")
            } else {
                Picker("Zeilentyp", selection: Binding(
                    get: { model.editor.focusedKind ?? .math },
                    set: { model.setBlockKind($0) }
                )) {
                    ForEach(BlockKind.selectable, id: \.rawValue) { kind in
                        Text(kind.germanName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .help("Zeilentyp dieser Zeile")
            }

            Button {
                isTablePickerOpen.toggle()
            } label: {
                Image(systemName: "tablecells.badge.ellipsis")
            }
            .help("Tabelle einfügen (⇧⌘T)")
            .popover(isPresented: $isTablePickerOpen, arrowEdge: .bottom) {
                TableSizePicker { rows, columns in
                    isTablePickerOpen = false
                    model.insertTable(rows: rows, columns: columns)
                }
            }

            Button {
                model.editor.toggleSource()
            } label: {
                Image(systemName: model.editor.focusedShowsSource ? "chevron.left.forwardslash.chevron.right" : "curlybraces")
            }
            .help("LaTeX-Quelltext dieser Zeile zeigen (⌥⌘L)")

            ForEach(TextFormat.allCases) { format in
                Button {
                    model.editor.apply(format)
                } label: {
                    Image(systemName: format.systemImage)
                }
                .help("\(format.germanName) (⌘\(format.shortcut.character.uppercased()))")
            }

            Menu {
                Section("Schriftfarbe") {
                    ForEach(ColorPalette.ink) { choice in
                        Button { model.editor.setInkColor(choice.hex) } label: {
                            swatchLabel(choice, filled: true)
                        }
                    }
                }
                Section("Textmarker") {
                    ForEach(ColorPalette.highlight) { choice in
                        Button { model.editor.setHighlight(choice.hex) } label: {
                            swatchLabel(choice, filled: false)
                        }
                    }
                }
                Divider()
                Button("Formatierung entfernen") { model.editor.clearFormatting() }
            } label: {
                Image(systemName: "paintpalette")
            }
            .help("Schriftfarbe und Textmarker")

            Button {
                model.openPalette()
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            .help("Symbolpalette (⌘K)")

            Button {
                model.importWorksheet()
            } label: {
                Image(systemName: "doc.viewfinder")
            }
            .help("Arbeitsblatt einlesen (⇧⌘I)")

            Menu {
                Button("Formel als LaTeX kopieren") { model.copyFocusedLaTeX() }
                Button("Formel als MathML kopieren") { model.copyFocusedMathML() }
                Divider()
                Button("Blatt als LaTeX kopieren") { model.copySheetLaTeX() }
                Button("Blatt als Markdown kopieren") { model.copySheetMarkdown() }
                Divider()
                Button("Blatt als PDF sichern …") { model.exportPDF() }
                Button("Blatt als .tex sichern …") { model.exportLaTeXFile() }
                Button("Blatt als .md sichern …") { model.exportMarkdownFile() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Kopieren & Exportieren")
        }
    }
}
