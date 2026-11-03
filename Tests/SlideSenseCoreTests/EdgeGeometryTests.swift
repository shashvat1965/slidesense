import CoreGraphics
import XCTest
@testable import SlideSenseCore

final class EdgeGeometryTests: XCTestCase {
    func testDetectsEachEdge() {
        let geometry = EdgeGeometry(edgeWidth: 0.2)
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.05, y: 0.5)), .left)
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.95, y: 0.5)), .right)
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.5, y: 0.05)), .bottom)
        XCTAssertNil(geometry.edge(at: CGPoint(x: 0.5, y: 0.5)))
    }

    func testCornerPicksNearestEdge() {
        let geometry = EdgeGeometry(edgeWidth: 0.2)
        // Bottom-left corner: closer to the bottom (y = 0.02) than the left (x = 0.15).
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.15, y: 0.02)), .bottom)
        // Bottom-right corner: closer to the right.
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.99, y: 0.02)), .right)
    }

    func testBottomQuarterOnlyLimitsSideEdges() {
        let geometry = EdgeGeometry(edgeWidth: 0.2, bottomQuarterOnly: true)
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.05, y: 0.1)), .left)
        XCTAssertNil(geometry.edge(at: CGPoint(x: 0.05, y: 0.7)))
    }

    func testQuickMuteBandCoversTopSixteenPercentAcrossFullWidth() {
        let geometry = EdgeGeometry()
        for x in [0.0, 0.5, 1.0] {
            XCTAssertTrue(geometry.isQuickMuteBand(CGPoint(x: x, y: 0.84)))
            XCTAssertFalse(geometry.isQuickMuteBand(CGPoint(x: x, y: 0.839)))
        }
        XCTAssertFalse(geometry.isQuickMuteBand(CGPoint(x: -0.01, y: 0.95)))
        XCTAssertFalse(geometry.isQuickMuteBand(CGPoint(x: 0.5, y: 1.01)))
    }

    func testOutOfRangePointsAreIgnored() {
        let geometry = EdgeGeometry()
        XCTAssertNil(geometry.edge(at: CGPoint(x: -0.2, y: 0.5)))
        XCTAssertNil(geometry.edge(at: CGPoint(x: 0.5, y: 1.4)))
    }
}
