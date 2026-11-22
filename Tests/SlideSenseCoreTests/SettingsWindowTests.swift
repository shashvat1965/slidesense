import AppKit
import SwiftUI
import XCTest

@testable import SlideSenseCore

@MainActor
final class SettingsWindowTests: XCTestCase {
    // MARK: - Fixtures

    private struct Fixture {
        let store: SettingsStore
        let defaults: UserDefaults
        let suiteName: String
    }

    private func makeFixture() -> Fixture {
        let suiteName = "SlideSenseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return Fixture(
            store: SettingsStore(defaults: defaults),
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func persistedSettings(_ fixture: Fixture) -> SlideSenseCore.Settings? {
        let domain = fixture.defaults.persistentDomain(forName: fixture.suiteName) ?? [:]
        for value in domain.values {
            guard let data = value as? Data else { continue }
            if let settings = try? JSONDecoder().decode(Settings.self, from: data) {
                return settings
            }
        }
        return nil
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    // MARK: - Window chrome

    func testWindowUsesDocumentedSizeAndChrome() {
        let fixture = makeFixture()
        let controller = SettingsWindowController(store: fixture.store)
        let window = controller.prepareWindow()

        XCTAssertEqual(window.title, "SlideSense Settings")
        let tallest = SettingsWindowController.measuredHeights(
            store: fixture.store,
            permissionState: PermissionState()
        ).map(\.height).max() ?? 0
        XCTAssertEqual(window.contentLayoutRect.size.width, SettingsWindowController.Layout.width)
        XCTAssertEqual(window.contentLayoutRect.size.height, tallest.rounded(.up))

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.styleMask.contains(.miniaturizable))

        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertEqual(window.tabbingMode, .disallowed)
    }

    // MARK: - Tab sizing

    func testEveryTabFitsWithoutClipping() {
        let fixture = makeFixture()
        let permissionState = PermissionState(isTrusted: true)
        let controller = SettingsWindowController(store: fixture.store)
        let window = controller.prepareWindow()

        let contentHeight = window.contentLayoutRect.height

        for tab in SettingsTab.allCases {
            controller.selectTab(tab)
            XCTAssertEqual(controller.selectedTab, tab)

            let height = SettingsWindowController.fittingHeight(
                of: tab,
                store: fixture.store,
                permissionState: permissionState
            )
            XCTAssertLessThanOrEqual(
                height,
                contentHeight + 0.5,
                "\(tab.rawValue) needs \(height) pt but the window only offers \(contentHeight) pt"
            )
        }
    }

    func testSelectionBindingDrivesTabView() {
        let fixture = makeFixture()
        let controller = SettingsWindowController(store: fixture.store)
        _ = controller.prepareWindow()

        for tab in SettingsTab.allCases {
            controller.selectTab(tab)
            XCTAssertEqual(controller.selectedTab, tab)
        }
        XCTAssertEqual(SettingsTab.allCases.map(\.title), ["Edges", "Feel", "Media", "Startup", "General"])
    }

    // MARK: - Permissions

    func testPermissionStateRefreshFlipsWithInjectedState() {
        final class Stub {
            var trusted = false
        }
        let stub = Stub()
        let state = PermissionState(provider: { stub.trusted })

        XCTAssertFalse(state.isTrusted)

        stub.trusted = true
        state.refresh()
        XCTAssertTrue(state.isTrusted)

        stub.trusted = false
        state.refresh()
        XCTAssertFalse(state.isTrusted)
    }

    // MARK: - Store write-through

    func testSettingsControlsWriteThroughToStore() throws {
        let fixture = makeFixture()
        let store = fixture.store
        var changed = SlideSenseCore.Settings()

        changed.sensitivity = 2.35
        changed.swapped = true
        changed.requireModifier = .option
        changed.hapticsEnabled = false
        changed.mediaStripEnabled = false
        changed.openAtLogin = true

        store.settings = changed

        XCTAssertEqual(store.settings.leftEdge, .volume)
        XCTAssertEqual(store.settings.rightEdge, .brightness)

        let persisted = try XCTUnwrap(persistedSettings(fixture), "Settings were not written to the defaults store")
        XCTAssertEqual(persisted, changed)
        XCTAssertEqual(persisted.sensitivity, 2.35)
        XCTAssertEqual(persisted.leftEdge, .volume)
        XCTAssertEqual(persisted.rightEdge, .brightness)
        XCTAssertEqual(persisted.requireModifier, .option)
        XCTAssertFalse(persisted.hapticsEnabled)
        XCTAssertFalse(persisted.mediaStripEnabled)
        XCTAssertTrue(persisted.openAtLogin)
    }

    func testSwappedTogglePersistsBothEdges() throws {
        let fixture = makeFixture()
        fixture.store.settings.swapped = true
        XCTAssertEqual(fixture.store.settings.leftEdge, .volume)
        XCTAssertEqual(fixture.store.settings.rightEdge, .brightness)

        fixture.store.settings.swapped = false
        XCTAssertEqual(fixture.store.settings.leftEdge, .brightness)
        XCTAssertEqual(fixture.store.settings.rightEdge, .volume)

        let persisted = try XCTUnwrap(persistedSettings(fixture))
        XCTAssertEqual(persisted.leftEdge, .brightness)
        XCTAssertEqual(persisted.rightEdge, .volume)
    }

    // MARK: - Snapshots

    func testWritesSnapshotsWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["SLIDESENSE_SNAPSHOT_DIR"] else {
            throw XCTSkip("SLIDESENSE_SNAPSHOT_DIR is not set")
        }

        let fixture = makeFixture()
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let controller = SettingsWindowController(store: fixture.store)
        let window = controller.prepareWindow()
        window.isReleasedWhenClosed = false
        // Keep the window off-screen: rendering needs a real window for the
        // grouped Form and its visual-effect backdrop, but nobody should see it.
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        let size = window.contentLayoutRect.size
        let scale: CGFloat = 2

        for tab in SettingsTab.allCases {
            controller.selectTab(tab)

            for (appearance, suffix) in [
                (NSAppearance.Name.aqua, "light"),
                (NSAppearance.Name.darkAqua, "dark")
            ] {
                window.appearance = NSAppearance(named: appearance)
                window.layoutIfNeeded()

                guard let hosting = window.contentView else {
                    return XCTFail("Window has no hosted content view")
                }
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()

                guard let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(size.width * scale),
                    pixelsHigh: Int(size.height * scale),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                ) else {
                    return XCTFail("Could not create bitmap for \(tab.rawValue)")
                }
                rep.size = size
                hosting.cacheDisplay(in: hosting.bounds, to: rep)

                guard let png = rep.representation(using: .png, properties: [:]) else {
                    return XCTFail("Could not encode PNG for \(tab.rawValue)")
                }
                let url = base.appendingPathComponent("settings-\(tab.rawValue)-\(suffix).png")
                try png.write(to: url)

                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                XCTAssertEqual(rep.pixelsWide, Int(size.width * scale))
                XCTAssertEqual(rep.pixelsHigh, Int(size.height * scale))
            }
        }
    }

    /// Renders the granted state of the General tab, which the normal pass
    /// cannot reach without Accessibility being granted on the test machine.
    func testWritesGrantedPermissionSnapshot() throws {
        guard let directory = ProcessInfo.processInfo.environment["SLIDESENSE_SNAPSHOT_DIR"] else {
            throw XCTSkip("SLIDESENSE_SNAPSHOT_DIR is not set")
        }

        let fixture = makeFixture()
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let controller = SettingsWindowController(
            store: fixture.store,
            permissionState: PermissionState(isTrusted: true)
        )
        let window = controller.prepareWindow()
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        controller.selectTab(.general)
        window.appearance = NSAppearance(named: .darkAqua)
        window.layoutIfNeeded()

        guard let hosting = window.contentView else {
            return XCTFail("Window has no hosted content view")
        }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let size = window.contentLayoutRect.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return XCTFail("Could not create bitmap")
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not encode PNG")
        }
        let url = base.appendingPathComponent("settings-general-granted-dark.png")
        try png.write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
