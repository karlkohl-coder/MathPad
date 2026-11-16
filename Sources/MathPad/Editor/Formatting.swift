import AppKit
import SwiftUI

/// The three character styles that work in every kind of line.
enum TextFormat: String, CaseIterable, Identifiable {
    case bold, italic, underline

    var id: String { rawValue }

    var germanName: String {
        switch self {
        case .bold: "Fett"
        case .italic: "Kursiv"
        case .underline: "Unterstrichen"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .underline: "u"
        }
    }
}

/// One entry in the colour or highlighter menu.
struct ColorChoice: Identifiable, Hashable {
    let name: String
    /// `nil` restores the default — theme colour, or no highlight.
    let hex: String?

    var id: String { name }

    var swiftUIColor: Color? {
        guard let hex else { return nil }
        return Color(hex: hex)
    }
}

enum ColorPalette {
    /// Ink colours. Each one is chosen to stay legible on the light *and* the
    /// dark sheet, because the colour is stored in the document and the theme
    /// can change afterwards.
    static let ink: [ColorChoice] = [
        ColorChoice(name: "Standard", hex: nil),
        ColorChoice(name: "Rot", hex: "#E5484D"),
        ColorChoice(name: "Orange", hex: "#F76B15"),
        ColorChoice(name: "Gold", hex: "#D9A400"),
        ColorChoice(name: "Grün", hex: "#30A46C"),
        ColorChoice(name: "Blau", hex: "#3E8FF0"),
        ColorChoice(name: "Lila", hex: "#A063E8"),
        ColorChoice(name: "Grau", hex: "#8B8D98"),
    ]

    /// Highlighter colours. These are deliberately pale: the editor pins the ink
    /// to a dark tone whenever a highlight is applied, so marked text reads the
    /// same way in both themes.
    static let highlight: [ColorChoice] = [
        ColorChoice(name: "Ohne", hex: nil),
        ColorChoice(name: "Gelb", hex: "#FFE08A"),
        ColorChoice(name: "Grün", hex: "#B7EFC5"),
        ColorChoice(name: "Blau", hex: "#BCE0FD"),
        ColorChoice(name: "Pink", hex: "#FBC7E0"),
        ColorChoice(name: "Orange", hex: "#FFD3A5"),
    ]
}

extension ColorChoice {
    /// A drawn swatch rather than a tinted SF Symbol: macOS strips the tint from
    /// symbols inside menus, which is exactly where these are used — a row of
    /// identical grey circles would tell you nothing.
    ///
    /// Ink is a filled dot, a highlighter a rounded chip, and "no colour" an
    /// outlined circle with a stroke through it.
    func swatch(filled: Bool) -> NSImage {
        let side: CGFloat = 13
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let box = NSRect(x: 1, y: 1, width: side - 2, height: side - 2)
            let shape = filled
                ? NSBezierPath(ovalIn: box)
                : NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)

            if let hex {
                NSColor(hex: hex).setFill()
                shape.fill()
                NSColor.black.withAlphaComponent(0.20).setStroke()
            } else {
                NSColor.secondaryLabelColor.setStroke()
            }
            shape.lineWidth = 1
            shape.stroke()

            if hex == nil {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 3, y: 3))
                slash.line(to: NSPoint(x: side - 3, y: side - 3))
                slash.lineWidth = 1
                NSColor.secondaryLabelColor.setStroke()
                slash.stroke()
            }
            return true
        }
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self.init(white: 0.5, alpha: 1)
            return
        }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    /// `#RRGGBB` → colour. Returns grey for anything unparseable rather than
    /// failing, since this only drives menu swatches.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .gray
            return
        }
        self = Color(.sRGB,
                     red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
