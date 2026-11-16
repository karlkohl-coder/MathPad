import Foundation

/// The contents of a table line.
///
/// A table is stored in `Block.value` like every other line, as JSON, so the
/// sheet file keeps one shape for all kinds. Each cell holds the same LaTeX a
/// "Text + Formel" line holds: prose in `\text{…}`, everything else maths.
struct TableData: Codable, Hashable, Sendable {
    enum Alignment: String, Codable, CaseIterable, Identifiable, Sendable {
        case left, center, right

        var id: String { rawValue }

        var germanName: String {
            switch self {
            case .left: "Links"
            case .center: "Zentriert"
            case .right: "Rechts"
            }
        }

        var systemImage: String {
            switch self {
            case .left: "text.alignleft"
            case .center: "text.aligncenter"
            case .right: "text.alignright"
            }
        }
    }

    enum LineStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Every cell boxed.
        case grid
        /// Rules between rows only, the way tables look in a book.
        case lines
        /// No rules, except under a header row.
        case none

        var id: String { rawValue }

        var germanName: String {
            switch self {
            case .grid: "Gitter"
            case .lines: "Nur waagerechte Linien"
            case .none: "Ohne Linien"
            }
        }
    }

    var rows: [[String]]
    /// Whether the first row is a header.
    var header: Bool
    var style: LineStyle
    /// One entry per column.
    var align: [Alignment]
    /// Column widths in em, `nil` = sized to the content. One entry per column.
    var widths: [Double?]

    init(rows: [[String]], header: Bool = true, style: LineStyle = .grid) {
        let columns = max(1, rows.map(\.count).max() ?? 1)
        self.rows = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
        if self.rows.isEmpty { self.rows = [Array(repeating: "", count: columns)] }
        self.header = header
        self.style = style
        self.align = Array(repeating: .left, count: columns)
        self.widths = Array(repeating: nil, count: columns)
    }

    /// Lenient for the same reason as `Sheet`: the editor pads ragged rows and
    /// fills in anything missing, so the Swift side must not be stricter.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decodeIfPresent([[String]].self, forKey: .rows)) ?? nil
        self.init(rows: raw ?? [["", ""], ["", ""]],
                  header: (try? container.decodeIfPresent(Bool.self, forKey: .header)) ?? false,
                  style: (try? container.decodeIfPresent(LineStyle.self, forKey: .style)) ?? .grid)
        let columns = self.columns
        if let stored = try? container.decodeIfPresent([String].self, forKey: .align) {
            align = (0..<columns).map { index in
                index < stored.count ? Alignment(rawValue: stored[index]) ?? .left : .left
            }
        }
        if let stored = try? container.decodeIfPresent([Double?].self, forKey: .widths) {
            widths = (0..<columns).map { index in
                index < stored.count ? stored[index].flatMap { $0 > 0 ? $0 : nil } : nil
            }
        }
    }

    /// A value that cannot be read becomes an empty 2 × 2 table, which is also
    /// what the editor shows for it.
    init(value: String) {
        if let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(TableData.self, from: data) {
            self = decoded
        } else {
            self.init(rows: [["", ""], ["", ""]], header: false)
        }
    }

    var columns: Int { rows.first?.count ?? 0 }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    var isEmpty: Bool {
        rows.allSatisfy { row in
            row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    // MARK: Export

    /// A `tabular`. Cells go in as inline maths, which is how a mixed line
    /// exports too — the prose in them already sits in `\text{}`.
    func asLaTeX() -> String {
        let spec: String = align.map { alignment in
            switch alignment {
            case .left: "l"
            case .center: "c"
            case .right: "r"
            }
        }.joined(separator: style == .grid ? "|" : "")

        var lines: [String] = []
        lines.append("\\begin{tabular}{\(style == .grid ? "|\(spec)|" : spec)}")
        if style != .none { lines.append("\\hline") }
        for (index, row) in rows.enumerated() {
            let cells = row.map { cell in
                let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "" : "$\(trimmed)$"
            }
            lines.append(cells.joined(separator: " & ") + " \\\\")
            let isLast = index == rows.count - 1
            let underHeader = header && index == 0
            switch style {
            case .grid, .lines: lines.append("\\hline")
            case .none: if underHeader && !isLast { lines.append("\\hline") }
            }
        }
        lines.append("\\end{tabular}")
        return lines.joined(separator: "\n")
    }

    /// A pipe table. Markdown insists on a header row, so a table without one
    /// gets an empty header rather than having its first line promoted.
    func asMarkdown() -> String {
        func line(_ cells: [String]) -> String {
            "| " + cells.map { cell in
                let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                // A pipe inside a cell would end the cell early.
                return trimmed.isEmpty ? "" : "$\(trimmed.replacingOccurrences(of: "|", with: "\\vert "))$"
            }.joined(separator: " | ") + " |"
        }
        let separator = "| " + align.map { alignment in
            switch alignment {
            case .left: "---"
            case .center: ":---:"
            case .right: "---:"
            }
        }.joined(separator: " | ") + " |"

        var body = rows
        let head = header && !body.isEmpty ? body.removeFirst() : Array(repeating: "", count: columns)
        return ([line(head), separator] + body.map(line)).joined(separator: "\n")
    }

    /// The cells as readable text, for previews: "x | 0 | 1".
    var plainPreview: String {
        rows.first.map { $0.joined(separator: " | ") } ?? ""
    }
}
