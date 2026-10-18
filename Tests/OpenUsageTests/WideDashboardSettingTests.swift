import AppKit
import XCTest
@testable import OpenUsage

final class WideDashboardSettingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WideDashboardSettingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testOffByDefaultKeepsTheRegularWidth() {
        XCTAssertFalse(WideDashboardSetting.isEnabled(defaults: defaults))
        XCTAssertEqual(WideDashboardSetting.panelWidth(defaults: defaults), WideDashboardSetting.regularWidth)
    }

    func testOnAsksForTheThreeAcrossWidth() {
        defaults.set(true, forKey: WideDashboardSetting.key)

        XCTAssertTrue(WideDashboardSetting.isEnabled(defaults: defaults))
        XCTAssertEqual(WideDashboardSetting.panelWidth(defaults: defaults), WideDashboardSetting.wideWidth)
        XCTAssertEqual(WideDashboardSetting.columns, 3)
    }

    func testWideWidthShrinksToFitANarrowDisplay() {
        let narrow = NSRect(x: 0, y: 0, width: 800, height: 900)
        let roomy = NSRect(x: 0, y: 0, width: 1800, height: 1100)

        XCTAssertEqual(PanelGeometry.clampedWidth(WideDashboardSetting.wideWidth, visibleFrame: narrow), 784)
        XCTAssertEqual(PanelGeometry.clampedWidth(WideDashboardSetting.wideWidth, visibleFrame: roomy), 960)
        XCTAssertEqual(PanelGeometry.clampedWidth(320, visibleFrame: nil), 320)
    }

    @MainActor
    func testPanelWidthStoreStartsAtTheStoredSettingsWidth() {
        XCTAssertEqual(PanelWidthStore(width: WideDashboardSetting.panelWidth(defaults: defaults)).width, 320)
        defaults.set(true, forKey: WideDashboardSetting.key)
        XCTAssertEqual(PanelWidthStore(width: WideDashboardSetting.panelWidth(defaults: defaults)).width, 960)
    }

    func testFormsStayNarrowerThanTheWideWindow() {
        XCTAssertGreaterThanOrEqual(WideDashboardSetting.formWidth, WideDashboardSetting.regularWidth)
        XCTAssertLessThan(WideDashboardSetting.formWidth, WideDashboardSetting.wideWidth)
    }
}
