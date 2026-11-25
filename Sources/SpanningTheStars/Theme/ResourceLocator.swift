import Foundation

/// Finds files inside the SwiftPM resource bundle. The packaged .app copies the bundle into
/// `Contents/Resources`; `Bundle.module` is only touched when that fails, because its generated
/// accessor calls `fatalError` when the bundle is not at the build machine's path.
enum ResourceLocator {
    static func url(_ name: String) -> URL? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL {
            for url in [res.appendingPathComponent("SpanningTheStars_SpanningTheStars.bundle/\(name)"),
                        res.appendingPathComponent(name)] where fm.fileExists(atPath: url.path) {
                return url
            }
        }
        return Bundle.module.resourceURL?.appendingPathComponent(name)
    }
}
