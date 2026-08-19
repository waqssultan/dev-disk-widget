import Foundation

/// One cache/junk location we know how to size (and, from the menu bar app,
/// clean). Mirrors the categories in the HTML dashboard's server.py.
struct CacheTarget: Codable, Identifiable, Hashable {
    var id: String
    var category: String
    var label: String
    var risk: String // "safe" | "caution" | "risky"
    var bytes: Int64
}

struct DiskInfo: Codable, Hashable {
    var totalBytes: Int64
    var usedBytes: Int64
    var freeBytes: Int64

    var percentUsed: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0
    }
}

/// The full snapshot written by the menu bar app and read by the widget.
struct ScanResult: Codable, Hashable {
    var scannedAt: Date
    var disk: DiskInfo
    var targets: [CacheTarget]

    var safeReclaimableBytes: Int64 {
        targets.filter { $0.risk == "safe" }.reduce(0) { $0 + $1.bytes }
    }

    var topTargets: [CacheTarget] {
        targets.sorted { $0.bytes > $1.bytes }
    }

    static let empty = ScanResult(
        scannedAt: .distantPast,
        disk: DiskInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0),
        targets: []
    )
}

func humanBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024, unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}
