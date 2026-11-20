import XCTest
@testable import SlideSenseCore

final class SystemHUDStepperTests: XCTestCase {
    private let step = 1.0 / Double(SystemHUDStepper.stepsPerRange)

    func testMovementUnderHalfAStepSendsNothing() {
        var stepper = SystemHUDStepper(start: 0.5)
        XCTAssertEqual(stepper.presses(toFollow: 0.5 + step * 0.4), 0)
        XCTAssertEqual(stepper.presses(toFollow: 0.5 - step * 0.4), 0)
    }

    func testOneStepEachWay() {
        var stepper = SystemHUDStepper(start: 0.5)
        XCTAssertEqual(stepper.presses(toFollow: 0.5 + step), 1)
        XCTAssertEqual(stepper.presses(toFollow: 0.5), -1)
        XCTAssertEqual(stepper.presses(toFollow: 0.5 - step), -1)
    }

    /// A slide that goes up and comes back must end with no net key presses.
    func testFollowsBackAndForth() {
        var stepper = SystemHUDStepper(start: 0.5)
        XCTAssertEqual(stepper.presses(toFollow: 0.75), 4)
        XCTAssertEqual(stepper.presses(toFollow: 0.625), -2)
        XCTAssertEqual(stepper.presses(toFollow: 0.5), -2)
        XCTAssertEqual(stepper.sent, 0)
    }

    func testRepeatingTheSameLevelSendsNothing() {
        var stepper = SystemHUDStepper(start: 0.25)
        XCTAssertEqual(stepper.presses(toFollow: 0.5), 4)
        XCTAssertEqual(stepper.presses(toFollow: 0.5), 0)
    }

    func testFullRangeIsSixteenPresses() {
        var up = SystemHUDStepper(start: 0)
        XCTAssertEqual(up.presses(toFollow: 1), 16)
        var down = SystemHUDStepper(start: 1)
        XCTAssertEqual(down.presses(toFollow: 0), -16)
    }

    /// Overshooting the ends never asks for presses beyond the range.
    func testClampsAtTheEnds() {
        var stepper = SystemHUDStepper(start: 0.9)
        XCTAssertEqual(stepper.presses(toFollow: 1.4), 2)
        XCTAssertEqual(stepper.presses(toFollow: 3), 0)
        XCTAssertEqual(stepper.presses(toFollow: -2), -16)
    }

    func testSettingIsOptInAndDecodes() throws {
        XCTAssertFalse(Settings().useSystemHUD)
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"edgeWidth": 0.2}"#.utf8))
        XCTAssertFalse(old.useSystemHUD)
        let on = try JSONDecoder().decode(Settings.self, from: Data(#"{"useSystemHUD": true}"#.utf8))
        XCTAssertTrue(on.useSystemHUD)
    }
}
