import AppKit
import CoreText
import WebKit

/// Sets a sheet on A4 pages.
///
/// The editor itself is a poor source for a PDF: its formula lines are input
/// fields that cannot wrap, so anything wider than the window was cut off, and
/// the result was one endless page. This renderer loads the editor page into its
/// own invisible web view, lets `print.js` set the sheet as flowing text at the
/// width of an A4 text block, and then cuts that into pages — between lines of
/// the sheet where possible, between lines of a paragraph or rows of a table
/// otherwise. Each page is copied in as vector PDF, so text stays text.
@MainActor
final class PDFRenderer: NSObject {

    enum RenderError: LocalizedError {
        case resourcesMissing
        case editorDidNotLoad
        case layoutFailed(String)

        var errorDescription: String? {
            switch self {
            case .resourcesMissing: "Die Editor-Dateien fehlen im Programm."
            case .editorDidNotLoad: "Die Seite für den PDF-Export konnte nicht geladen werden."
            case .layoutFailed(let detail): "Das Blatt konnte nicht gesetzt werden: \(detail)"
            }
        }
    }

    /// A4 in PostScript points.
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    /// 2 cm left and right, a little less top and bottom plus room for the page number.
    static let sideMargin: CGFloat = 56.7
    static let topMargin: CGFloat = 50
    static let bottomMargin: CGFloat = 56
    /// CSS pixels are laid out at 96 dpi, PDF points are 72 per inch.
    static let pointsPerPixel: CGFloat = 0.75
    /// Formula size on paper: 16 px ≙ 12 pt.
    static let fontSizePixels = 16

    static var contentWidthPixels: CGFloat {
        (pageSize.width - 2 * sideMargin) / pointsPerPixel
    }
    static var contentHeightPixels: CGFloat {
        (pageSize.height - topMargin - bottomMargin) / pointsPerPixel
    }

    private var webView: WKWebView?
    private var window: NSWindow?
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var isReady = false

    // MARK: Public

    /// The sheet as a multi-page A4 PDF.
    static func render(blocks: [Block], resources: URL? = AppResources.root) async throws -> Data {
        let renderer = PDFRenderer()
        defer { renderer.tearDown() }
        return try await renderer.run(blocks: blocks, resources: resources)
    }

    // MARK: Layout in the web view

    struct Layout {
        struct Line { var top: CGFloat; var bottom: CGFloat; var breaks: [CGFloat] }
        var width: CGFloat
        var height: CGFloat
        var lines: [Line]
    }

    private func run(blocks: [Block], resources: URL?) async throws -> Data {
        guard let resources else { throw RenderError.resourcesMissing }
        let index = resources.appendingPathComponent("web/index.html")
        guard FileManager.default.fileExists(atPath: index.path) else { throw RenderError.resourcesMissing }

        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakMessageHandler(self), name: "mathpad")
        let width = Self.contentWidthPixels
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 1200), configuration: config)
        webView = view

        // WebKit only lays out and paints reliably inside a window. This one is
        // never shown.
        let host = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: width, height: 1200),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = view
        window = host

        view.loadFileURL(index, allowingReadAccessTo: resources)
        try await waitUntilReady(timeout: 15)

        _ = try? await view.evaluateJavaScript("MP.setTheme('light'); MP.setFontSize(\(Self.fontSizePixels)); 1")
        let payload: [String: Any] = [
            "width": Double(width),
            "blocks": blocks.map { ["id": $0.id.uuidString, "kind": $0.kind.rawValue, "value": $0.value] },
        ]
        let raw: Any?
        do {
            raw = try await view.callAsyncJavaScript("return await MP.preparePrint(payload)",
                                                     arguments: ["payload": payload],
                                                     contentWorld: .page)
        } catch {
            throw RenderError.layoutFailed(error.localizedDescription)
        }
        guard let layout = Self.decodeLayout(raw) else { throw RenderError.layoutFailed("keine Maße") }

        // The whole document has to exist at full height for every slice.
        let fullHeight = max(layout.height, 1)
        view.frame = CGRect(x: 0, y: 0, width: width, height: fullHeight)
        host.setContentSize(CGSize(width: width, height: fullHeight))

        let slices = Self.paginate(layout, pageHeight: Self.contentHeightPixels)
        var pages: [Data] = []
        for slice in slices {
            let pdf = WKPDFConfiguration()
            pdf.rect = CGRect(x: 0, y: slice.lowerBound, width: width, height: slice.upperBound - slice.lowerBound)
            pages.append(try await view.pdf(configuration: pdf))
        }
        return Self.compose(pages: pages, slices: slices)
    }

    private func waitUntilReady(timeout: TimeInterval) async throws {
        if isReady { return }
        let timer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self?.resumeReady()
        }
        await withCheckedContinuation { continuation in
            if isReady { continuation.resume() } else { readyContinuation = continuation }
        }
        timer.cancel()
        guard isReady else { throw RenderError.editorDidNotLoad }
    }

    fileprivate func handle(message name: String) {
        guard name == "ready" else { return }
        isReady = true
        resumeReady()
    }

    private func resumeReady() {
        readyContinuation?.resume()
        readyContinuation = nil
    }

    private func tearDown() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "mathpad")
        window?.contentView = nil
        window?.close()
        webView = nil
        window = nil
    }

    private static func decodeLayout(_ raw: Any?) -> Layout? {
        guard let dict = raw as? [String: Any],
              let width = (dict["width"] as? NSNumber)?.doubleValue,
              let height = (dict["height"] as? NSNumber)?.doubleValue,
              let blocks = dict["blocks"] as? [[String: Any]] else { return nil }
        let lines = blocks.compactMap { block -> Layout.Line? in
            guard let top = (block["top"] as? NSNumber)?.doubleValue,
                  let bottom = (block["bottom"] as? NSNumber)?.doubleValue else { return nil }
            let breaks = (block["breaks"] as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) }
            return Layout.Line(top: top, bottom: bottom, breaks: breaks)
        }
        return Layout(width: width, height: height, lines: lines)
    }

    // MARK: Pages

    /// Vertical ranges, one per page.
    ///
    /// A page ends before the last line of the sheet that still fits, as long as
    /// that fills at least half the page; otherwise — one very long paragraph or
    /// table — it ends after the last text line or table row that fits, and only
    /// if there is none either is the content cut at the page edge.
    static func paginate(_ layout: Layout, pageHeight: CGFloat) -> [Range<CGFloat>] {
        guard layout.height > 0 else { return [0..<1] }
        let lineStarts = layout.lines.map(\.top)
        let innerBreaks = layout.lines.flatMap(\.breaks) + layout.lines.map(\.bottom)

        var pages: [Range<CGFloat>] = []
        var start: CGFloat = 0
        while layout.height - start > 0.5 {
            let limit = start + pageHeight
            if layout.height <= limit {
                pages.append(start..<layout.height)
                break
            }
            let minimumFill = start + pageHeight * 0.5
            var end: CGFloat
            if let boundary = lineStarts.filter({ $0 > minimumFill && $0 <= limit }).max() {
                end = boundary
            } else if let inner = innerBreaks.filter({ $0 > start + 1 && $0 <= limit }).max() {
                end = inner
            } else if let boundary = lineStarts.filter({ $0 > start + 1 && $0 <= limit }).max() {
                end = boundary
            } else {
                end = limit
            }
            pages.append(start..<end)
            start = end
        }
        return pages.isEmpty ? [0..<1] : pages
    }

    /// Places each slice at the top of an A4 page and numbers the pages.
    static func compose(pages: [Data], slices: [Range<CGFloat>]) -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        for (index, data) in pages.enumerated() {
            context.beginPDFPage(nil)
            if let provider = CGDataProvider(data: data as CFData),
               let document = CGPDFDocument(provider),
               let page = document.page(at: 1) {
                let box = page.getBoxRect(.mediaBox)
                let height = (slices[index].upperBound - slices[index].lowerBound)
                context.saveGState()
                // Top-left of the text block, then pixels to points.
                context.translateBy(x: sideMargin, y: pageSize.height - topMargin - height * pointsPerPixel)
                context.scaleBy(x: pointsPerPixel * (box.width > 0 ? (contentWidthPixels / box.width) : 1),
                                y: pointsPerPixel * (box.height > 0 ? (height / box.height) : 1))
                context.translateBy(x: -box.minX, y: -box.minY)
                context.drawPDFPage(page)
                context.restoreGState()
            }
            if pages.count > 1 {
                drawPageNumber(index + 1, of: pages.count, in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    private static func drawPageNumber(_ number: Int, of total: Int, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5),
            .foregroundColor: NSColor(white: 0.45, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(number) / \(total)", attributes: attributes))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.saveGState()
        context.textPosition = CGPoint(x: (pageSize.width - width) / 2, y: bottomMargin / 2 - 3)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

/// The content controller keeps its handler alive; this keeps it from keeping
/// the renderer alive too.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: PDFRenderer?
    init(_ target: PDFRenderer) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any], let name = body["name"] as? String else { return }
            target?.handle(message: name)
        }
    }
}
