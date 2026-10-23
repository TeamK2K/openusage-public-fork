import Foundation

/// The concise "which account has room" page the local server serves at `/`: a top bar (title, Add
/// Account), the which-account verdict, then one card per account fitted on one screen, soonest reset
/// first, with its status and battery bars, plus the Add Account / Sign In flow. It reads `/v1/limits`
/// and `/v1/accounts/…` from the same origin and refreshes itself.
///
/// The page is a React + Tailwind app built from Shadcn Studio blocks in `web/accounts-page`;
/// `script/build_accounts_page.sh` builds it into one self-contained HTML file (no external assets)
/// committed as the `accounts_page.html` resource, which this serves as-is.
enum SeatsPage {
    static let resourceName = "accounts_page"

    static let html: Data = load()

    static func load(from bundle: Bundle = .openUsageResources) -> Data {
        guard let url = bundle.url(forResource: resourceName, withExtension: "html") else {
            AppLog.error(.localAPI, "accounts page: \(resourceName).html is missing from the app's resources")
            return unavailable
        }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                AppLog.error(.localAPI, "accounts page: \(resourceName).html is empty")
                return unavailable
            }
            return data
        } catch {
            AppLog.error(.localAPI, "accounts page: couldn't read \(resourceName).html (\(error.localizedDescription))")
            return unavailable
        }
    }

    /// What the page says when this build carries no page (a broken install): the friendly half of a
    /// loud failure, the log line above is the other.
    static let unavailable = Data("""
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><title>AI Accounts · OpenUsage</title></head>
    <body style="font: 16px -apple-system, system-ui, sans-serif; margin: 3rem;">
    <h1>The Accounts Page Is Missing</h1>
    <p>This copy of OpenUsage was built without its accounts page. Reinstall OpenUsage from its website; the menu bar panel and <code>/v1/limits</code> still work.</p>
    </body></html>
    """.utf8)
}
