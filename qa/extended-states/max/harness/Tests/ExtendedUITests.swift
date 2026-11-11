import XCTest

final class ExtendedUITests: XCTestCase {
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-ax"; tree.lifetime = .keepAlways; add(tree)
    }

    @MainActor func testMaxTextScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        let ids = ["4:214", "47:56", "51:52", "51:211", "51:411", "51:915", "59:1683", "59:1953", "78:5059", "94:1517", "94:2930", "94:3224", "94:4213", "119:1912", "119:3280", "127:2092", "129:2217", "147:2387", "147:2719", "147:3080", "147:3269", "147:3340", "159:2752", "159:2979", "235:2861", "235:2908", "235:2955", "78:5157", "78:5345", "78:5559", "94:2057", "94:3869", "94:4372", "94:4665", "119:2804", "159:3259", "159:3124", "159:3189", "141:2461"]
        for id in ids {
            app.terminate(); app.launchArguments = ["--fidelity-frame", id]; app.launch()
            capture(app, "max-" + id.replacingOccurrences(of: ":", with: "-") + "-top")
            for count in 1...(id == "4:214" ? 6 : 3) {
                if app.scrollViews.firstMatch.exists { app.scrollViews.firstMatch.swipeUp() }
                else { app.swipeUp() }
                if [1, 3, 6, 10].contains(count) {
                    capture(app, "max-" + id.replacingOccurrences(of: ":", with: "-") + "-scroll-\(count)")
                }
            }
        }
        app.terminate()
    }

    @MainActor func testAccessibleModalActions() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        for (id, title) in [("159:3259", "Back to Settings"), ("159:3189", "Continue"), ("94:3869", "Continue")] {
            app.terminate(); app.launchArguments = ["--fidelity-frame", id]; app.launch()
            let button = app.buttons[title]
            for _ in 0..<5 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(button.isHittable, "Action unreachable: " + id)
            capture(app, "action-" + id.replacingOccurrences(of: ":", with: "-"))
            button.tap()
        }
        app.terminate()
    }

    @MainActor func testClearPhotosPrompt() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        app.launchArguments = ["--qa-screen", "scan"]; app.launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.buttons["Allow Full Access"]
        if allow.waitForExistence(timeout: 10) { allow.tap() }
        capture(app, "live-permission-cleared")
        app.terminate()
    }

    @MainActor func testSupplementalLiveErrors() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        app.launchArguments = ["--qa-screen", "email"]; app.launch()
        let email = app.textFields["Email address"]
        XCTAssertTrue(email.waitForExistence(timeout: 10)); email.tap(); email.typeText("alex@example.com")
        app.buttons["Check"].tap()
        XCTAssertTrue(app.staticTexts["Check unavailable"].waitForExistence(timeout: 5))
        capture(app, "supplemental-email-unavailable")
        app.terminate(); app.launchArguments = ["--qa-screen", "settings"]; app.launch()
        let restore = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Restore Purchases")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10)); restore.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        capture(app, "supplemental-restore-unconfigured")
        app.alerts.buttons["OK"].tap(); app.terminate()
    }

    @MainActor func testLiveMediaEntry() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        for (route, title) in [("photos", "Let’s Go!"), ("swipe", "Got it")] {
            app.terminate(); app.launchArguments = ["--qa-screen", route]; app.launch()
            let start = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", route == "photos" ? "Go" : title)).firstMatch
            if start.waitForExistence(timeout: 5) { start.tap() }
            capture(app, "real-" + route + "-loaded")
        }
        app.terminate()
    }

    @MainActor func testLastVideoRowFix() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        app.launchArguments = ["--fidelity-frame", "78:5559"]; app.launch()
        for _ in 0..<3 { app.scrollViews.firstMatch.swipeUp() }
        capture(app, "final-large-videos-row-names")
        app.terminate()
    }

    @MainActor func testLiveScrollReachability() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        for route in ["home", "subscription", "device"] {
            app.terminate(); app.launchArguments = ["--qa-screen", route]; app.launch()
            for count in 1...3 {
                app.scrollViews.firstMatch.swipeUp()
                capture(app, "real-" + route + "-scroll-\(count)")
            }
        }
        app.terminate()
    }
}
