import Foundation

/// Same target list as the HTML dashboard's server.py — kept in sync by hand.
/// Patterns are shell globs (fed to `/bin/sh -c`, which expands `~` and `*`).
private struct TargetDef {
    let id: String
    let category: String
    let label: String
    let risk: String
    let patterns: [String]
}

private let home = NSHomeDirectory()

private let targetDefs: [TargetDef] = [
    TargetDef(id: "derived_data", category: "Xcode", label: "DerivedData", risk: "safe",
              patterns: ["\(home)/Library/Developer/Xcode/DerivedData"]),
    TargetDef(id: "sim_caches", category: "Xcode", label: "Simulator Caches", risk: "safe",
              patterns: ["\(home)/Library/Developer/CoreSimulator/Caches"]),
    TargetDef(id: "xcode_caches", category: "Xcode", label: "Xcode App Caches", risk: "safe",
              patterns: ["\(home)/Library/Caches/com.apple.dt.Xcode"]),
    TargetDef(id: "device_support", category: "Xcode", label: "Old iOS DeviceSupport", risk: "caution",
              patterns: ["\(home)/Library/Developer/Xcode/iOS DeviceSupport"]),
    TargetDef(id: "archives", category: "Xcode", label: "Archives", risk: "risky",
              patterns: ["\(home)/Library/Developer/Xcode/Archives"]),
    TargetDef(id: "android_studio_caches", category: "Android & JetBrains", label: "Android Studio Caches", risk: "safe",
              patterns: ["\(home)/Library/Caches/Google/AndroidStudio*", "\(home)/Library/Caches/JetBrains/AndroidStudio*"]),
    TargetDef(id: "goland_caches", category: "Android & JetBrains", label: "GoLand Caches", risk: "safe",
              patterns: ["\(home)/Library/Caches/JetBrains/GoLand*"]),
    TargetDef(id: "gradle_caches", category: "Android & JetBrains", label: "Gradle Caches", risk: "safe",
              patterns: ["\(home)/.gradle/caches", "\(home)/.gradle/wrapper/dists"]),
    TargetDef(id: "avd_snapshots", category: "Android & JetBrains", label: "Emulator (AVD) Snapshots", risk: "caution",
              patterns: ["\(home)/.android/avd/*.avd/snapshots"]),
    TargetDef(id: "homebrew_cache", category: "Package Manager Caches", label: "Homebrew Cache", risk: "safe",
              patterns: ["\(home)/Library/Caches/Homebrew"]),
    TargetDef(id: "npm_cache", category: "Package Manager Caches", label: "npm Cache", risk: "safe",
              patterns: ["\(home)/.npm/_cacache"]),
    TargetDef(id: "go_build_cache", category: "Package Manager Caches", label: "Go Build Cache", risk: "safe",
              patterns: ["\(home)/Library/Caches/go-build"]),
    TargetDef(id: "user_cache", category: "System Junk", label: "User App Caches", risk: "caution",
              patterns: ["\(home)/Library/Caches/*"]),
    TargetDef(id: "user_logs", category: "System Junk", label: "User App Logs", risk: "safe",
              patterns: ["\(home)/Library/Logs/*"]),
    TargetDef(id: "trash", category: "System Junk", label: "Trash", risk: "risky",
              patterns: ["\(home)/.Trash/*"]),
]

/// Result of a `du -sk` line: size plus the exact (glob-expanded) path it
/// measured, so cleaning later touches precisely what was measured.
private struct DuLine {
    let kb: Int64
    let path: String
}

enum DiskScanner {
    /// Runs `du -sk` (via a shell, so `~`/`*` expand) over a target's
    /// patterns. Safe to call off the main thread — this blocks on
    /// subprocess I/O.
    private static func duLines(patterns: [String]) -> [DuLine] {
        let quoted = patterns.map { "\"\($0)\"" }.joined(separator: " ")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "du -sk \(quoted) 2>/dev/null"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        var lines: [DuLine] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kb = Int64(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            lines.append(DuLine(kb: kb, path: String(parts[1])))
        }
        return lines
    }

    private static func sizeBytes(patterns: [String]) -> Int64 {
        duLines(patterns: patterns).reduce(0) { $0 + $1.kb } * 1024
    }

    static func diskInfo() -> DiskInfo {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = Int64(values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0))
            return DiskInfo(totalBytes: total, usedBytes: total - free, freeBytes: free)
        } catch {
            return DiskInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0)
        }
    }

    /// Runs the full scan across all targets concurrently (each `du` call
    /// blocks on disk I/O, so a small thread pool turns wall-clock into
    /// "slowest single target" instead of "sum of all targets").
    static func scan(completion: @escaping (ScanResult) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var results = [CacheTarget?](repeating: nil, count: targetDefs.count)
            let lock = NSLock()
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "devdisk.scan.concurrent", attributes: .concurrent)
            for (index, def) in targetDefs.enumerated() {
                group.enter()
                queue.async {
                    let bytes = sizeBytes(patterns: def.patterns)
                    let target = CacheTarget(id: def.id, category: def.category, label: def.label, risk: def.risk, bytes: bytes)
                    lock.lock()
                    results[index] = target
                    lock.unlock()
                    group.leave()
                }
            }
            group.wait()
            let result = ScanResult(
                scannedAt: Date(),
                disk: diskInfo(),
                targets: results.compactMap { $0 }
            )
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Deletes the contents of a target's resolved paths (keeps the
    /// directory itself, mirrors server.py's clean_target). Runs off the
    /// main thread; calls back with bytes freed + any errors encountered.
    static func clean(targetID: String, completion: @escaping (CleanOutcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let def = targetDefs.first(where: { $0.id == targetID }) else {
                DispatchQueue.main.async {
                    completion(CleanOutcome(freedBytes: 0, errors: ["Unknown target '\(targetID)'"]))
                }
                return
            }
            let lines = duLines(patterns: def.patterns)
            var freed: Int64 = 0
            var errors: [String] = []
            let fm = FileManager.default
            for line in lines {
                freed += line.kb * 1024
                let url = URL(fileURLWithPath: line.path)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    // Remove contents, keep the directory so the owning
                    // tool doesn't need to recreate it before its next write.
                    if let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        for child in children {
                            do { try fm.removeItem(at: child) }
                            catch { errors.append("\(child.lastPathComponent): \(error.localizedDescription)") }
                        }
                    }
                } else {
                    do { try fm.removeItem(at: url) }
                    catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
            }
            DispatchQueue.main.async {
                completion(CleanOutcome(freedBytes: freed, errors: errors))
            }
        }
    }
}

struct CleanOutcome {
    let freedBytes: Int64
    let errors: [String]
    var ok: Bool { errors.isEmpty }
}
