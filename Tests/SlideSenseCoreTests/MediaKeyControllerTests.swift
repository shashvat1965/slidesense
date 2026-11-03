import AppKit
import XCTest
@testable import SlideSenseCore

final class MediaKeyControllerTests: XCTestCase {
    func testPlayPausePostsMatchingPressAndRelease() throws {
        var events: [CGEvent] = []
        let controller = MediaKeyController(sendPlayPause: { false }, postEvent: { events.append($0) })
        controller.send(.playPause)

        XCTAssertEqual(events.count, 2)
        for (event, state) in zip(events, [0xA, 0xB]) {
            let native = try XCTUnwrap(NSEvent(cgEvent: event))
            XCTAssertEqual(native.type, .systemDefined)
            XCTAssertEqual(native.subtype.rawValue, 8)
            XCTAssertEqual(native.data1 >> 16, 16)
            XCTAssertEqual(native.data1 & 0xFF00, state << 8)
            XCTAssertEqual(Int(event.flags.rawValue) & 0xFF00, state << 8)
        }
    }

    func testAcceptedPlaybackCommandDoesNotAlsoPostMediaKey() {
        var commands = 0
        var events: [CGEvent] = []
        let controller = MediaKeyController(
            sendPlayPause: { commands += 1; return true },
            postEvent: { events.append($0) }
        )

        controller.send(.playPause)

        XCTAssertEqual(commands, 1)
        XCTAssertTrue(events.isEmpty)
    }
}
