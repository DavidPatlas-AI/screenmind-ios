import XCTest

final class ScreenMindUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-AppleLanguages", "(he)", "-AppleLocale", "he_IL"]
        app.launch()
        return app
    }

    func testFreshLaunchShowsHebrewTabsAndAnEmptyLibrary() {
        let app = launch(["-UITestReset"])
        XCTAssertTrue(app.tabBars.buttons["בית"].waitForExistence(timeout: 8))
        for name in ["ספרייה", "המוח", "מרחבים", "הצעד הבא"] {
            XCTAssertTrue(app.tabBars.buttons[name].exists)
        }
        XCTAssertTrue(app.staticTexts["מתחילים בכמה צילומים."].exists)
        XCTAssertTrue(app.buttons["שמור צילומים"].exists)

        app.tabBars.buttons["ספרייה"].tap()
        let scan = app.buttons["סרוק צילומי מסך"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        XCTAssertTrue(app.buttons["אפשר גישה וסרוק"].waitForExistence(timeout: 5))
        app.buttons["ביטול"].firstMatch.tap()

        app.tabBars.buttons["המוח"].tap()
        XCTAssertTrue(app.staticTexts["המוח מתמלא מצילומים."].waitForExistence(timeout: 5))
    }

    func testSeededBrainOpensATopicAndRereadsTheSource() {
        let app = launch(["-UITestSeed"])
        XCTAssertTrue(app.buttons["המוח של הרעיונות"].waitForExistence(timeout: 8))
        app.tabBars.buttons["המוח"].tap()
        XCTAssertTrue(app.buttons["הגיע הרגע, להתקשר"].waitForExistence(timeout: 5))
        let topic = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "נושא הבית")).firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        topic.tap()
        let source = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "שולחן אלון")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        XCTAssertTrue(app.navigationBars["המקור והכוונה"].waitForExistence(timeout: 5))
        app.swipeUp()
        let reread = app.buttons["זהה טקסט מחדש"]
        XCTAssertTrue(reread.waitForExistence(timeout: 5))
        reread.tap()
        let finished = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "לא נמצא טקסט", "הזיהוי לא הושלם")).firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout: 30))
    }

    func testReviewAsksWhyTheScreenshotWasSaved() {
        let app = launch(["-UITestSeed"])
        let review = app.buttons["לסקירה"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        if !review.isHittable { app.swipeUp() }
        review.tap()
        XCTAssertTrue(app.staticTexts["מה חשוב לזכור? תקן אם צריך, ובחר למה שמרת את זה לפני שממשיכים."].waitForExistence(timeout: 5))
    }

    func testFavoriteSurvivesRelaunch() {
        let app = launch(["-UITestSeed"])
        app.tabBars.buttons["ספרייה"].tap()
        let tile = app.buttons["שולחן אלון"]
        XCTAssertTrue(tile.waitForExistence(timeout: 8))
        tile.tap()
        app.swipeUp()
        let add = app.buttons["הוסף למועדפים"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.buttons["הסר ממועדפים"].waitForExistence(timeout: 5))
        app.terminate()

        let again = launch()
        again.tabBars.buttons["ספרייה"].tap()
        XCTAssertTrue(again.buttons["שולחן אלון"].waitForExistence(timeout: 8))
        again.buttons["שולחן אלון"].tap()
        again.swipeUp()
        XCTAssertTrue(again.buttons["הסר ממועדפים"].waitForExistence(timeout: 8))
    }

    func testSettingsDescribeOnDeviceHebrew() {
        let app = launch(["-UITestReset"])
        app.buttons["הגדרות ופרטיות"].tap()
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Tesseract")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
    }

    func testLargeTextAndDarkModeKeepTheTabsReachable() {
        let app = launch(["-UITestReset", "-UITestDark", "-UITestLargeText"])
        for name in ["בית", "ספרייה", "המוח", "מרחבים", "הצעד הבא"] {
            let tab = app.tabBars.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 8))
            XCTAssertTrue(tab.isHittable)
        }
    }

    func testBulkScanExplainsTheWholeAlbumBeforeItStarts() {
        let app = launch(["-UITestReset"])
        let scan = app.buttons["סרוק את כל צילומי המסך"]
        XCTAssertTrue(scan.waitForExistence(timeout: 8))
        scan.tap()
        XCTAssertTrue(app.buttons["סרוק הכול"].waitForExistence(timeout: 5))
        app.buttons["ביטול"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["המוח"].exists)
    }

    func testAlbumProgressCanPauseWithoutDeleting() {
        let app = launch(["-UITestReset", "-UITestAlbumRunning"])
        let progress = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "400 מתוך 2500")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        app.buttons["השהה"].tap()
        XCTAssertTrue(app.buttons["המשך סריקה"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["העבר לנמחקו לאחרונה"].exists)
    }

    func testCleanupAsksBeforeMovingScreenshotsToRecentlyDeleted() {
        let app = launch(["-UITestSeed"])
        let open = app.buttons["בדוק מה אפשר לפנות"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        if !open.isHittable { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.staticTexts["כפילויות"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["בלי טקסט מועיל"].exists)
        XCTAssertTrue(app.staticTexts["הטקסט כבר שמור"].exists)
        XCTAssertTrue(app.buttons["שתף כ־Markdown"].exists)
        XCTAssertTrue(app.buttons["שתף כטקסט"].exists)
        let selectJunk = app.buttons["בחר את כל מה שבלי טקסט מועיל"]
        if !selectJunk.isHittable { app.swipeUp() }
        selectJunk.tap()
        app.buttons["מחק את הבחירה מתמונות"].tap()
        XCTAssertTrue(app.buttons["העבר לנמחקו לאחרונה"].waitForExistence(timeout: 5))
        app.buttons["להשאיר בתמונות"].tap()
        XCTAssertTrue(app.staticTexts["בלי טקסט"].exists)
    }
}
