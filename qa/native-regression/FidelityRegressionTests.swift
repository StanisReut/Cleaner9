import XCTest
import AVFoundation

final class FidelityRegressionTests: XCTestCase {
    @MainActor func testESeekProbe() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cleaner-test-video", withExtension: "mp4"))
        let player = AVPlayer(url: url)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in player.status == .readyToPlay }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let first = expectation(description: "default seek")
        player.seek(to: CMTime(seconds: 1.6, preferredTimescale: 600)) { finished in
            print("SEEK_PROBE default finished=\(finished) time=\(player.currentTime().seconds)")
            first.fulfill()
        }
        wait(for: [first], timeout: 10)
        let second = expectation(description: "precise seek")
        player.seek(to: CMTime(seconds: 1.6, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            print("SEEK_PROBE precise finished=\(finished) time=\(player.currentTime().seconds)")
            second.fulfill()
        }
        wait(for: [second], timeout: 10)
    }
    @MainActor func testDSecondaryModalButtonHitTarget() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for dy in [0.5, 0.92] {
            app.terminate()
            app.launchArguments = ["--fidelity-frame", "159:3259"]
            app.launch()
            let back = app.buttons["Back to Settings"]
            XCTAssertTrue(back.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertGreaterThanOrEqual(back.frame.height, 44)
            attach("modal-secondary-before-\(dy)")
            back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)).tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: back)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, app.debugDescription)
            attach("modal-secondary-dismissed-\(dy)")
        }
    }
    @MainActor private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testANativeSystemHandoffs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for id in ["141:2302", "129:2935", "141:2430", "141:2550"] {
            app.terminate()
            if id == "141:2430" || id == "141:2550" {
                app.resetAuthorizationStatus(for: .photos)
            }
            app.launchArguments = ["--fidelity-frame", id, "--fidelity-native-handoff"]
            app.launch()
            if id == "141:2302" {
                let photos = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["Photos", "Фото"])).firstMatch
                XCTAssertTrue(photos.waitForExistence(timeout: 12), app.debugDescription)
            } else if id == "129:2935" {
                let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Copy", "Скопировать", "Копировать"])).firstMatch
                XCTAssertTrue(copy.waitForExistence(timeout: 12), app.debugDescription)
            } else {
                let deny = system.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label == %@", "Don", "Не разрешать")).firstMatch
                XCTAssertTrue(deny.waitForExistence(timeout: 12), system.debugDescription)
                attach("native-\(id.replacingOccurrences(of: ":", with: "-"))")
                deny.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                continue
            }
            attach("native-\(id.replacingOccurrences(of: ":", with: "-"))")
        }
        app.terminate()
    }

    @MainActor func testBOwnedDuplicateVideoAndPlayback() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = ["--qa-screen", "scan"]
        app.launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Full Access", "Разрешить полный доступ"])).firstMatch
        if allow.waitForExistence(timeout: 8) { allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        let duplicates = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Duplicate videos")).firstMatch
        XCTAssertTrue(duplicates.waitForExistence(timeout: 90), app.debugDescription)
        for _ in 0..<5 where !duplicates.isHittable { app.swipeUp() }
        duplicates.tap()
        app.buttons["Deselect all"].tap()
        XCTAssertFalse(app.buttons["Delete videos"].isEnabled)
        let previews = app.buttons.matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "Preview video", "cleaner-test-video"))
        for _ in 0..<30 where previews.count < 2 { app.swipeUp() }
        XCTAssertEqual(previews.count, 2)
        for index in 0..<2 {
            XCTAssertTrue((previews.element(boundBy: index).value as? String ?? "").contains("cleaner-test-video"), "Only owned QA media may be deleted")
        }
        let ownedSecond = previews.element(boundBy: 1)
        for _ in 0..<5 where !ownedSecond.isHittable { app.swipeUp() }
        ownedSecond.tap()
        let previewSelection = app.buttons.matching(identifier: "Select item").firstMatch
        XCTAssertTrue(previewSelection.waitForExistence(timeout: 5))
        XCTAssertTrue(previewSelection.isHittable)
        previewSelection.tap()
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), app.debugDescription)
        let timeline = app.descendants(matching: .any).matching(identifier: "Playback position").firstMatch
        XCTAssertTrue(timeline.exists)
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 0.4, thenDragTo: timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        let sought = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "00:01"), object: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [sought], timeout: 5), .completed)
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 1))
        XCTAssertTrue(play.waitForExistence(timeout: 6), "Playback must return to Play when the clip ends")
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 1), "Replay must restart the clip")
        attach("live-player")
        app.buttons.matching(identifier: "Back").firstMatch.tap()
        let delete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Delete 1 Videos,")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap(); app.buttons["Delete selected items"].tap()
        let approve = system.buttons.matching(NSPredicate(format: "label IN %@", ["Delete", "Удалить"])).firstMatch
        if approve.waitForExistence(timeout: 8) { approve.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        let result = app.staticTexts["1 video deleted"]
        XCTAssertTrue(result.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " deleted")).count, 1, "Exactly one result modal")
        attach("live-deletion-result")
        app.buttons["Continue"].tap()
        app.terminate(); app.launchArguments = ["--qa-screen", "videos"]; app.launch()
        let other = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Other,")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 60))
        other.tap()
        let retained = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "cleaner-test-video")).firstMatch
        for _ in 0..<30 where !retained.exists { app.swipeUp() }
        XCTAssertTrue(retained.exists, "Owned original copy must remain")
        attach("live-original-retained")
    }

    @MainActor func testCContactsBackupRestoreIsIdempotent() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--qa-screen", "contacts"]; app.launch()
        let all = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "All contacts")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 15), app.debugDescription)
        let before = all.label
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Backups")).firstMatch.tap()
        let create = app.buttons["Create backup"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); XCTAssertTrue(create.isEnabled)
        create.tap()
        let backup = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " contacts")).firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 10), app.debugDescription); backup.tap()
        let restore = app.buttons["Restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
        app.sheets.buttons["Restore contacts"].tap()
        XCTAssertTrue(app.staticTexts["0 contacts restored"].waitForExistence(timeout: 20), app.debugDescription)
        attach("live-restore-result")
        app.buttons["Continue"].tap()
        app.buttons["Back"].tap()
        XCTAssertEqual(all.label, before)
    }
}
