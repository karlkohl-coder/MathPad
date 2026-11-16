import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Turns a file the user picked into a single normalised page image.
enum WorksheetImageLoader {

    /// What the open panel and drag-and-drop accept.
    static let supportedTypes: [UTType] = [.pdf, .png, .jpeg, .tiff, .heic, .bmp, .gif]

    /// Long edge of the image we send. Models downscale anything larger anyway,
    /// and a bigger file only costs time.
    static let maximumEdge: CGFloat = 1568

    enum LoadError: LocalizedError {
        case unreadable(String)
        case emptyPDF

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): "„\(name)" + "“ konnte nicht gelesen werden."
            case .emptyPDF: "Das PDF enthält keine Seite."
            }
        }
    }

    static func load(from url: URL) throws -> WorksheetImage {
        let name = url.deletingPathExtension().lastPathComponent
        if url.pathExtension.lowercased() == "pdf" {
            return try loadPDF(url, name: name)
        }
        guard let image = NSImage(contentsOf: url), let cgImage = image.cgImage else {
            throw LoadError.unreadable(url.lastPathComponent)
        }
        return try encode(cgImage, name: name, skippedPages: 0)
    }

    private static func loadPDF(_ url: URL, name: String) throws -> WorksheetImage {
        guard let document = PDFDocument(url: url), document.pageCount > 0,
              let page = document.page(at: 0) else {
            throw LoadError.emptyPDF
        }
        let bounds = page.bounds(for: .mediaBox)
        // Render well above the target size, then downscale once — sharper than
        // rendering straight to the final size.
        let scale = min(3, max(1, maximumEdge * 1.5 / max(bounds.width, bounds.height)))
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let thumbnail = page.thumbnail(of: pixelSize, for: .mediaBox)
        guard let cgImage = thumbnail.cgImage else { throw LoadError.unreadable(url.lastPathComponent) }
        return try encode(cgImage, name: name, skippedPages: document.pageCount - 1)
    }

    /// Scales to the target box (never up) and writes PNG on a white ground, so a
    /// transparent scan does not arrive as black-on-black.
    private static func encode(_ image: CGImage, name: String, skippedPages: Int) throws -> WorksheetImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let factor = min(1, maximumEdge / max(width, height))
        let targetWidth = Int((width * factor).rounded())
        let targetHeight = Int((height * factor).rounded())

        guard let context = CGContext(data: nil,
                                      width: targetWidth,
                                      height: targetHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw LoadError.unreadable(name)
        }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let scaled = context.makeImage() else { throw LoadError.unreadable(name) }
        let rep = NSBitmapImageRep(cgImage: scaled)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw LoadError.unreadable(name)
        }
        return WorksheetImage(pngData: data,
                              pixelWidth: targetWidth,
                              pixelHeight: targetHeight,
                              sourceName: name,
                              skippedPages: max(0, skippedPages))
    }
}

private extension NSImage {
    var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
