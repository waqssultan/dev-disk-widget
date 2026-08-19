# DevDiskWidget

A macOS menu bar app + Desktop widget (WidgetKit) that shows disk usage and
lets you clean common developer-tool caches: Xcode/iOS, Android Studio/
GoLand/Gradle, package managers (Homebrew, npm, Go), and general macOS
"system junk" (caches, logs, Trash).

Covers the same ground as a companion HTML dashboard, packaged as a native
menu bar app + Desktop widget instead of a local web page.

## Install (one command, per machine)

```bash
git clone https://github.com/waqssultan/dev-disk-widget/edit/main DevDiskWidget
cd DevDiskWidget
./install.sh
```

This builds the app **locally on your Mac** (ad-hoc "Sign to Run Locally"
signing — no Apple ID or paid developer account needed) and installs it to
`/Applications/DevDiskApp.app`. Building locally, rather than downloading a
prebuilt binary, is what avoids Gatekeeper quarantine warnings.

Requirements: Xcode (or at least the Command Line Tools) and Homebrew.
The script installs `xcodegen` via Homebrew automatically if it's missing.

## What you get

- A menu bar icon (🗄) showing free space; click it for a breakdown by
  category and per-target "Clean…" actions (confirmed before deleting
  anything, color-coded by risk: safe / caution / risky).
- A "Dev Disk Cleanup" Desktop widget (small/medium/large) — add it via
  **right-click Desktop → Edit Widgets → search "Dev Disk Cleanup"**.
- "Rescan Now" (⌘R) and a 30-minute automatic rescan.

## Updating

```bash
cd DevDiskWidget
git pull
./install.sh
```

## Project layout

- `Shared/` — scanning/cleaning logic (`DiskScanner.swift`) and the on-disk
  JSON snapshot format shared between the app and the widget
  (`SharedStore.swift`, `Models.swift`).
- `DevDiskApp/` — the menu bar app (`LSUIElement`, no Dock icon). Runs the
  scan periodically, writes the snapshot, triggers widget reloads.
- `DevDiskWidget/` — the WidgetKit extension. Only reads the snapshot the
  app already wrote (no subprocess calls here — WidgetKit budgets timeline
  generation strictly).
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec;
  `install.sh` runs `xcodegen generate` to produce the `.xcodeproj` (not
  committed — it's generated).

## Notes / design choices

- No App Sandbox and no App Groups: since this isn't distributed via the
  Mac App Store, sandboxing is optional, so the app and the widget just
  share a plain JSON file at
  `~/Library/Application Support/DevDiskWidget/scan.json` instead of
  needing an App Group entitlement (which would require a paid team).
- The cache/target list is kept in sync by hand with the companion HTML
  dashboard's `server.py` — if you add a target there, add it to
  `Shared/DiskScanner.swift` too.


  Design: 

  <img width="475" height="38" alt="Screenshot 2026-08-19 at 3 48 32 PM" src="https://github.com/user-attachments/assets/fedd32ed-9b44-4383-9a1c-0d9899ae1039" />
<img width="396" height="375" alt="Screenshot 2026-08-19 at 3 48 24 PM" src="https://github.com/user-attachments/assets/3f26c4a7-b4ec-4c01-8df3-36a0c02f6bab" />

