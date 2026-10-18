import Foundation

/// Whether a left click on the menu-bar item opens the concise accounts page (served by the local
/// usage API at `/`) in the default browser instead of the panel. Off by default; the toggle sits
/// in Settings → General. Right-click keeps a menu with the panel, Settings, and Quit.
enum SeatsPageSetting {
    static let key = "openusage.clickOpensSeatsPage"
    static let fallback = false
    /// Mirrors `LocalUsageServer.port`; kept here as a literal so the setting stays nonisolated.
    static let url = URL(string: "http://127.0.0.1:6736/")!

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
