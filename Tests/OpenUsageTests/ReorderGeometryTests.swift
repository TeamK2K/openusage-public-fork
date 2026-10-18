import CoreGraphics
import XCTest
@testable import OpenUsage

final class ReorderGeometryTests: XCTestCase {
    func testFrameStoreSharesLatestSlideGeometryWithExistingDragConsumers() {
        let frameStore = ReorderFrameStore()
        let dragConsumer = frameStore
        frameStore.frames = [
            "dragged": CGRect(x: 0, y: 0, width: 100, height: 40),
            "target": CGRect(x: 0, y: 40, width: 100, height: 40)
        ]

        XCTAssertEqual(reorderTarget(
            at: CGPoint(x: 20, y: 48),
            in: dragConsumer.frames,
            excluding: "dragged",
            orderedIDs: ["dragged", "target"]
        ), "target")

        frameStore.frames = [
            "dragged": CGRect(x: 160, y: 0, width: 100, height: 40),
            "target": CGRect(x: 160, y: 40, width: 100, height: 40)
        ]

        XCTAssertNil(reorderTarget(
            at: CGPoint(x: 20, y: 48),
            in: dragConsumer.frames,
            excluding: "dragged",
            orderedIDs: ["dragged", "target"]
        ))
        XCTAssertEqual(reorderTarget(
            at: CGPoint(x: 180, y: 48),
            in: dragConsumer.frames,
            excluding: "dragged",
            orderedIDs: ["dragged", "target"]
        ), "target")
    }

    func testCrossingThresholdWhenDraggingDown() {
        let frames = [
            "dragged": CGRect(x: 0, y: 0, width: 100, height: 40),
            "target": CGRect(x: 0, y: 40, width: 100, height: 40)
        ]

        XCTAssertNil(reorderTarget(
            at: CGPoint(x: 20, y: 44),
            in: frames,
            excluding: "dragged",
            orderedIDs: ["dragged", "target"]
        ))
        XCTAssertEqual(reorderTarget(
            at: CGPoint(x: 20, y: 48),
            in: frames,
            excluding: "dragged",
            orderedIDs: ["dragged", "target"]
        ), "target")
    }

    func testCrossingThresholdWhenDraggingUp() {
        let frames = [
            "above": CGRect(x: 0, y: 0, width: 100, height: 40),
            "divider": CGRect(x: 0, y: 40, width: 100, height: 40),
            "dragged": CGRect(x: 0, y: 80, width: 100, height: 40)
        ]

        XCTAssertNil(reorderTarget(
            at: CGPoint(x: 20, y: 76),
            in: frames,
            excluding: "dragged",
            orderedIDs: ["above", "divider", "dragged"],
        ))
        XCTAssertEqual(reorderTarget(
            at: CGPoint(x: 20, y: 72),
            in: frames,
            excluding: "dragged",
            orderedIDs: ["above", "divider", "dragged"],
        ), "divider")
    }

    /// Wide dashboard: neighbours in one grid row share a band of y, so the crossing is horizontal —
    /// a drag along the header (near the top of a tall card) still moves right and left.
    func testCrossingThresholdWithinAGridRow() {
        let frames = [
            "left": CGRect(x: 0, y: 0, width: 300, height: 200),
            "dragged": CGRect(x: 320, y: 0, width: 300, height: 120),
            "right": CGRect(x: 640, y: 0, width: 300, height: 160)
        ]
        let order = ["left", "dragged", "right"]

        XCTAssertNil(reorderTarget(at: CGPoint(x: 660, y: 10), in: frames, excluding: "dragged", orderedIDs: order))
        XCTAssertEqual(
            reorderTarget(at: CGPoint(x: 720, y: 10), in: frames, excluding: "dragged", orderedIDs: order),
            "right"
        )
        XCTAssertNil(reorderTarget(at: CGPoint(x: 280, y: 10), in: frames, excluding: "dragged", orderedIDs: order))
        XCTAssertEqual(
            reorderTarget(at: CGPoint(x: 220, y: 10), in: frames, excluding: "dragged", orderedIDs: order),
            "left"
        )
    }
}
