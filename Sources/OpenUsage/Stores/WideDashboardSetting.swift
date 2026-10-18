import CoreGraphics
import Foundation
import Observation

/// Opt-in wide panel: the dashboard lays provider cards out three across instead of one long column,
/// so many accounts (several Claude config folders, say) read at a glance without scrolling. Off by
/// default; the toggle sits in Settings → Appearance.
enum WideDashboardSetting {
    static let key = "openusage.wideDashboard"
    static let fallback = false
    /// Provider cards per row while wide.
    static let columns = 3
    /// The regular single-column panel width.
    static let regularWidth: CGFloat = 320
    /// Panel width while wide: three cards a little roomier than the regular single column.
    static let wideWidth: CGFloat = 960
    /// Settings and Customize are forms, not card grids: in the wide window they stay a centered
    /// column this wide instead of stretching each label-and-control row across the whole panel.
    static let formWidth: CGFloat = 560

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    /// The panel width the setting asks for, before any display clamping.
    static func panelWidth(defaults: UserDefaults = .standard) -> CGFloat {
        isEnabled(defaults: defaults) ? wideWidth : regularWidth
    }

    /// Posted after the setting flips (the Settings switch, Reset All) so the open panel resizes in
    /// place. Deliberately not `UserDefaults.didChangeNotification`, which fires for every defaults
    /// write the app makes.
    static let didChangeNotification = Notification.Name("WideDashboardSettingDidChange")

    @MainActor
    static func notifyChanged() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

/// The width the panel really has: the setting's width clamped to the display. `PanelHeightController`
/// writes it whenever it sizes the window; the dashboard lays out at exactly this width, so on a display
/// narrower than the wide panel the content shrinks with the window instead of being clipped.
@MainActor
@Observable
final class PanelWidthStore {
    var width: CGFloat

    init(width: CGFloat = WideDashboardSetting.panelWidth()) {
        self.width = width
    }
}
