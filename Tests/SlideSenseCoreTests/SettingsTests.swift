import XCTest
@testable import SlideSenseCore

final class SettingsTests: XCTestCase {
    func testRoundTrip() throws {
        var settings = Settings()
        settings.leftEdge = .volume
        settings.rightEdge = .brightness
        settings.edgeWidth = 0.24
        settings.sensitivity = 1.75
        settings.requireModifier = .option
        settings.hapticsEnabled = false
        settings.hapticStrength = .strong
        settings.mediaStripReverse = true
        settings.appearance = .dark

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    /// Old settings files must keep working: unknown future keys are ignored and
    /// missing keys fall back to defaults instead of failing to decode.
    func testForgivingDecoding() throws {
        let json = #"{"edgeWidth": 0.3, "somethingFromTheFuture": true}"#
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        let defaults = Settings()

        XCTAssertEqual(decoded.edgeWidth, 0.3)
        XCTAssertEqual(decoded.leftEdge, defaults.leftEdge)
        XCTAssertEqual(decoded.rightEdge, defaults.rightEdge)
        XCTAssertEqual(decoded.hapticsEnabled, defaults.hapticsEnabled)
        XCTAssertTrue(decoded.ignoreWhileTyping)
        XCTAssertTrue(decoded.palmRejection)
        XCTAssertTrue(decoded.bottomQuarterOnly)
    }

    /// Someone who saved Bottom Quarter Only = off keeps it off after upgrading.
    func testSavedBottomQuarterChoiceIsKept() throws {
        let json = #"{"bottomQuarterOnly": false}"#
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.bottomQuarterOnly)
    }

    func testSwappedReadsAndWritesBothEdges() {
        var settings = Settings()
        XCTAssertFalse(settings.swapped)

        settings.swapped = true
        XCTAssertEqual(settings.leftEdge, .volume)
        XCTAssertEqual(settings.rightEdge, .brightness)
        XCTAssertTrue(settings.swapped)

        settings.swapped = false
        XCTAssertEqual(settings.leftEdge, .brightness)
        XCTAssertEqual(settings.rightEdge, .volume)
    }

    func testActionForEdge() {
        var settings = Settings()
        settings.leftEdge = .brightness
        settings.rightEdge = .volume

        XCTAssertEqual(settings.action(for: .left), .brightness)
        XCTAssertEqual(settings.action(for: .right), .volume)
        XCTAssertNil(settings.action(for: .bottom))
    }

    func testStorePersistsAcrossInstances() throws {
        let suiteName = "io.github.slidesense.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.settings.sensitivity = 2.1
        store.settings.mediaStripEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.sensitivity, 2.1)
        XCTAssertFalse(reloaded.settings.mediaStripEnabled)
    }

    func testResetToDefaults() throws {
        let suiteName = "io.github.slidesense.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.settings.edgeWidth = 0.4
        store.resetToDefaults()

        XCTAssertEqual(store.settings, Settings())
    }

    func testSettingsChangePostsNotification() throws {
        let suiteName = "io.github.slidesense.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let expectation = expectation(forNotification: .slideSenseSettingsDidChange, object: store)
        store.settings.sensitivity = 1.2
        wait(for: [expectation], timeout: 1)
    }
}
