import AppKit
import XCTest
@testable import SlideSenseCore

final class StatusItemTests: XCTestCase {
    private final class StubSource: StatusItemDataSource {
        var volumeLevel: Double = 0.81
        var brightnessLevel: Double = 0.69
        var isMuted = false

        private(set) var settingsRequests = 0
        private(set) var quitRequests = 0

        func requestSettings() { settingsRequests += 1 }
        func requestQuit() { quitRequests += 1 }
    }

    private var store: SettingsStore!
    private var source: StubSource!

    override func setUp() {
        super.setUp()
        let suiteName = "io.github.slidesense.statusitem.\(UUID().uuidString)"
        store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        source = StubSource()
    }

    private func makeController() -> StatusItemController {
        StatusItemController(store: store, dataSource: source)
    }

    private func items(_ controller: StatusItemController) -> [NSMenuItem] {
        controller.menu?.items ?? []
    }

    // MARK: - Structure

    func testMenuIsMinimalAndOrdered() {
        let controller = makeController()
        let items = items(controller)

        XCTAssertEqual(items.count, 7)
        XCTAssertTrue(items[0].title.hasPrefix("Volume"))
        XCTAssertTrue(items[1].title.hasPrefix("Brightness"))
        XCTAssertTrue(items[2].isSeparatorItem)
        XCTAssertEqual(items[3].title, "Enabled")
        XCTAssertEqual(items[4].title, "Settings…")
        XCTAssertTrue(items[5].isSeparatorItem)
        XCTAssertEqual(items[6].title, "Quit SlideSense")
    }

    func testReadoutItemsAreDisabledAndPlain() {
        let controller = makeController()
        let menuItems = items(controller)
        let volume = menuItems[0]
        let brightness = menuItems[1]

        for item in [volume, brightness] {
            XCTAssertFalse(item.isEnabled)
            XCTAssertNil(item.image)
            XCTAssertNil(item.action)
            let text = item.attributedTitle?.string ?? ""
            XCTAssertFalse(text.isEmpty)
        }
        XCTAssertTrue(volume.attributedTitle?.string.contains("Volume") ?? false)
        XCTAssertTrue(volume.attributedTitle?.string.contains("81%") ?? false)
        XCTAssertTrue(brightness.attributedTitle?.string.contains("69%") ?? false)
    }

    func testMenuHasNoImagesAnywhere() {
        let controller = makeController()
        for item in items(controller) {
            XCTAssertNil(item.image, "\(item.title) should not carry an image")
        }
    }

    func testKeyEquivalents() {
        let controller = makeController()
        let menuItems = items(controller)
        let settings = menuItems.first { $0.title == "Settings…" }
        let quit = menuItems.first { $0.title == "Quit SlideSense" }

        XCTAssertEqual(settings?.keyEquivalent, ",")
        XCTAssertEqual(settings?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(quit?.keyEquivalent, "q")
        XCTAssertEqual(quit?.keyEquivalentModifierMask, .command)
    }

    // MARK: - State

    func testEnabledCheckmarkFollowsSettings() {
        let controller = makeController()
        let enabled = items(controller).first { $0.title == "Enabled" }
        XCTAssertEqual(enabled?.state, .on)

        store.settings.enabled = false
        controller.refresh()
        XCTAssertEqual(enabled?.state, .off)

        store.settings.enabled = true
        controller.refresh()
        XCTAssertEqual(enabled?.state, .on)
    }

    func testMenuBarIconFollowsSettings() {
        let controller = makeController()
        XCTAssertTrue(controller.isVisible)

        store.settings.showMenuBarIcon = false
        controller.refresh()
        XCTAssertFalse(controller.isVisible)

        store.settings.showMenuBarIcon = true
        controller.refresh()
        XCTAssertTrue(controller.isVisible)
    }

    func testMutedReadout() {
        let controller = makeController()
        source.isMuted = true
        controller.refresh()
        let volume = items(controller)[0]
        XCTAssertTrue(volume.attributedTitle?.string.contains("Muted") ?? false)
    }

    func testReadoutsClampOutOfRangeValues() {
        let controller = makeController()
        source.volumeLevel = 1.4
        source.brightnessLevel = -0.3
        controller.refresh()

        let menuItems = items(controller)
        XCTAssertTrue(menuItems[0].attributedTitle?.string.contains("100%") ?? false)
        XCTAssertTrue(menuItems[1].attributedTitle?.string.contains("0%") ?? false)
    }

    func testRefreshKeepsTheSameMenuObject() {
        let controller = makeController()
        let first = controller.menu
        controller.refresh()
        XCTAssertTrue(controller.menu === first, "refresh must not rebuild the menu")
    }

    // MARK: - Actions

    func testSettingsAndQuitRouteToTheDataSource() {
        let controller = makeController()
        let menuItems = items(controller)

        let settings = menuItems.first { $0.title == "Settings…" }
        XCTAssertNotNil(settings?.target)
        _ = settings?.target?.perform(settings?.action, with: settings)
        XCTAssertEqual(source.settingsRequests, 1)

        let quit = menuItems.first { $0.title == "Quit SlideSense" }
        XCTAssertNotNil(quit?.target)
        _ = quit?.target?.perform(quit?.action, with: quit)
        XCTAssertEqual(source.quitRequests, 1)
    }
}
