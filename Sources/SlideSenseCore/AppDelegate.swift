import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator(store: .shared)
        self.coordinator = coordinator
        coordinator.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    /// Opening the running app again (Finder, Spotlight, Launchpad) shows
    /// Settings, which is the way back when the menu bar icon is hidden.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.requestSettings()
        return false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
