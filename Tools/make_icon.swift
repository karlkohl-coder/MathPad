// Draws MathPad's app icon into a 1024pt PNG. Run: swift Tools/make_icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }
context.setShouldAntialias(true)

// Rounded-square plate with a deep indigo → blue gradient.
let inset: CGFloat = size * 0.08
let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = plate.width * 0.2237
let path = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

context.saveGState()
context.addPath(path)
context.clip()
let colors = [NSColor(srgbRed: 0.16, green: 0.20, blue: 0.45, alpha: 1).cgColor,
              NSColor(srgbRed: 0.25, green: 0.42, blue: 0.95, alpha: 1).cgColor] as CFArray
if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: colors, locations: [0, 1]) {
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: plate.minX, y: plate.maxY),
                               end: CGPoint(x: plate.maxX, y: plate.minY),
                               options: [])
}

// A faint ruled sheet behind the glyph — this is a scratch pad, after all.
context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
context.setLineWidth(size * 0.008)
for step in 1...5 {
    let y = plate.minY + plate.height * CGFloat(step) / 6
    context.move(to: CGPoint(x: plate.minX + plate.width * 0.12, y: y))
    context.addLine(to: CGPoint(x: plate.maxX - plate.width * 0.12, y: y))
}
context.strokePath()
context.restoreGState()

// The integral sign, set in the same serif italic maths uses.
let glyph = "∫"
let font = NSFont(name: "Times New Roman Italic", size: size * 0.62)
    ?? NSFont(name: "Times-Italic", size: size * 0.62)
    ?? NSFont.systemFont(ofSize: size * 0.62)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let text = NSAttributedString(string: glyph, attributes: attributes)
var bounds = text.boundingRect(with: NSSize(width: size, height: size), options: [.usesLineFragmentOrigin])
bounds.origin = CGPoint(x: (size - bounds.width) / 2, y: (size - bounds.height) / 2 - size * 0.01)

context.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.03,
                  color: NSColor.black.withAlphaComponent(0.25).cgColor)
text.draw(in: bounds)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
