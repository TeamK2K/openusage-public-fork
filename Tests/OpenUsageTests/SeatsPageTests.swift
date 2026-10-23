import JavaScriptCore
import XCTest
@testable import OpenUsage

/// The accounts page the server serves at `/` is the built `accounts_page.html` resource (source:
/// web/accounts-page, whose own Vitest suite covers the page's logic). These pin what the app relies on:
/// one self-contained document that talks only to its own origin, and a loud, friendly failure when a
/// build carries no page.
final class SeatsPageTests: XCTestCase {
    private var page: String { String(decoding: SeatsPage.html, as: UTF8.self) }

    func testServesTheCommittedBuild() throws {
        let committed = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenUsage/Resources/accounts_page.html")
        XCTAssertEqual(SeatsPage.html, try Data(contentsOf: committed))
        XCTAssertNotEqual(SeatsPage.html, SeatsPage.unavailable)
    }

    func testIsOneSelfContainedDocument() {
        let page = page
        XCTAssertTrue(page.hasPrefix("<!doctype html>"))
        XCTAssertEqual(page.components(separatedBy: "<html").count, 2)
        // Scripts and styles are inline; nothing is fetched from anywhere but the app itself.
        XCTAssertFalse(page.contains("<script src"))
        XCTAssertFalse(page.contains(" src=\"http"))
        XCTAssertFalse(page.contains(" href=\"http"))
        XCTAssertFalse(page.contains("<link"))
        XCTAssertFalse(page.contains("url(http"))
        XCTAssertTrue(page.contains("<script type=\"module\" crossorigin>"))
        XCTAssertTrue(page.contains("<style"))
    }

    func testTheInlineScriptParses() throws {
        let start = try XCTUnwrap(page.range(of: "<script type=\"module\" crossorigin>"))
        let end = try XCTUnwrap(page.range(of: "</script>", range: start.upperBound..<page.endIndex))
        let script = String(page[start.upperBound..<end.lowerBound])
        let context = try XCTUnwrap(JSContext())
        var thrown: String?
        context.exceptionHandler = { _, exception in thrown = exception?.toString() }
        // Compile only: `new Function` parses the body without running it (no DOM here).
        context.setObject(script, forKeyedSubscript: "source" as NSString)
        context.evaluateScript("new Function(source)")
        XCTAssertNil(thrown)
    }

    func testCarriesTheTopBarAndTheSignInFlow() {
        let page = page
        for text in ["AI Accounts", "Add Account", "Waiting for sign-in…", "Paste Code", "Sign In", "In Use",
                     "Use this one", "refreshes every 30 seconds"] {
            XCTAssertTrue(page.contains(text), text)
        }
        for route in ["/v1/limits", "/v1/accounts/signin", "/v1/accounts/add", "/v1/accounts/signin/code",
                      "/v1/accounts/signin/cancel"] {
            XCTAssertTrue(page.contains("\"\(route)\"") || page.contains("`\(route)`"), route)
        }
        // Light and dark follow the Mac.
        XCTAssertTrue(page.contains("prefers-color-scheme: dark"))
        // No clock times or dates anywhere on the cards.
        XCTAssertFalse(page.contains("toLocaleTimeString"))
        XCTAssertFalse(page.contains("toLocaleDateString"))
    }

    func testABuildWithoutThePageSaysSoInsteadOfServingNothing() throws {
        // `Bundle` caches its file lookups per path, so each case gets a folder of its own.
        func folder(page: Data?) throws -> Bundle {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("SeatsPageTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: url) }
            if let page { try page.write(to: url.appendingPathComponent("accounts_page.html")) }
            return try XCTUnwrap(Bundle(url: url))
        }
        XCTAssertEqual(SeatsPage.load(from: try folder(page: nil)), SeatsPage.unavailable)
        XCTAssertEqual(SeatsPage.load(from: try folder(page: Data())), SeatsPage.unavailable, "an empty file is no page")
        XCTAssertTrue(String(decoding: SeatsPage.unavailable, as: UTF8.self).contains("The Accounts Page Is Missing"))

        let page = Data("<!doctype html><p>page</p>".utf8)
        XCTAssertEqual(SeatsPage.load(from: try folder(page: page)), page)
    }
}
