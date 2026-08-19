import SwiftUI

@main
struct DevDiskAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — this is a pure menu-bar (LSUIElement) app. All UI
        // lives in AppDelegate's NSStatusItem menu.
        Settings {
            EmptyView()
        }
    }
}
