import SwiftUI

/// Table commands as SwiftUI menu items — shared by the menu bar and the
/// toolbar, so both always offer the same thing.
struct TableMenuItems: View {
    let editor: EditorController

    var body: some View {
        let table = editor.focusedTable
        ForEach(Array(TableAction.menuGroups.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group) { action in
                if action == .toggleHeader {
                    Toggle(action.germanName, isOn: Binding(
                        get: { table?.header ?? false },
                        set: { _ in editor.table(.toggleHeader) }
                    ))
                } else {
                    Button(action.germanName) { editor.table(action) }
                        .disabled(!action.isEnabled(in: table))
                }
            }
        }
        Divider()
        Picker("Spalte ausrichten", selection: Binding(
            get: { table?.alignment ?? .left },
            set: { editor.setTableAlignment($0) }
        )) {
            ForEach(TableData.Alignment.allCases) { alignment in
                Label(alignment.germanName, systemImage: alignment.systemImage).tag(alignment)
            }
        }
        .disabled(table == nil)
        Picker("Linien", selection: Binding(
            get: { table?.style ?? .grid },
            set: { editor.setTableLines($0) }
        )) {
            ForEach(TableData.LineStyle.allCases) { style in
                Text(style.germanName).tag(style)
            }
        }
        .disabled(table == nil)
    }
}

/// Word-style size picker: move over the grid, click to insert.
struct TableSizePicker: View {
    let onPick: (_ rows: Int, _ columns: Int) -> Void

    @State private var hover = (rows: 3, columns: 3)
    private let maxRows = 8
    private let maxColumns = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tabelle einfügen")
                .font(.system(size: 12, weight: .semibold))

            VStack(spacing: 3) {
                ForEach(0..<maxRows, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<maxColumns, id: \.self) { column in
                            let inside = row < hover.rows && column < hover.columns
                            RoundedRectangle(cornerRadius: 3)
                                .fill(inside ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(inside ? Color.accentColor : Color.primary.opacity(0.15))
                                )
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                                .onHover { if $0 { hover = (row + 1, column + 1) } }
                                .onTapGesture { onPick(row + 1, column + 1) }
                        }
                    }
                }
            }

            HStack {
                Text("\(hover.rows) Zeilen × \(hover.columns) Spalten")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            Text("Größer? Mit ⇥ in der letzten Zelle oder den + Knöpfen wächst sie weiter.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 214)
    }
}
