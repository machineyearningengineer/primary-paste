import Foundation

enum PracticePageCache {
    static func write(html: String, in directory: URL) throws -> URL {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous =
            (try files.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            )).filter { url in
                let name = url.deletingPathExtension().lastPathComponent
                return url.pathExtension == "html" && name.hasPrefix("first-paste-")
                    && UUID(uuidString: String(name.dropFirst("first-paste-".count))) != nil
                    && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.sorted {
                let lhs =
                    (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let rhs =
                    (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return lhs > rhs
            }
        // A fresh URL prevents browsers from reusing an error tab after cache eviction.
        let page = directory.appendingPathComponent("first-paste-\(UUID().uuidString).html")
        try html.write(to: page, atomically: true, encoding: .utf8)
        for stale in previous.dropFirst(4) { try? files.removeItem(at: stale) }
        return page
    }

}
