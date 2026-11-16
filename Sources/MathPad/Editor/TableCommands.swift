import Foundation

/// Where the caret sits in a table, as the editor reports it.
struct TableFocus: Equatable {
    var row: Int
    var column: Int
    var rows: Int
    var columns: Int
    var header: Bool
    var style: TableData.LineStyle
    var alignment: TableData.Alignment

    /// Reads the `table` object of a focus or context-menu message.
    init?(_ payload: Any?) {
        guard let dict = payload as? [String: Any],
              let rows = dict["rows"] as? Int,
              let columns = dict["columns"] as? Int else { return nil }
        self.row = dict["row"] as? Int ?? 0
        self.column = dict["column"] as? Int ?? 0
        self.rows = rows
        self.columns = columns
        self.header = dict["header"] as? Bool ?? false
        self.style = TableData.LineStyle(rawValue: dict["style"] as? String ?? "") ?? .grid
        self.alignment = TableData.Alignment(rawValue: dict["align"] as? String ?? "") ?? .left
    }
}

/// Structural table edits. The raw values are the action names `MP.table`
/// understands in editor.js.
enum TableAction: String, CaseIterable, Identifiable {
    case rowAbove, rowBelow, columnLeft, columnRight
    case deleteRow, deleteColumn
    case toggleHeader, resetWidths
    case deleteTable

    var id: String { rawValue }

    var germanName: String {
        switch self {
        case .rowAbove: "Zeile oberhalb einfügen"
        case .rowBelow: "Zeile unterhalb einfügen"
        case .columnLeft: "Spalte links einfügen"
        case .columnRight: "Spalte rechts einfügen"
        case .deleteRow: "Zeile löschen"
        case .deleteColumn: "Spalte löschen"
        case .toggleHeader: "Kopfzeile"
        case .resetWidths: "Spaltenbreiten zurücksetzen"
        case .deleteTable: "Tabelle löschen"
        }
    }

    /// Menu order, in separated groups.
    static let menuGroups: [[TableAction]] = [
        [.rowAbove, .rowBelow, .columnLeft, .columnRight],
        [.deleteRow, .deleteColumn, .deleteTable],
        [.toggleHeader, .resetWidths],
    ]

    /// Removing the last row or column would remove the whole table; that has
    /// its own item, so the narrower one is switched off rather than surprising.
    func isEnabled(in table: TableFocus?) -> Bool {
        guard let table else { return false }
        switch self {
        case .deleteRow: return table.rows > 1
        case .deleteColumn: return table.columns > 1
        default: return true
        }
    }
}
