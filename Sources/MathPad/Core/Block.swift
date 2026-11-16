import Foundation

/// The type of a block in a sheet.
///
/// Deliberately *not* a closed enum: new block kinds (a CAS result, a plot, an
/// AI question) can be added later without breaking documents written by older
/// builds — an unknown kind round-trips instead of failing to decode.
struct BlockKind: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    /// A formula, stored as LaTeX.
    static let math = BlockKind(rawValue: "math")
    /// Body text between formulas, set at the same size as a formula — the
    /// normal prose of a worksheet.
    static let paragraph = BlockKind(rawValue: "paragraph")
    /// A smaller aside. Keeps its old raw value so sheets written before the two
    /// were separated still load; those are migrated to `.paragraph` on opening,
    /// because back then this was the only prose kind there was.
    static let text = BlockKind(rawValue: "text")
    /// A section title.
    static let heading = BlockKind(rawValue: "heading")
    /// Prose and formulas on one line — stored as LaTeX whose prose runs sit in
    /// `\text{…}`. Worksheets are full of these ("Sei \(x \in \mathbb{R}\) mit …").
    static let mixed = BlockKind(rawValue: "mixed")
    /// A grid of cells, stored as `TableData` JSON. Not in `selectable`: a
    /// table is inserted, not switched to from a line.
    static let table = BlockKind(rawValue: "table")

    /// Kinds the user can pick in the UI, in menu order.
    static let selectable: [BlockKind] = [.math, .mixed, .paragraph, .text, .heading]

    var germanName: String {
        switch self {
        case .math: "Formel"
        case .mixed: "Text + Formel"
        case .paragraph: "Text"
        case .text: "Notiz"
        case .heading: "Überschrift"
        case .table: "Tabelle"
        default: rawValue
        }
    }

    /// Whether the block's value is LaTeX rather than plain text.
    var isLaTeX: Bool { self == .math || self == .mixed }
}

/// One line of a sheet.
struct Block: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: BlockKind
    /// LaTeX for `.math` / `.mixed`, HTML for the prose kinds, JSON for `.table`.
    var value: String

    init(id: UUID = UUID(), kind: BlockKind = .math, value: String = "") {
        self.id = id
        self.kind = kind
        self.value = value
    }

    /// Notes hold HTML, so emptiness is judged on the text inside the markup —
    /// an empty `<span>` left behind by the editor is still an empty line.
    /// Lenient for the same reason as `Sheet`: a block missing its kind is a
    /// formula, and a block missing its value is empty — neither is a reason to
    /// refuse the whole sheet.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(BlockKind.self, forKey: .kind) ?? .math
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
    }

    var isEmpty: Bool {
        if kind == .table { return TableData(value: value).isEmpty }
        let text = kind.isLaTeX ? value : ProseText.plain(value)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The line as readable text, for previews and window titles.
    var plainPreview: String {
        if kind == .table { return TableData(value: value).plainPreview }
        return kind.isLaTeX ? value : ProseText.plain(value)
    }
}
