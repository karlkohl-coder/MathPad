import SwiftUI

/// A top-level mode of the app.
///
/// Today there is exactly one ("Skizze"). A second one — a CAS panel, a graph
/// view, an assistant that answers questions about the sheet — registers itself
/// the same way and appears in the sidebar automatically; when only one feature
/// is registered the switcher stays hidden so nothing is in the way now.
@MainActor
struct Feature: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    /// Lower numbers appear first.
    let order: Int
    let makeView: () -> AnyView

    init(id: String,
         title: String,
         systemImage: String,
         order: Int = 100,
         @ViewBuilder view: @escaping () -> some View) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.order = order
        self.makeView = { AnyView(view()) }
    }
}

@MainActor
@Observable
final class FeatureRegistry {
    static let shared = FeatureRegistry()

    private(set) var features: [Feature] = []
    var activeID: String?

    func register(_ feature: Feature) {
        features.removeAll { $0.id == feature.id }
        features.append(feature)
        features.sort { $0.order < $1.order }
        if activeID == nil { activeID = features.first?.id }
    }

    var active: Feature? {
        features.first { $0.id == activeID } ?? features.first
    }

    var showsSwitcher: Bool { features.count > 1 }
}
