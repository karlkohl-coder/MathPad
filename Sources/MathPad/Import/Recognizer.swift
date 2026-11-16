import Foundation

/// One page of a worksheet, ready to be handed to a recognizer.
struct WorksheetImage: Sendable {
    /// PNG bytes, already scaled down to something a model accepts.
    var pngData: Data
    var pixelWidth: Int
    var pixelHeight: Int
    /// File name, used to title the resulting sheet.
    var sourceName: String
    /// Pages after the first that were skipped, so the UI can say so.
    var skippedPages: Int = 0

    var base64: String { pngData.base64EncodedString() }
}

/// Turns a picture of a worksheet into sheet blocks.
protocol WorksheetRecognizer: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Why this recognizer cannot run right now, in German, or `nil` if it can.
    func unavailableReason() -> String?
    func recognize(_ image: WorksheetImage) async throws -> [Block]
}

enum RecognitionError: LocalizedError {
    case notConfigured(String)
    case transport(String)
    case badResponse(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .notConfigured(let detail): detail
        case .transport(let detail): "Verbindung fehlgeschlagen: \(detail)"
        case .badResponse(let detail): "Unerwartete Antwort: \(detail)"
        case .emptyResult: "Auf der Seite wurde nichts erkannt."
        }
    }
}

/// The instruction every model-based recognizer sends, and the parser for what
/// comes back. Kept in one place so all providers behave identically.
enum RecognitionPrompt {

    static let instruction = """
    Du bekommst das Bild EINER Seite eines Mathematik-Arbeitsblatts.

    Übertrage die Seite vollständig, von oben nach unten in Lesereihenfolge.

    Antworte AUSSCHLIESSLICH mit JSON in genau dieser Form, ohne Markdown-Zaun,
    ohne Erklärung davor oder danach:

    {"blocks":[{"kind":"...","value":"..."}]}

    Erlaubte Werte für "kind":
    - "heading" — Überschrift oder Aufgabennummer, die als Titel steht. value = reiner Text.
    - "text"    — reiner Fließtext ohne Formelanteil. value = reiner Text.
    - "math"    — abgesetzte Formel allein in der Zeile. value = reines LaTeX OHNE $-Zeichen.
    - "mixed"   — Zeile, in der Text UND Formel vorkommen (auf Arbeitsblättern der
                  Normalfall, z. B. „Sei f: R -> R stetig mit f(0)=1").
                  value = LaTeX, in dem jeder Fließtext-Abschnitt in \\text{...} steht,
                  z. B. \\text{Sei }f\\colon\\mathbb{R}\\to\\mathbb{R}\\text{ stetig mit }f(0)=1
    - "table"   — eine Tabelle (Wertetabelle, Vorzeichentabelle, Übersicht). Statt "value"
                  gibst du "rows" an: eine Liste von Zeilen, jede eine Liste von Zellen,
                  z. B. {"kind":"table","header":true,"rows":[["x","0","1"],["f(x)","1","2"]]}.
                  Jede Zelle ist LaTeX wie bei "mixed" (Text in \\text{...}), leere Zelle = "".
                  "header": true, wenn die erste Zeile Spaltenüberschriften enthält.

    Regeln für das LaTeX:
    - Es muss von KaTeX/MathLive darstellbar sein. Verwende \\frac, \\sqrt, \\int, \\sum,
      \\lim, \\mathbb{R}, \\begin{pmatrix}...\\end{pmatrix}, \\begin{cases}...\\end{cases}.
    - Verwende NICHT: $ oder $$ als Trenner, \\substack, \\dots (nimm \\ldots),
      \\begin{align}, \\begin{equation}, \\label, \\ref, \\includegraphics.
    - Mehrzeilige Gleichungsketten: pro Zeile einen eigenen Block, nicht align.
    - Übernimm Indizes, Exponenten, Brüche, Wurzeln, Vektorpfeile und Matrizen genau so,
      wie sie auf dem Blatt stehen.

    Weiteres:
    - Grafische Abbildungen (Diagramme, Zeichnungen, Koordinatensysteme, Skizzen) lässt du
      komplett weg — kein Block dafür, auch keine Beschreibung.
    - Beschriftungen, die zu einer weggelassenen Abbildung gehören, ebenfalls weglassen.
    - Leere Zeilen und Seitenzahlen weglassen.
    - Nichts hinzuerfinden: Was du nicht lesen kannst, lässt du weg.
    """

    private struct Payload: Decodable {
        struct Item: Decodable {
            let kind: String
            let value: String?
            let rows: [[String]]?
            let header: Bool?
        }
        let blocks: [Item]
    }

    /// Pulls the JSON object out of whatever the model wrapped it in and turns it
    /// into blocks. Models like to add prose or a ```json fence; both are tolerated.
    static func blocks(fromModelOutput raw: String) throws -> [Block] {
        let json = extractJSONObject(from: raw)
        guard let data = json.data(using: .utf8) else {
            throw RecognitionError.badResponse(String(raw.prefix(200)))
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw RecognitionError.badResponse(String(raw.prefix(200)))
        }

        let blocks = payload.blocks.compactMap { item -> Block? in
            if item.kind == BlockKind.table.rawValue || item.rows != nil {
                return tableBlock(item.rows ?? [], header: item.header ?? false)
            }
            let value = (item.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            // Recognised prose is a worksheet's body text, not a margin note,
            // so it lands in `.paragraph` — which is also where anything
            // unrecognised goes rather than being dropped.
            var kind = BlockKind(rawValue: item.kind)
            if kind == .text { kind = .paragraph }
            let known = BlockKind.selectable.contains(kind) ? kind : .paragraph
            return Block(kind: known, value: sanitize(value, kind: known))
        }
        guard !blocks.isEmpty else { throw RecognitionError.emptyResult }
        return blocks
    }

    /// A recognised table, its cells cleaned like a mixed line. A "table" with
    /// nothing in it is dropped, like an empty line.
    static func tableBlock(_ rows: [[String]], header: Bool) -> Block? {
        let cleaned = rows
            .map { row in row.map { sanitize($0, kind: .mixed) } }
            .filter { !$0.isEmpty }
        let table = TableData(rows: cleaned, header: header)
        guard !cleaned.isEmpty, !table.isEmpty else { return nil }
        return Block(kind: .table, value: table.json)
    }

    /// Repairs the handful of things models emit that MathLive cannot render,
    /// and escapes recognised prose so a worksheet containing "a < b" does not
    /// arrive looking like markup.
    static func sanitize(_ value: String, kind: BlockKind) -> String {
        guard kind.isLaTeX else { return ProseText.escapeHTML(value) }
        var result = value
        // Stray delimiters: the block itself already is the maths context.
        if result.hasPrefix("$$"), result.hasSuffix("$$"), result.count > 4 {
            result = String(result.dropFirst(2).dropLast(2))
        } else if result.hasPrefix("$"), result.hasSuffix("$"), result.count > 2 {
            result = String(result.dropFirst().dropLast())
        }
        if result.hasPrefix("\\[") , result.hasSuffix("\\]"), result.count > 4 {
            result = String(result.dropFirst(2).dropLast(2))
        }
        // Commands MathLive renders as an error box.
        result = result.replacingOccurrences(of: "\\dots", with: "\\ldots")
        result = result.replacingOccurrences(of: "\\substack", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONObject(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fence = text.range(of: "```") {
            text = String(text[fence.upperBound...])
            if text.lowercased().hasPrefix("json") { text = String(text.dropFirst(4)) }
            if let end = text.range(of: "```") { text = String(text[..<end.lowerBound]) }
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start...end])
    }
}
