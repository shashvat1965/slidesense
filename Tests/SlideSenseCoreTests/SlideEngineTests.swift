import CoreGraphics
import XCTest
@testable import SlideSenseCore

private final class Recorder: SlideEngineDelegate {
    var begins: [EdgeAction] = []
    var updates: [(EdgeAction, Double)] = []
    var ends: [(EdgeAction, Double)] = []
    var ticks: [(EdgeAction, Double)] = []
    var commands: [MediaCommand] = []

    func slideEngine(_ engine: SlideEngine, didBeginSlide target: EdgeAction) {
        begins.append(target)
    }

    func slideEngine(_ engine: SlideEngine, didUpdateSlide target: EdgeAction, level: Double) {
        updates.append((target, level))
    }

    func slideEngine(_ engine: SlideEngine, didEndSlide target: EdgeAction, level: Double) {
        ends.append((target, level))
    }

    func slideEngine(_ engine: SlideEngine, didTick target: EdgeAction, level: Double) {
        ticks.append((target, level))
    }

    func slideEngine(_ engine: SlideEngine, didRecognize command: MediaCommand) {
        commands.append(command)
    }
}

final class SlideEngineTests: XCTestCase {
    private func makeEngine(_ configure: (inout EngineConfiguration) -> Void = { _ in }) -> (SlideEngine, Recorder) {
        let engine = SlideEngine()
        var config = EngineConfiguration()
        config.mediaStripEnabled = true
        configure(&config)
        engine.configuration = { config }
        engine.modifiers = { [] }
        let recorder = Recorder()
        engine.delegate = recorder
        return (engine, recorder)
    }

    private func frame(at time: TimeInterval, x: Double, y: Double, touching: Bool = true, id: Int32 = 1) -> TouchFrame {
        TouchFrame(timestamp: time, contacts: [TouchContact(id: id, x: x, y: y, isTouching: touching)])
    }

    func testRightSlideSenseChangesVolume() {
        var config = EngineConfiguration()
        config.currentVolume = 0.5
        let (engine, recorder) = makeEngine { $0 = config }

        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.4))
        engine.process(frame(at: 0.04, x: 0.95, y: 0.6))

        XCTAssertEqual(recorder.begins, [.volume])
        XCTAssertGreaterThan(recorder.updates.last?.1 ?? 0, 0.5)
        XCTAssertEqual(recorder.ends.count, 0) // still touching
    }

    func testLeftSlideSenseChangesBrightness() {
        var config = EngineConfiguration()
        config.currentBrightness = 0.5
        let (engine, recorder) = makeEngine { $0 = config }

        engine.process(frame(at: 0.0, x: 0.05, y: 0.8))
        engine.process(frame(at: 0.02, x: 0.05, y: 0.6))

        XCTAssertEqual(recorder.begins, [.brightness])
        XCTAssertEqual(recorder.updates.last?.1 ?? 1, 0.25, accuracy: 0.001)
    }

    func testMiddleTouchIsIgnored() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.5, y: 0.5))
        engine.process(frame(at: 0.02, x: 0.55, y: 0.55))
        XCTAssertTrue(recorder.begins.isEmpty)
        XCTAssertTrue(recorder.updates.isEmpty)
    }

    func testSlideEndsWhenFingerMovesIntoMiddle() {
        for (edgeX, target) in [(0.05, EdgeAction.brightness), (0.95, .volume)] {
            let (engine, recorder) = makeEngine()
            engine.process(frame(at: 0, x: edgeX, y: 0.3))
            engine.process(frame(at: 0.02, x: edgeX, y: 0.45))
            XCTAssertTrue(engine.isTrackingSlide)
            let lastLevel = recorder.updates.last?.1

            engine.process(frame(at: 0.04, x: 0.5, y: 0.6))
            XCTAssertFalse(engine.isTrackingSlide)
            engine.process(frame(at: 0.06, x: 0.5, y: 0.7))
            engine.process(TouchFrame(timestamp: 0.07, contacts: []))
            engine.process(frame(at: 0.08, x: edgeX, y: 0.8))
            engine.process(frame(at: 0.10, x: edgeX, y: 0.9))

            XCTAssertEqual(recorder.begins, [target])
            XCTAssertEqual(recorder.updates.count, 1)
            XCTAssertEqual(recorder.ends.map(\.0), [target])
            XCTAssertEqual(recorder.ends.last?.1, lastLevel)
        }
    }

    func testVerticalMotionInMiddleNeverAdjustsLevels() {
        for width in [0.1, 0.18] {
            for x in stride(from: width + 0.01, through: 1 - width - 0.01, by: 0.05) {
                let (engine, recorder) = makeEngine { $0.edgeWidth = width }
                for (index, y) in [0.3, 0.5, 0.7, 0.5, 0.3].enumerated() {
                    engine.process(frame(at: Double(index) * 0.02, x: x, y: y))
                    XCTAssertFalse(engine.isTrackingSlide, "x=\(x), y=\(y), width=\(width)")
                }
                XCTAssertTrue(recorder.begins.isEmpty)
                XCTAssertTrue(recorder.updates.isEmpty)
                XCTAssertTrue(recorder.ticks.isEmpty)
            }
        }
    }

    func testSlideEndsAboveBottomQuarter() {
        for (x, target) in [(0.05, EdgeAction.brightness), (0.95, .volume)] {
            let (engine, recorder) = makeEngine { $0.bottomQuarterOnly = true }
            engine.process(frame(at: 0, x: x, y: 0.1))
            engine.process(frame(at: 0.02, x: x, y: 0.2))
            XCTAssertTrue(engine.isTrackingSlide)
            let updateCount = recorder.updates.count

            engine.process(frame(at: 0.04, x: x, y: 0.26))
            XCTAssertFalse(engine.isTrackingSlide)
            engine.process(frame(at: 0.06, x: x, y: 0.5))
            engine.process(frame(at: 0.08, x: x, y: 0.2))

            XCTAssertEqual(recorder.updates.count, updateCount)
            XCTAssertEqual(recorder.begins, [target])
            XCTAssertEqual(recorder.ends.map(\.0), [target])
        }
    }

    func testSideSlideEndsWhenBottomStripBecomesNearestEdge() {
        for (x, target) in [(0.15, EdgeAction.brightness), (0.85, .volume)] {
            let (engine, recorder) = makeEngine()
            engine.process(frame(at: 0, x: x, y: 0.5))
            engine.process(frame(at: 0.02, x: x, y: 0.4))
            XCTAssertTrue(engine.isTrackingSlide)
            let updateCount = recorder.updates.count

            engine.process(frame(at: 0.04, x: x, y: 0.02))
            XCTAssertFalse(engine.isTrackingSlide)
            engine.process(frame(at: 0.06, x: x, y: 0.01))
            engine.process(frame(at: 0.08, x: x, y: 0.4))

            XCTAssertEqual(recorder.updates.count, updateCount)
            XCTAssertEqual(recorder.begins, [target])
            XCTAssertEqual(recorder.ends.map(\.0), [target])
            XCTAssertTrue(recorder.commands.isEmpty)
        }
    }

    func testQuickMuteCornerCannotStartSlideOutsideBottomQuarter() {
        let (engine, recorder) = makeEngine { $0.bottomQuarterOnly = true }
        engine.process(frame(at: 0, x: 0.95, y: 0.95))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.8))
        engine.process(frame(at: 0.04, x: 0.95, y: 0.7))

        XCTAssertFalse(engine.isTrackingSlide)
        XCTAssertTrue(recorder.begins.isEmpty)
        XCTAssertTrue(recorder.updates.isEmpty)
    }

    func testNewContactDoesNotInheritSlide() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0, x: 0.95, y: 0.3))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.45))
        engine.process(TouchFrame(timestamp: 0.03, contacts: []))
        XCTAssertTrue(engine.isTrackingSlide)

        engine.process(frame(at: 0.04, x: 0.5, y: 0.6, id: 2))
        engine.process(frame(at: 0.06, x: 0.95, y: 0.8, id: 2))

        XCTAssertFalse(engine.isTrackingSlide)
        XCTAssertEqual(recorder.begins, [.volume])
        XCTAssertEqual(recorder.updates.count, 1)
        XCTAssertEqual(recorder.ends.count, 1)
    }

    func testSecondFingerCancelsSlide() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.4))
        let twoFingers = TouchFrame(timestamp: 0.04, contacts: [
            TouchContact(id: 1, x: 0.95, y: 0.5, isTouching: true),
            TouchContact(id: 2, x: 0.5, y: 0.5, isTouching: true)
        ])
        engine.process(twoFingers)
        XCTAssertEqual(recorder.ends.count, 1)
    }

    func testLevelStopsAtBounds() {
        var config = EngineConfiguration()
        config.currentVolume = 0.9
        let (engine, recorder) = makeEngine { $0 = config }
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 1.0))
        XCTAssertEqual(recorder.updates.last?.1 ?? 0, 1.0, accuracy: 0.001)
    }

    func testDoubleTapCornerMutes() {
        let (engine, recorder) = makeEngine()
        for index in 0..<2 {
            let base = Double(index) * 0.2
            engine.process(frame(at: base + 0.00, x: 0.95, y: 0.95))
            engine.process(frame(at: base + 0.05, x: 0.95, y: 0.95))
            engine.process(frame(at: base + 0.08, x: 0.95, y: 0.95, touching: false))
        }
        XCTAssertEqual(recorder.commands, [.mute])
    }

    func testSingleCornerTapDoesNotMute() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.95, y: 0.95))
        engine.process(frame(at: 0.05, x: 0.95, y: 0.95))
        engine.process(frame(at: 0.08, x: 0.95, y: 0.95, touching: false))
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testBottomStripSwipeSendsNext() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.8, y: 0.05))
        engine.process(frame(at: 0.02, x: 0.6, y: 0.05))
        engine.process(frame(at: 0.04, x: 0.4, y: 0.05))
        XCTAssertEqual(recorder.commands, [.next])
    }

    func testBottomStripReverseFlipsDirection() {
        let (engine, recorder) = makeEngine { $0.mediaStripReverse = true }
        engine.process(frame(at: 0.0, x: 0.2, y: 0.05))
        engine.process(frame(at: 0.04, x: 0.6, y: 0.05))
        XCTAssertEqual(recorder.commands, [.next])
    }

    func testDroppedContactKeepsSlideAlive() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.4))
        // One stray frame with no contacts should not end the gesture.
        engine.process(TouchFrame(timestamp: 0.04, contacts: []))
        engine.process(frame(at: 0.05, x: 0.95, y: 0.55))
        XCTAssertEqual(recorder.begins.count, 1)
        XCTAssertEqual(recorder.ends.count, 0)
        XCTAssertGreaterThan(recorder.updates.last?.1 ?? 0, 0.5)
    }

    func testReportedLiftEndsSlideImmediately() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0, x: 0.95, y: 0.3))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.45))
        engine.process(frame(at: 0.04, x: 0.95, y: 0.45, touching: false))

        XCTAssertFalse(engine.isTrackingSlide)
        XCTAssertEqual(recorder.ends.map(\.0), [.volume])

        engine.process(frame(at: 0.06, x: 0.05, y: 0.6))
        engine.process(frame(at: 0.08, x: 0.05, y: 0.75))
        XCTAssertEqual(recorder.begins, [.volume, .brightness])
    }

    func testRepeatedMissingFramesEndSlide() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0, x: 0.95, y: 0.3))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.45))

        for index in 1...5 {
            engine.process(TouchFrame(timestamp: 0.02 + Double(index) * 0.01, contacts: []))
            XCTAssertTrue(engine.isTrackingSlide)
        }
        engine.process(TouchFrame(timestamp: 0.08, contacts: []))

        XCTAssertFalse(engine.isTrackingSlide)
        XCTAssertEqual(recorder.ends.map(\.0), [.volume])
    }

    func testContactReturningAfterGraceStartsFreshSlide() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0, x: 0.95, y: 0.3))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.45))
        engine.process(TouchFrame(timestamp: 0.03, contacts: []))
        engine.process(frame(at: 0.2, x: 0.05, y: 0.6))

        XCTAssertFalse(engine.isTrackingSlide)
        XCTAssertEqual(recorder.ends.map(\.0), [.volume])

        engine.process(frame(at: 0.22, x: 0.05, y: 0.75))
        XCTAssertEqual(recorder.begins, [.volume, .brightness])
    }

    func testFineControlUsesQuarterSteps() {
        var config = EngineConfiguration()
        config.preciseSliding = true
        config.currentVolume = 0.5
        let (engine, recorder) = makeEngine { $0 = config }

        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.25))
        guard let level = recorder.updates.last?.1 else {
            return XCTFail("expected an update")
        }
        // Quarter steps land on multiples of 1/64.
        let scaled = level * 64
        XCTAssertEqual(scaled.rounded(), scaled, accuracy: 0.0001)
    }

    func testRequiredModifierBlocksSlide() {
        let engine = SlideEngine()
        var config = EngineConfiguration()
        config.requireModifier = .option
        engine.configuration = { config }
        engine.modifiers = { [] }
        let recorder = Recorder()
        engine.delegate = recorder

        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.6))
        XCTAssertTrue(recorder.updates.isEmpty)
    }
}
