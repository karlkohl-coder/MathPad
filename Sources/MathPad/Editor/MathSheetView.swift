import SwiftUI
import WebKit

/// SwiftUI wrapper around the editor's web view.
///
/// `updateNSView` runs inside a SwiftUI update, so it only forwards values that
/// actually changed — pushing on every pass is both wasteful and, if the
/// controller records anything observable, a way to build an update loop.
struct MathSheetView: NSViewRepresentable {
    let controller: EditorController
    var isDark: Bool
    var fontSize: Double

    final class Coordinator {
        var appliedDark: Bool?
        var appliedFontSize: Double?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        controller.startIfNeeded()
        return controller.webView
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.appliedDark != isDark {
            coordinator.appliedDark = isDark
            controller.setAppearance(dark: isDark)
        }
        if coordinator.appliedFontSize != fontSize {
            coordinator.appliedFontSize = fontSize
            controller.setFontSize(fontSize)
        }
    }
}
