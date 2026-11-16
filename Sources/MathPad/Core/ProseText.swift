import Foundation

/// One stretch of note text that shares the same character styling.
struct ProseRun: Equatable, Sendable {
    var text: String
    var bold = false
    var italic = false
    var underline = false
    /// `#rrggbb`, or `nil` for the theme colour.
    var color: String?
    var background: String?

    var isStyled: Bool { bold || italic || underline || color != nil || background != nil }
}

/// Converts the small HTML subset that note blocks store.
///
/// Notes are edited in a `contenteditable`, so their value is HTML — but only
/// the handful of tags the editor's sanitizer lets through. Rather than reach
/// for a general HTML parser (and its surprises about default colours and
/// implicit fonts), this walks exactly that subset, which keeps export output
/// predictable and testable.
enum ProseText {

    /// Whether the value needs parsing at all. Entities count: a note holding
    /// `a &lt; b` has no tag but still is not literal text.
    static func isMarkup(_ value: String) -> Bool {
        value.contains("<") || value.contains("&")
    }

    /// Turns plain text into the HTML a note block stores.
    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: Renderers

    static func plain(_ value: String) -> String {
        runs(value).map(\.text).joined()
    }

    static func markdown(_ value: String) -> String {
        let list = runs(value)
        // `**bold**` next to `***bold italic***` would run the asterisks
        // together into an unparseable `*****`. When two emphasised runs touch,
        // the whole line switches to HTML tags, which nest unambiguously and are
        // valid Markdown too.
        let emphasisCollides = zip(list, list.dropFirst()).contains { left, right in
            (left.bold || left.italic) && (right.bold || right.italic)
        }

        return list.map { run in
            var text = run.text
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }
            if run.bold { text = emphasisCollides ? "<strong>\(text)</strong>" : "**\(text)**" }
            if run.italic { text = emphasisCollides ? "<em>\(text)</em>" : "*\(text)*" }
            if run.underline { text = "<u>\(text)</u>" }
            // Markdown has no colour of its own; inline HTML is the usual way and
            // every viewer that renders Markdown understands it.
            var styles: [String] = []
            if let color = run.color { styles.append("color:\(color)") }
            if let background = run.background { styles.append("background-color:\(background)") }
            if !styles.isEmpty {
                text = "<span style=\"\(styles.joined(separator: ";"))\">\(text)</span>"
            }
            return text
        }.joined()
    }

    static func latex(_ value: String) -> String {
        runs(value).map { run in
            var text = escapeLaTeX(run.text)
            if run.italic { text = "\\textit{\(text)}" }
            if run.bold { text = "\\textbf{\(text)}" }
            if run.underline { text = "\\underline{\(text)}" }
            if let color = run.color {
                text = "\\textcolor[HTML]{\(hexDigits(color))}{\(text)}"
            }
            if let background = run.background {
                text = "\\colorbox[HTML]{\(hexDigits(background))}{\(text)}"
            }
            return text
        }.joined()
    }

    // MARK: Parsing

    /// Flattens the markup into styled runs, carrying a style stack through
    /// nested tags.
    static func runs(_ value: String) -> [ProseRun] {
        guard isMarkup(value) else { return [ProseRun(text: decodeEntities(value))] }

        var result: [ProseRun] = []
        var stack: [ProseRun] = [ProseRun(text: "")]
        var buffer = ""
        var index = value.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            var run = stack[stack.count - 1]
            run.text = decodeEntities(buffer)
            result.append(run)
            buffer = ""
        }

        while index < value.endIndex {
            let character = value[index]
            guard character == "<", let close = value[index...].firstIndex(of: ">") else {
                buffer.append(character)
                index = value.index(after: index)
                continue
            }

            flush()
            let tag = String(value[value.index(after: index)..<close])
            index = value.index(after: close)

            if tag.hasPrefix("/") {
                if stack.count > 1 { stack.removeLast() }
                continue
            }
            let name = tag.prefix { $0.isLetter }.lowercased()
            if name == "br" {
                var run = stack[stack.count - 1]
                run.text = "\n"
                result.append(run)
                continue
            }
            // Self-closing anything else: no state change.
            if tag.hasSuffix("/") { continue }

            var style = stack[stack.count - 1]
            switch name {
            case "b", "strong": style.bold = true
            case "i", "em": style.italic = true
            case "u": style.underline = true
            case "span": apply(inlineStyle: tag, to: &style)
            default: break
            }
            stack.append(style)
        }
        flush()
        return result.filter { !$0.text.isEmpty }
    }

    /// Reads the `style="…"` attribute WebKit's editing commands write.
    private static func apply(inlineStyle tag: String, to style: inout ProseRun) {
        guard let range = tag.range(of: "style=") else { return }
        let rest = tag[range.upperBound...]
        guard let quote = rest.first, quote == "\"" || quote == "'" else { return }
        let body = rest.dropFirst()
        guard let end = body.firstIndex(of: quote) else { return }

        for declaration in body[..<end].split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let property = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch property {
            case "font-weight":
                if value == "bold" || (Int(value) ?? 0) >= 600 { style.bold = true }
            case "font-style":
                if value == "italic" || value == "oblique" { style.italic = true }
            case "text-decoration", "text-decoration-line":
                if value.contains("underline") { style.underline = true }
            case "color":
                if value == "inherit" { style.color = nil } else { style.color = normalizeColor(value) }
            case "background-color":
                if value == "transparent" { style.background = nil }
                else { style.background = normalizeColor(value) }
            default:
                break
            }
        }
    }

    // MARK: Helpers

    /// `rgb(229, 72, 77)` and `#e5484d` both become `#e5484d`.
    static func normalizeColor(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            let digits = String(trimmed.dropFirst())
            return digits.count == 6 ? "#" + digits.lowercased() : nil
        }
        guard trimmed.lowercased().hasPrefix("rgb"),
              let open = trimmed.firstIndex(of: "("),
              let close = trimmed.firstIndex(of: ")") else { return nil }
        let numbers = trimmed[trimmed.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count >= 3 else { return nil }
        return String(format: "#%02x%02x%02x", numbers[0], numbers[1], numbers[2])
    }

    private static func hexDigits(_ color: String) -> String {
        String(color.drop(while: { $0 == "#" })).uppercased()
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let map = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
                   ("&nbsp;", "\u{00A0}"), ("&amp;", "&")]
        for (entity, character) in map {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    /// Escapes the characters TeX would otherwise read as commands.
    static func escapeLaTeX(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "\\": result += "\\textbackslash{}"
            case "&", "%", "$", "#", "_", "{", "}": result += "\\\(character)"
            case "~": result += "\\textasciitilde{}"
            case "^": result += "\\textasciicircum{}"
            default: result.append(character)
            }
        }
        return result
    }
}
