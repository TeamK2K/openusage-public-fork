import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

final class ColumnGridLayoutTests: XCTestCase {
    func testColumnsSplitTheWidthEvenlyAroundTheGaps() {
        XCTAssertEqual(ColumnGridLayout.columnWidth(total: 932, columns: 3, spacing: 16), 300)
        XCTAssertEqual(ColumnGridLayout.columnWidth(total: 20, columns: 3, spacing: 16), 0)
        XCTAssertEqual(ColumnGridLayout.columnWidth(total: 300, columns: 0, spacing: 16), 0)
    }

    /// Every card is measured: each row is as tall as its tallest card, a short last row included,
    /// so the panel's content-driven height is exact.
    @MainActor
    func testHeightIsTheSumOfEachRowsTallestCard() {
        let heights: [CGFloat] = [100, 40, 60, 30, 80, 20, 50]
        let grid = ColumnGridLayout(columns: 3, spacing: 10) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Color.clear.frame(height: height)
            }
        }
        let host = NSHostingView(rootView: grid.frame(width: 320))

        XCTAssertEqual(host.fittingSize.height, 100 + 80 + 50 + 2 * 10, accuracy: 0.5)
    }

    @MainActor
    func testNoCardsTakesNoHeight() {
        let host = NSHostingView(rootView: ColumnGridLayout(columns: 3, spacing: 10) {}.frame(width: 320))

        XCTAssertEqual(host.fittingSize.height, 0, accuracy: 0.5)
    }
}
