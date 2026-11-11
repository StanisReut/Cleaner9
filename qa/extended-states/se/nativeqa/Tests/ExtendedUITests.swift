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
        let ids = ["4:214", "47:23", "47:56", "51:52", "59:1683", "51:87", "51:145", "51:211", "51:411", "59:1953", "78:5059", "94:1327", "94:1517", "94:2057", "94:2930", "94:3224", "94:4213", "119:3280", "127:2092", "129:2123", "141:2383", "129:2217", "147:2387", "147:2719", "147:2774", "147:3080", "147:3269", "147:3340", "147:3669", "235:2861", "235:2908", "235:2955", "94:3869", "94:4372", "159:3259", "159:3189", "119:2804", "78:5157", "78:5345", "78:5559", "51:915", "94:1992"]
        for id in ids {
            app.terminate(); app.launchArguments = ["--fidelity-frame", id]; app.launch()
            capture(app, "max-" + id.replacingOccurrences(of: ":", with: "-") + "-top")
            for count in 1...(id == "4:214" ? 8 : 4) {
                if app.scrollViews.firstMatch.exists { app.scrollViews.firstMatch.swipeUp() }
                else { app.swipeUp() }
                if [1, 4, 8].contains(count) {
                    capture(app, "max-" + id.replacingOccurrences(of: ":", with: "-") + "-scroll-\(count)")
                }
            }
        }
        app.terminate()
    }

    @MainActor func testModalActionsReachable() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        for (id, label) in [("94:3869", "Continue"), ("159:3259", "Back to Settings"), ("159:3189", "Continue"), ("141:2461", "Back to editor")] {
            app.terminate(); app.launchArguments = ["--fidelity-frame", id]; app.launch()
            let button = app.buttons[label]
            for _ in 0..<6 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(button.isHittable, id + " action must be reachable")
            capture(app, "modal-reachable-" + id.replacingOccurrences(of: ":", with: "-"))
        }
        app.terminate()
    }

    @MainActor func testSettingsScroll() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        for id in ["159:2752", "159:2979"] {
            app.terminate(); app.launchArguments = ["--fidelity-frame", id]; app.launch()
            for _ in 0..<6 { app.scrollViews.firstMatch.swipeUp() }
            capture(app, "settings-bottom-" + id.replacingOccurrences(of: ":", with: "-"))
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Privacy Policy")).firstMatch.isHittable)
        }
        app.terminate()
    }

    @MainActor func testPhotosDeniedAfterIntro() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        app.launchArguments = ["--qa-screen", "photos"]; app.launch()
        let intro = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Go!")).firstMatch
        if intro.waitForExistence(timeout: 3) { intro.tap() }
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 8))
        capture(app, "denied-photos-after-intro")
        app.terminate()
    }

    @MainActor func testTargetedVerticalScroll() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        for id in ["51:211", "51:915", "59:1953", "78:5157", "78:5345", "78:5559", "147:3340", "147:3669"] {
            app.terminate(); app.launchArguments = ["--fidelity-frame", id]; app.launch()
            for _ in 0..<8 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.67)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.39)))
            }
            capture(app, "vertical-bottom-" + id.replacingOccurrences(of: ":", with: "-"))
        }
        app.terminate()
    }

    @MainActor func testLivePhotosGranted() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        app.launchArguments = ["--qa-screen", "photos"]; app.launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.buttons["Allow Full Access"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let duplicate = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Duplicates")).firstMatch
        XCTAssertTrue(duplicate.waitForExistence(timeout: 15))
        capture(app, "real-photos-granted")
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
    @MainActor func testRealPhotosPastIntro() {
        let app = XCUIApplication(bundleIdentifier: "test.com.PhotoCleanerApp")
        app.launchArguments = ["--qa-screen", "photos"]; app.launch()
        let intro = app.buttons["Let’s Go!"]
        if intro.waitForExistence(timeout: 5) { intro.tap() }
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Full Access"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Duplicates")).firstMatch.waitForExistence(timeout: 15))
        capture(app, "real-photos-categories")
        app.terminate()
    }

}
