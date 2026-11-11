import XCTest

final class CleanerUITests: XCTestCase {
    @MainActor func testRemainingVideoAndContactsBackup() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--qa-screen", "videos"]
        app.launch()
        let other = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Other,")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(other.label.contains("1 videos"), other.label)
        let kept = XCTAttachment(screenshot: app.screenshot()); kept.name = "one-original-video-retained"; kept.lifetime = .keepAlways; add(kept)
        app.terminate()
        app.launchArguments = ["--qa-screen", "contacts"]
        app.launch()
        let allContacts = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "All contacts")).firstMatch
        XCTAssertTrue(allContacts.waitForExistence(timeout: 10), app.debugDescription)
        let originalLabel = allContacts.label
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Backups")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Create backup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Create backup"].isEnabled)
        app.buttons["Create backup"].tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Backed up ")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), app.debugDescription)
        let backup = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Contacts-")).firstMatch
        XCTAssertTrue(backup.exists)
        backup.tap()
        let restore = app.buttons["Restore contacts"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        let confirmRestore = app.sheets.buttons["Restore contacts"]
        XCTAssertTrue(confirmRestore.waitForExistence(timeout: 5), app.debugDescription)
        confirmRestore.tap()
        let restored = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Restored 0 contacts.")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 15), app.debugDescription)
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "backup-restore-deduplicated"; proof.lifetime = .keepAlways; add(proof)
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()
        XCTAssertEqual(allContacts.label, originalLabel)
    }

    @MainActor func testOwnedDuplicateVideoDeletion() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = ["--qa-screen", "scan"]
        app.launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let fullAccess = system.buttons["Allow Full Access"]
        if fullAccess.waitForExistence(timeout: 8) { fullAccess.tap() }
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Duplicate Videos")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 90), app.debugDescription)
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        // Fail closed: only the two newly imported identical QA videos may be selected.
        XCTAssertTrue(row.label.contains("2 items"), "Unexpected duplicate population: \(row.label)")
        row.tap()
        XCTAssertTrue(app.staticTexts["Group 1 · 2 videos"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Preview video").count, 2)
        XCTAssertTrue(app.buttons["Deselect all"].exists)
        let delete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Delete 1 Videos,")).firstMatch
        XCTAssertTrue(delete.exists)
        app.buttons["Deselect all"].tap()
        let emptyDelete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Delete 0 Videos,")).firstMatch
        XCTAssertTrue(emptyDelete.exists)
        XCTAssertFalse(emptyDelete.isEnabled)
        app.buttons["Select all"].tap()
        XCTAssertTrue(delete.isEnabled)
        app.buttons.matching(identifier: "Preview video").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Preview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Video unavailable"].exists)
        let preview = XCTAttachment(screenshot: app.screenshot()); preview.name = "owned-video-preview"; preview.lifetime = .keepAlways; add(preview)
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        app.buttons["Delete selected items"].tap()
        let systemDelete = system.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Delete")).firstMatch
        XCTAssertTrue(systemDelete.waitForExistence(timeout: 8))
        print("System delete frame: \(systemDelete.frame)")
        let prompt = XCTAttachment(screenshot: system.screenshot()); prompt.name = "system-delete-prompt"; prompt.lifetime = .keepAlways; add(prompt)
        systemDelete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: systemDelete)
        if XCTWaiter.wait(for: [dismissed], timeout: 3) != .completed {
            XCTAssertTrue(systemDelete.exists)
            print("System confirmation still visible: \(system.debugDescription)")
            systemDelete.tap()
        }
        XCTAssertTrue(app.staticTexts["All done"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1 items deleted")).firstMatch.exists)
        let success = XCTAttachment(screenshot: app.screenshot()); success.name = "one-owned-video-deleted"; success.lifetime = .keepAlways; add(success)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Nothing here"].waitForExistence(timeout: 5))
    }
}
