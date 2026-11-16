import SwiftUI

/// The sketching mode: a sheet of formulas you type straight from the keyboard.
@MainActor
enum SketchFeature {
    static func register() {
        FeatureRegistry.shared.register(
            Feature(id: "sketch", title: "Skizze", systemImage: "function", order: 0) {
                SketchView()
            }
        )
    }
}

struct SketchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            SheetListView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 320)
        } detail: {
            EditorArea()
        }
        .onChange(of: colorScheme) { _, new in
            model.editor.setAppearance(dark: new == .dark)
        }
    }
}
