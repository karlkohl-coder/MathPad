import AppKit
import Observation
import WebKit

/// Owns the web view that renders and edits a sheet, and is the only place that
/// knows how Swift and JavaScript talk to each other.
///
/// Everything the UI can do to the editor goes through a method here, so menus,
/// the toolbar and the symbol palette never touch `evaluateJavaScript`.
@MainActor
@Observable
final class EditorController: NSObject {

    // MARK: Published editor state

    /// Kind of the block the caret is in — drives menu check marks.
    private(set) var focusedKind: BlockKind?
    /// Whether the focused block shows raw LaTeX.
    private(set) var focusedShowsSource = false
    /// Where the caret is in a table, when the focused line is one.
    private(set) var focusedTable: TableFocus?
    private(set) var isReady = false

    /// Called whenever the user edits the sheet. The sheet id is passed along so
    /// a debounced edit can never land in a sheet the user has since switched to.
    @ObservationIgnored var onChange: ((Sheet.ID, [Block]) -> Void)?
    /// Called when the user presses Escape inside the editor.
    @ObservationIgnored var onEscape: (() -> Void)?
    /// Called when the context menu's "Symbol einfügen" is chosen.
    @ObservationIgnored var onRequestPalette: (() -> Void)?

    /// Built in `init` after `super.init`, because the script message handler has
    /// to be on the configuration *before* the web view copies it.
    @ObservationIgnored private(set) var webView: WKWebView!

    // Plumbing, not UI state. These must stay unobserved: `updateNSView` sends
    // commands through `run(_:)`, and if appending to `pendingScripts` invalidated
    // the view, every update would schedule another one — an update loop that
    // spins the main thread forever and freezes the whole app.
    @ObservationIgnored private var pendingScripts: [String] = []
    @ObservationIgnored private var hasStartedLoading = false
    @ObservationIgnored private(set) var loadedSheetID: Sheet.ID?

    // MARK: Init

    override init() {
        super.init()

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(self, name: "mathpad")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        if #available(macOS 13.3, *) { webView.isInspectable = true }

    }

    /// Loads the editor page. Called when the view is first put on screen rather
    /// than from `init`, so WebKit is only started once the app is fully up.
    func startIfNeeded() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        guard let root = AppResources.root, let index = AppResources.indexHTML else {
            assertionFailure("MathPad web resources are missing from the bundle")
            return
        }
        webView.loadFileURL(index, allowingReadAccessTo: root)
        Diagnostics.log("Editor lädt \(index.lastPathComponent)")
    }

    // MARK: Document

    /// Push a sheet into the editor. Re-sending the sheet that is already open
    /// is ignored, otherwise every keystroke would bounce back and reset the caret.
    func show(_ sheet: Sheet) {
        guard loadedSheetID != sheet.id else { return }
        loadedSheetID = sheet.id
        guard let json = encode(sheet.blocks) else { return }
        run("MP.setDocument({blocks: \(json)})")
    }

    /// Force the editor to reload the sheet even if it is the current one.
    func reload(_ sheet: Sheet) {
        loadedSheetID = nil
        show(sheet)
    }

    private func encode(_ blocks: [Block]) -> String? {
        struct Wire: Encodable { let id: String; let kind: String; let value: String }
        let wire = blocks.map { Wire(id: $0.id.uuidString, kind: $0.kind.rawValue, value: $0.value) }
        guard let data = try? JSONEncoder().encode(wire) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Commands

    func insert(latex: String) { run("MP.insertLatex(\(js: latex))") }
    func newBlock(_ kind: BlockKind) { run("MP.newBlock(\(js: kind.rawValue))") }

    /// Insert recognised lines after the caret.
    func insert(blocks: [Block]) {
        guard let json = encode(blocks) else { return }
        run("MP.insertBlocks({blocks: \(json)})")
    }
    func setKind(_ kind: BlockKind) { run("MP.setKind(\(js: kind.rawValue))") }

    // MARK: Tables

    /// A new table at the caret — it takes the place of an empty line.
    func insertTable(rows: Int, columns: Int) { run("MP.newTable(\(rows), \(columns))") }
    func table(_ action: TableAction) { run("MP.table(\(js: action.rawValue))") }
    func setTableAlignment(_ alignment: TableData.Alignment) {
        run("MP.table(\"align\", \(js: alignment.rawValue))")
    }
    func setTableLines(_ style: TableData.LineStyle) {
        run("MP.table(\"lines\", \(js: style.rawValue))")
    }

    // MARK: Formatting
    //
    // Applies to the selection, or to the whole line when nothing is selected.

    func apply(_ format: TextFormat) { run("MP.format(\(js: format.rawValue))") }
    func setInkColor(_ hex: String?) { run("MP.setColor(\(js: hex ?? "none"))") }
    func setHighlight(_ hex: String?) { run("MP.setHighlight(\(js: hex ?? "none"))") }
    func clearFormatting() { run("MP.clearFormatting()") }

    func undo() { run("MP.undo()") }
    func redo() { run("MP.redo()") }

    /// Reinterpret the selection as prose or as maths.
    func convertSelection(to mode: String) { run("MP.convertSelection(\(js: mode))") }
    func toggleSource() { run("MP.toggleSource()") }
    func deleteBlock() { run("MP.deleteBlock()") }
    func moveBlockUp() { run("MP.moveUp()") }
    func moveBlockDown() { run("MP.moveDown()") }
    func duplicateBlock() { run("MP.duplicateBlock()") }
    func focusEditor() { webView.window?.makeFirstResponder(webView); run("MP.refocus()") }

    func setAppearance(dark: Bool) { run("MP.setTheme(\(js: dark ? "dark" : "light"))") }
    func setFontSize(_ points: Double) { run("MP.setFontSize(\(Int(points)))") }

    /// LaTeX of the current block (or selection). Empty if nothing is focused.
    func focusedLatex() async -> String { await string(from: "MP.focusedLatex()") }

    /// The lines exactly as the editor holds them now; saving runs a moment
    /// behind typing.
    func currentBlocks() async -> [Block]? {
        let json = await string(from: "MP.snapshotBlocks()")
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return raw.compactMap { item in
            guard let id = (item["id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return Block(id: id, kind: BlockKind(rawValue: item["kind"] as? String ?? "math"),
                         value: item["value"] as? String ?? "")
        }
    }
    func focusedMathML() async -> String { await string(from: "MP.focusedMathML()") }
    func focusedASCIIMath() async -> String { await string(from: "MP.focusedASCII()") }

    // MARK: JS plumbing

    private func run(_ script: String) {
        guard isReady else { pendingScripts.append(script); return }
        evaluate(script)
    }

    /// Runs a script and reports failures instead of swallowing them — a broken
    /// bridge call used to show up only as an editor that stayed empty.
    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script) { _, error in
            guard let error else { return }
            FileHandle.standardError.write(Data("MathPad [bridge] \(script.prefix(60))… -> \(error.localizedDescription)\n".utf8))
            Diagnostics.log("Bridge-Fehler: \(error.localizedDescription)")
        }
    }

    private func string(from expression: String) async -> String {
        guard isReady else { return "" }
        let result = try? await webView.evaluateJavaScript(expression)
        return result as? String ?? ""
    }

    private func flushPending() {
        let scripts = pendingScripts
        pendingScripts.removeAll()
        for script in scripts { evaluate(script) }
    }
}

// MARK: - Messages from JavaScript

extension EditorController: WKScriptMessageHandler {
    nonisolated func userContentController(_ controller: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        // WebKit delivers script messages on the main thread.
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any],
                  let name = body["name"] as? String else { return }
            let payload = body["payload"] as? [String: Any] ?? [:]
            handle(name: name, payload: payload)
        }
    }

    private func handle(name: String, payload: [String: Any]) {
        switch name {
        case "ready":
            Diagnostics.log("Bridge bereit, \(pendingScripts.count) Aufrufe in der Warteschlange")
            isReady = true
            flushPending()

        case "change":
            guard let raw = payload["blocks"] as? [[String: Any]] else { return }
            let blocks: [Block] = raw.compactMap { item in
                guard let idString = item["id"] as? String,
                      let id = UUID(uuidString: idString) else { return nil }
                let kind = BlockKind(rawValue: item["kind"] as? String ?? "math")
                return Block(id: id, kind: kind, value: item["value"] as? String ?? "")
            }
            if let sheetID = loadedSheetID { onChange?(sheetID, blocks) }

        case "focus":
            focusedKind = (payload["kind"] as? String).map(BlockKind.init(rawValue:))
            focusedShowsSource = payload["source"] as? Bool ?? false
            focusedTable = TableFocus(payload["table"])

        case "log":
            // JavaScript errors surface on stderr rather than disappearing silently.
            FileHandle.standardError.write(Data(("MathPad [web] " + (payload["text"] as? String ?? "") + "\n").utf8))

        case "contextmenu":
            let table = TableFocus(payload["table"])
            if let table { focusedTable = table }
            showContextMenu(hasSelection: payload["hasSelection"] as? Bool ?? false,
                            isText: payload["isText"] as? Bool ?? false,
                            table: table)

        case "escape":
            onEscape?()

        default:
            break
        }
    }
}

extension EditorController: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        FileHandle.standardError.write(Data("MathPad: Editor konnte nicht geladen werden – \(error.localizedDescription)\n".utf8))
    }

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor action: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // The editor is a local page; anything that tries to navigate elsewhere
        // (a stray link in pasted content) opens in the browser instead.
        let external: URL? = MainActor.assumeIsolated {
            action.navigationType == .linkActivated ? action.request.url : nil
        }
        if let external {
            NSWorkspace.shared.open(external)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

// MARK: - Right-click menu

extension EditorController {

    /// Puts up a menu at the pointer for a right-click inside a formula.
    ///
    /// The position comes from the mouse rather than from the click coordinates
    /// the page reports: that sidesteps scrolling, zoom and the flipped-view
    /// question, and the pointer is exactly where the menu belongs anyway.
    fileprivate func showContextMenu(hasSelection: Bool, isText: Bool, table: TableFocus?) {
        let menu = NSMenu()

        let toText = NSMenuItem(title: "Auswahl ist Text",
                                action: #selector(menuConvertToText),
                                keyEquivalent: "")
        let toMath = NSMenuItem(title: "Auswahl ist Formel",
                                action: #selector(menuConvertToMath),
                                keyEquivalent: "")
        for item in [toText, toMath] {
            item.target = self
            item.isEnabled = hasSelection
        }
        // A tick shows how the selection is set right now, so the menu answers
        // "what is this?" as well as "make it the other thing".
        if hasSelection {
            toText.state = isText ? .on : .off
            toMath.state = isText ? .off : .on
        }
        menu.addItem(toText)
        menu.addItem(toMath)

        if !hasSelection {
            let hint = NSMenuItem(title: "Dafür zuerst etwas markieren", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(.separator())
        for format in TextFormat.allCases {
            let item = NSMenuItem(title: format.germanName,
                                  action: #selector(menuFormat(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = format.rawValue
            menu.addItem(item)
        }

        if let table {
            menu.addItem(.separator())
            addTableItems(to: menu, table: table)
        }

        menu.addItem(.separator())
        let palette = NSMenuItem(title: "Symbol einfügen …",
                                 action: #selector(menuOpenPalette),
                                 keyEquivalent: "")
        palette.target = self
        menu.addItem(palette)

        let location = NSEvent.mouseLocation
        guard let window = webView.window else { return }
        let inWindow = window.convertPoint(fromScreen: location)
        let inView = webView.convert(inWindow, from: nil)
        menu.popUp(positioning: nil, at: inView, in: webView)
    }

    /// The same table commands the menu bar and the toolbar offer.
    private func addTableItems(to menu: NSMenu, table: TableFocus) {
        func item(_ title: String, _ action: Selector, _ value: String, on: Bool = false) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = on ? .on : .off
            return item
        }

        for group in TableAction.menuGroups {
            for action in group {
                let entry = item(action.germanName, #selector(menuTable(_:)), action.rawValue,
                                 on: action == .toggleHeader && table.header)
                entry.isEnabled = action.isEnabled(in: table)
                menu.addItem(entry)
            }
            menu.addItem(.separator())
        }

        let alignMenu = NSMenu()
        for alignment in TableData.Alignment.allCases {
            alignMenu.addItem(item(alignment.germanName, #selector(menuTableAlign(_:)), alignment.rawValue,
                                   on: table.alignment == alignment))
        }
        let alignItem = NSMenuItem(title: "Spalte ausrichten", action: nil, keyEquivalent: "")
        alignItem.submenu = alignMenu
        menu.addItem(alignItem)

        let linesMenu = NSMenu()
        for style in TableData.LineStyle.allCases {
            linesMenu.addItem(item(style.germanName, #selector(menuTableLines(_:)), style.rawValue,
                                   on: table.style == style))
        }
        let linesItem = NSMenuItem(title: "Linien", action: nil, keyEquivalent: "")
        linesItem.submenu = linesMenu
        menu.addItem(linesItem)
    }

    @objc fileprivate func menuTable(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = TableAction(rawValue: raw) else { return }
        table(action)
    }

    @objc fileprivate func menuTableAlign(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let alignment = TableData.Alignment(rawValue: raw) else { return }
        setTableAlignment(alignment)
    }

    @objc fileprivate func menuTableLines(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = TableData.LineStyle(rawValue: raw) else { return }
        setTableLines(style)
    }

    @objc fileprivate func menuConvertToText() { convertSelection(to: "text") }
    @objc fileprivate func menuConvertToMath() { convertSelection(to: "math") }
    @objc fileprivate func menuOpenPalette() { onRequestPalette?() }

    @objc fileprivate func menuFormat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let format = TextFormat(rawValue: raw) else { return }
        apply(format)
    }
}

// MARK: - Safe JS string interpolation

extension String.StringInterpolation {
    /// Interpolates a Swift string as a JavaScript string literal, escaped.
    mutating func appendInterpolation(js value: String) {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data()
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        appendLiteral(String(array.dropFirst().dropLast()))
    }
}
