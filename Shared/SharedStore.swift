import Foundation

/// Reads/writes the scan snapshot to a plain file on disk. The widget
/// extension and the menu bar app are NOT app-sandboxed (this is a
/// locally-built, non-App-Store tool), so a plain file in Application
/// Support works fine without needing an App Group entitlement.
enum SharedStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DevDiskWidget", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("scan.json")
    }

    static func load() -> ScanResult {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ScanResult.self, from: data)) ?? .empty
    }

    static func save(_ result: ScanResult) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(result) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
