import AppKit
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var rescanTimer: Timer?
    private var currentResult: ScanResult?
    private let rescanInterval: TimeInterval = 30 * 60 // 30 min

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "Disk")
        statusItem.button?.imagePosition = .imageLeading

        buildMenu(scanning: true)
        runScan()

        rescanTimer = Timer.scheduledTimer(withTimeInterval: rescanInterval, repeats: true) { [weak self] _ in
            self?.runScan()
        }
    }

    private func runScan() {
        DiskScanner.scan { [weak self] result in
            self?.currentResult = result
            SharedStore.save(result)
            WidgetCenter.shared.reloadAllTimelines()
            self?.buildMenu(scanning: false, result: result)
        }
    }

    private func buildMenu(scanning: Bool, result: ScanResult? = nil) {
        let menu = NSMenu()

        if scanning {
            statusItem.button?.title = " Scanning…"
            menu.addItem(NSMenuItem(title: "Scanning disk…", action: nil, keyEquivalent: ""))
        } else if let result = result {
            statusItem.button?.title = " \(humanBytes(result.disk.freeBytes)) free"

            let usedItem = NSMenuItem(
                title: "\(humanBytes(result.disk.usedBytes)) used of \(humanBytes(result.disk.totalBytes)) (\(String(format: "%.1f", result.disk.percentUsed))%)",
                action: nil, keyEquivalent: ""
            )
            usedItem.isEnabled = false
            menu.addItem(usedItem)
            menu.addItem(NSMenuItem.separator())

            let safeItem = NSMenuItem(
                title: "Safe to reclaim: \(humanBytes(result.safeReclaimableBytes))",
                action: nil, keyEquivalent: ""
            )
            safeItem.isEnabled = false
            menu.addItem(safeItem)
            menu.addItem(withTitle: "Clean All Safe Caches", action: #selector(cleanAllSafe), keyEquivalent: "").target = self
            menu.addItem(NSMenuItem.separator())

            // Per-target rows, each with its own "Clean…" submenu item.
            let topTargets = result.topTargets.prefix(8).filter { $0.bytes > 0 }
            for target in topTargets {
                let row = NSMenuItem(title: "\(riskGlyph(target.risk)) \(target.label): \(humanBytes(target.bytes))", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                let cleanItem = NSMenuItem(title: "Clean \(target.label)…", action: #selector(cleanTarget(_:)), keyEquivalent: "")
                cleanItem.target = self
                cleanItem.representedObject = target.id
                submenu.addItem(cleanItem)
                row.submenu = submenu
                menu.addItem(row)
            }
            menu.addItem(NSMenuItem.separator())

            let lastScanned = DateFormatter.localizedString(from: result.scannedAt, dateStyle: .none, timeStyle: .short)
            let scannedItem = NSMenuItem(title: "Last scanned \(lastScanned)", action: nil, keyEquivalent: "")
            scannedItem.isEnabled = false
            menu.addItem(scannedItem)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Rescan Now", action: #selector(rescanNow), keyEquivalent: "r").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q")

        statusItem.menu = menu
    }

    private func riskGlyph(_ risk: String) -> String {
        switch risk {
        case "safe": return "🟢"
        case "caution": return "🟡"
        default: return "🔴"
        }
    }

    @objc private func rescanNow() {
        buildMenu(scanning: true)
        runScan()
    }

    // MARK: - Cleaning

    @objc private func cleanTarget(_ sender: NSMenuItem) {
        guard let targetID = sender.representedObject as? String,
              let target = currentResult?.targets.first(where: { $0.id == targetID }) else { return }
        confirmAndClean(target)
    }

    private func confirmAndClean(_ target: CacheTarget) {
        let alert = NSAlert()
        switch target.risk {
        case "risky":
            alert.messageText = "⚠️ Permanently delete \(target.label)?"
            alert.informativeText = "This is marked RISKY and cannot be undone (e.g. archives, backups, or Trash contents). \(humanBytes(target.bytes)) will be deleted."
            alert.alertStyle = .critical
        case "caution":
            alert.messageText = "Delete \(target.label)?"
            alert.informativeText = "This is safe-ish but not guaranteed lossless — check the description in the dashboard if unsure. \(humanBytes(target.bytes)) will be deleted."
            alert.alertStyle = .warning
        default:
            alert.messageText = "Delete \(target.label)?"
            alert.informativeText = "\(humanBytes(target.bytes)) will be deleted. This is considered safe — the owning tool regenerates it as needed."
            alert.alertStyle = .informational
        }
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DiskScanner.clean(targetID: target.id) { [weak self] outcome in
            self?.showCleanResult(label: target.label, outcome: outcome)
            self?.runScan()
        }
    }

    @objc private func cleanAllSafe() {
        guard let result = currentResult else { return }
        let safeTargets = result.targets.filter { $0.risk == "safe" && $0.bytes > 0 }
        guard !safeTargets.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Clean \(safeTargets.count) safe cache location(s)?"
        alert.informativeText = "Freeing up to \(humanBytes(result.safeReclaimableBytes))."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Clean")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        cleanSequentially(safeTargets, freed: 0, errors: [])
    }

    private func cleanSequentially(_ remaining: [CacheTarget], freed: Int64, errors: [String]) {
        guard let target = remaining.first else {
            showCleanResult(label: "safe caches", outcome: CleanOutcome(freedBytes: freed, errors: errors))
            runScan()
            return
        }
        DiskScanner.clean(targetID: target.id) { [weak self] outcome in
            self?.cleanSequentially(
                Array(remaining.dropFirst()),
                freed: freed + outcome.freedBytes,
                errors: errors + outcome.errors
            )
        }
    }

    private func showCleanResult(label: String, outcome: CleanOutcome) {
        let notification = NSUserNotificationCenter.default
        let note = NSUserNotification()
        note.title = "Dev Disk Cleanup"
        note.informativeText = outcome.ok
            ? "Freed \(humanBytes(outcome.freedBytes)) from \(label)."
            : "Freed \(humanBytes(outcome.freedBytes)) from \(label), with \(outcome.errors.count) error(s)."
        notification.deliver(note)
    }
}
