import Foundation

/// Finds the bundled web editor.
///
/// The same files have to be found in two different layouts: inside the
/// assembled `.app` (`Contents/Resources/web`) and, when running straight from
/// `swift run`, inside SwiftPM's resource bundle next to the executable. We look
/// in every plausible place and use the first that actually contains the page.
///
/// `Bundle.module` is deliberately not used: its generated accessor traps when
/// the SwiftPM bundle is absent, which is exactly the shipping case.
enum AppResources {

    /// Directory that holds `web/` and `vendor/`.
    static let root: URL? = candidates.first { url in
        FileManager.default.fileExists(atPath: url.appendingPathComponent("web/index.html").path)
    }

    static var indexHTML: URL? {
        root?.appendingPathComponent("web/index.html")
    }

    private static var candidates: [URL] {
        var urls: [URL] = []
        if let resources = Bundle.main.resourceURL { urls.append(resources) }

        // `swift run`: the resource bundle sits next to the executable.
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            let bundle = executable.appendingPathComponent("MathPad_MathPad.bundle")
            urls.append(bundle)
            urls.append(bundle.appendingPathComponent("Contents/Resources"))
            urls.append(executable.appendingPathComponent("Resources"))
        }
        urls.append(Bundle.main.bundleURL)
        return urls
    }
}
