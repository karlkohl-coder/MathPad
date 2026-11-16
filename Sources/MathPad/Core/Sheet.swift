import Foundation

/// A document: an ordered list of blocks.
struct Sheet: Identifiable, Codable, Hashable, Sendable {
    static let currentFormatVersion = 1

    var id: UUID
    var title: String
    var blocks: [Block]
    /// Name of the group this sheet sits in; `nil` means the ungrouped section.
    /// Stored on the sheet itself so a sheet file stays self-contained.
    var group: String?
    /// Bumped when the stored shape changes so old sheets can be brought
    /// forward on opening. 0 = written before body text and notes were separate.
    var formatVersion: Int = 0
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         title: String = "Unbenannt",
         blocks: [Block] = [Block()],
         group: String? = nil,
         formatVersion: Int = Sheet.currentFormatVersion,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.blocks = blocks
        self.group = group
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Reads a sheet leniently.
    ///
    /// Swift's synthesized decoder demands every non-optional key, *including*
    /// ones that have a default value — so simply adding a field would make every
    /// sheet written before it unreadable. Decoding each key as optional with a
    /// fallback keeps old documents loadable and leaves room for the next field.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Unbenannt"
        blocks = try container.decodeIfPresent([Block].self, forKey: .blocks) ?? [Block()]
        group = try container.decodeIfPresent(String.self, forKey: .group)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    /// Title shown in the sidebar: the explicit title, or a preview of the first
    /// non-empty block so a fresh sheet is still recognisable.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "Unbenannt" { return trimmed }
        if let first = blocks.first(where: { !$0.isEmpty }) {
            return String(first.plainPreview.prefix(40))
        }
        return "Unbenannt"
    }

    /// The whole sheet as a LaTeX fragment — math blocks as display equations,
    /// text blocks as prose.
    func asLaTeX() -> String {
        blocks.compactMap { block in
            if block.isEmpty { return nil }
            switch block.kind {
            case .math:    return "\\[\n\(block.value)\n\\]"
            // A mixed line is one paragraph: its prose already sits in \text{},
            // so inline math keeps it on the same line.
            case .mixed:   return "$\(block.value)$"
            case .heading: return "\\section*{\(ProseText.latex(block.value))}"
            case .table:   return TableData(value: block.value).asLaTeX()
            default:       return ProseText.latex(block.value)  // .paragraph und .text
            }
        }.joined(separator: "\n\n")
    }

    /// The whole sheet as Markdown with `$$…$$` math — what most note apps,
    /// Obsidian and Notion understand.
    func asMarkdown() -> String {
        blocks.compactMap { block in
            if block.isEmpty { return nil }
            switch block.kind {
            case .math:    return "$$\n\(block.value)\n$$"
            case .mixed:   return "$\(block.value)$"
            case .heading: return "## \(ProseText.markdown(block.value))"
            case .table:   return TableData(value: block.value).asMarkdown()
            default:       return ProseText.markdown(block.value)
            }
        }.joined(separator: "\n\n")
    }
}
