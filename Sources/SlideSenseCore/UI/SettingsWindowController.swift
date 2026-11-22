import AppKit
import SwiftUI

/// Holds the settings window's state outside of SwiftUI so the app can drive
/// the tab selection programmatically.
final class SettingsWindowModel: ObservableObject {
    @Published var selection: SettingsTab = .edges
}

/// Root of the hosted tree. It observes the window model so that
/// `selectTab(_:)` from outside SwiftUI re-renders the tab view, while
/// `SettingsView` itself keeps the plain `@Binding` API.
private struct SettingsRootView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permissionState: PermissionState
    @ObservedObject var model: SettingsWindowModel

    var body: some View {
        SettingsView(
            store: store,
            permissionState: permissionState,
            selection: $model.selection
        )
    }
}

/// Hosts the SwiftUI settings window.
public final class SettingsWindowController {
    enum Layout {
        static let width: CGFloat = 540

        /// Space between the tab view and the window's edges.
        static let margin: CGFloat = 20

        static let autosaveName = "SlideSenseSettingsWindow"
    }

    private let store: SettingsStore
    private let permissionState: PermissionState
    private let model = SettingsWindowModel()
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsRootView>?

    // MARK: - Lifecycle

    public init(store: SettingsStore) {
        self.store = store
        self.permissionState = PermissionState()
    }

    /// Injection point for tests and snapshots (e.g. to render the granted state).
    init(store: SettingsStore, permissionState: PermissionState) {
        self.store = store
        self.permissionState = permissionState
    }

    // MARK: - Presentation

    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        store.settings.hasCompletedSetup = true
        permissionState.refresh()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Selects a tab, creating the window if needed. Used by the app's
    /// snapshot tooling and by deep links from the menu.
    public func selectTab(_ tab: SettingsTab) {
        if window == nil {
            window = makeWindow()
        }
        model.selection = tab
    }

    /// Called by the coordinator so the window can update the permission row.
    public func refreshPermissionState() {
        permissionState.refresh()
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(
            store: store,
            permissionState: permissionState,
            model: model
        )
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        hostingController = hosting

        let size = NSSize(width: Layout.width, height: measuredHeight())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SlideSense Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.setContentSize(size)
        window.tabbingMode = .disallowed

        // Restore the last position, otherwise centre on the first show.
        let restored = window.setFrameUsingName(Layout.autosaveName)
        _ = window.setFrameAutosaveName(Layout.autosaveName)
        if !restored {
            window.center()
        }

        return window
    }

    // MARK: - Measurement

    /// Fitting height of the whole window content with each tab selected, at
    /// the shared window width. The window takes the tallest, so it never
    /// changes size when the user switches tabs (the Apple anti-pattern) and
    /// no tab is clipped. Exposed so the tests can check that.
    static func measuredHeights(
        store: SettingsStore,
        permissionState: PermissionState
    ) -> [(tab: SettingsTab, height: CGFloat)] {
        SettingsTab.allCases.map { tab in
            (tab, fittingHeight(of: tab, store: store, permissionState: permissionState))
        }
    }

    static func fittingHeight(
        of tab: SettingsTab,
        store: SettingsStore,
        permissionState: PermissionState
    ) -> CGFloat {
        // Pinning the width is what makes this useful: without it SwiftUI
        // reports the form's natural width (wider than the window) and the
        // footnotes would not be wrapped, so the height would come out short.
        //
        // The whole TabView, not only the tab's form: depending on the macOS
        // version the tab strip takes content height, and text metrics change
        // too, so no fixed height fits every release.
        let view = SettingsView(
            store: store,
            permissionState: permissionState,
            selection: .constant(tab)
        )
        .frame(width: Layout.width)
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    /// The window height: the tallest tab.
    private func measuredHeight() -> CGFloat {
        Self.measuredHeights(store: store, permissionState: permissionState)
            .map(\.height)
            .max()?
            .rounded(.up) ?? 0
    }

    // MARK: - Testing hooks

    /// Creates the window without ordering it on screen.
    func prepareWindow() -> NSWindow {
        if let window { return window }
        let window = makeWindow()
        self.window = window
        return window
    }

    var selectedTab: SettingsTab { model.selection }
}
