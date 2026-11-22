import AppKit
import Foundation

public protocol StatusItemDataSource: AnyObject {
    var volumeLevel: Double { get }
    var brightnessLevel: Double { get }
    var isMuted: Bool { get }
    func requestSettings()
    func requestQuit()
}

/// The menu bar item and its menu.
///
/// The menu is deliberately minimal — two live readouts, an enable switch,
/// Settings and Quit — and is built exactly once. `refresh()` only rewrites
/// item titles and state, so it stays cheap when called every second and
/// keeps working while the menu is open.
public final class StatusItemController {
    private let store: SettingsStore
    private weak var dataSource: StatusItemDataSource?

    private var statusItem: NSStatusItem?
    private let menuDelegate = PlainTextMenuDelegate()

    // Menu items whose contents are updated in place by `refresh()`.
    private var volumeItem: NSMenuItem?
    private var brightnessItem: NSMenuItem?
    private var enabledItem: NSMenuItem?

    /// The installed menu, exposed for tests and snapshot tooling.
    var menu: NSMenu? { statusItem?.menu }

    /// Whether the item shows in the menu bar, exposed for tests.
    var isVisible: Bool { statusItem?.isVisible ?? false }

    /// Called just before the menu is displayed, so the app can refresh the
    /// live readouts without a timer running in the background.
    public var willOpen: (() -> Void)? {
        get { menuDelegate.onWillOpen }
        set { menuDelegate.onWillOpen = newValue }
    }

    // MARK: - Status item artwork

    /// 18×18 template artwork: a thin trackpad outline with a short bar
    /// hugging each inner edge. Template images are tinted by the menu bar.
    private static let enabledIcon = StatusItemController.makeIcon(alpha: 1.0)
    private static let disabledIcon = StatusItemController.makeIcon(alpha: 0.42)

    private static func makeIcon(alpha: CGFloat) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let color = NSColor.black.withAlphaComponent(alpha)
            color.setStroke()
            color.setFill()

            let outline = NSBezierPath(
                roundedRect: NSRect(x: 3.25, y: 2.25, width: 11.5, height: 13.5),
                xRadius: 2.75,
                yRadius: 2.75
            )
            outline.lineWidth = 1.5
            outline.stroke()

            let barWidth: CGFloat = 1.5
            let barHeight: CGFloat = 6
            let leftBar = NSRect(x: 4.5, y: 6, width: barWidth, height: barHeight)
            let rightBar = NSRect(x: 12, y: 6, width: barWidth, height: barHeight)
            NSBezierPath(roundedRect: leftBar, xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: rightBar, xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Lifecycle

    public init(store: SettingsStore, dataSource: StatusItemDataSource) {
        self.store = store
        self.dataSource = dataSource

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("SlideSense")
        statusItem = item

        buildMenu()
        refresh()
    }

    // MARK: - Refresh

    /// Cheap update called about once a second and after every settings change.
    /// Never rebuilds the menu, so an open menu keeps its highlight.
    public func refresh() {
        statusItem?.isVisible = store.settings.showMenuBarIcon
        updateButtonAppearance()
        updateReadouts()
        enabledItem?.state = store.settings.enabled ? .on : .off
    }

    private func updateButtonAppearance() {
        guard let button = statusItem?.button else { return }
        let enabled = store.settings.enabled
        let icon = enabled ? Self.enabledIcon : Self.disabledIcon
        if button.image !== icon {
            button.image = icon
        }
        button.toolTip = enabled ? "SlideSense" : "SlideSense (Off)"
    }

    // MARK: - Readouts

    private func updateReadouts() {
        let volume = clamped(dataSource?.volumeLevel ?? 0)
        let brightness = clamped(dataSource?.brightnessLevel ?? 0)
        let muted = dataSource?.isMuted ?? false

        volumeItem?.attributedTitle = readout(
            label: "Volume",
            value: muted ? "Muted" : percent(volume)
        )
        brightnessItem?.attributedTitle = readout(
            label: "Brightness",
            value: percent(brightness)
        )
    }

    /// A menu row with the label on the left and the value right-aligned,
    /// like the informational rows in Apple's own menu extras.
    private func readout(label: String, value: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 190, options: [:])]

        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        let title = NSMutableAttributedString(
            string: "\(label)\t\(value)",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
        if let range = title.string.range(of: value, options: .backwards) {
            title.addAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor,
                range: NSRange(range, in: title.string)
            )
        }
        return title
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", clamped(value) * 100)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    // MARK: - Menu construction

    /// Builds the menu exactly once. Plain text only — no images, no bullets.
    private func buildMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = menuDelegate

        let volume = readoutItem()
        menu.addItem(volume)

        let brightness = readoutItem()
        menu.addItem(brightness)

        menu.addItem(.separator())

        let enabled = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabled.target = self
        menu.addItem(enabled)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = .command
        settings.target = self
        // macOS attaches a gear symbol to items titled like Settings; the
        // menu is text-only by design.
        settings.image = nil
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit SlideSense",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = .command
        quit.target = self
        menu.addItem(quit)

        volumeItem = volume
        brightnessItem = brightness
        enabledItem = enabled
        statusItem.menu = menu

        // AppKit decorates the "Settings…" item with a gear symbol as soon as
        // the menu is installed; clear every image so the menu is text-only.
        for item in menu.items where item.image != nil {
            item.image = nil
        }
    }

    /// A disabled, non-highlighting item used for the live level readouts.
    private func readoutItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.action = nil
        item.target = nil
        return item
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        store.settings.enabled.toggle()
        refresh()
    }

    @objc private func openSettings() {
        dataSource?.requestSettings()
    }

    @objc private func quit() {
        dataSource?.requestQuit()
    }
}

// MARK: - Menu delegate

/// Strips the SF Symbol gear that macOS attaches to items with standard
/// titles such as "Settings…", keeping the menu plain text.
private final class PlainTextMenuDelegate: NSObject, NSMenuDelegate {
    var onWillOpen: (() -> Void)?

    func menuWillOpen(_ menu: NSMenu) {
        onWillOpen?()
        for item in menu.items where item.image != nil {
            item.image = nil
        }
    }
}
