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

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let raw = ProcessInfo.processInfo.environment["SCREENMIND_SHOTS"] ?? ""
        let folder = raw.isEmpty || raw.contains("$(")
            ? URL(fileURLWithPath: "/tmp/screenmind-shots", isDirectory: true)
            : URL(fileURLWithPath: raw, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }

    func testFreshLaunchShowsHebrewTabsAndAnEmptyLibrary() {
        let app = launch(["-UITestReset"])
        XCTAssertTrue(app.tabBars.buttons["בית"].waitForExistence(timeout: 8))
        for name in ["ספרייה", "המוח", "מרחבים", "הצעד הבא"] {
            XCTAssertTrue(app.tabBars.buttons[name].exists)
        }
        XCTAssertTrue(app.staticTexts["מתחילים בכמה צילומים."].exists)
        XCTAssertTrue(app.buttons["שמור צילומים"].exists)
        snap("01-home-empty")

        app.tabBars.buttons["ספרייה"].tap()
        let scan = app.buttons["סרוק צילומי מסך"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        XCTAssertTrue(app.buttons["אפשר גישה וסרוק"].waitForExistence(timeout: 5))
        app.buttons["ביטול"].firstMatch.tap()

        app.tabBars.buttons["המוח"].tap()
        XCTAssertTrue(app.staticTexts["המוח מתמלא מצילומים."].waitForExistence(timeout: 5))
        snap("02-brain-empty")
    }

    func testSeededBrainOpensATopicAndRereadsTheSource() {
        let app = launch(["-UITestSeed"])
        let brainLink = app.buttons["המוח של הרעיונות"]
        for _ in 0..<3 where !brainLink.isHittable { app.swipeUp() }
        XCTAssertTrue(brainLink.waitForExistence(timeout: 8))
        app.tabBars.buttons["המוח"].tap()
        let moment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "הגיע הרגע")).firstMatch
        XCTAssertTrue(moment.waitForExistence(timeout: 5))
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
        let finished = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@", "זוהה שוב", "הזיהוי לא הושלם", "לא נמצא טקסט")).firstMatch
        if !finished.waitForExistence(timeout: 8) { app.swipeDown() }
        XCTAssertTrue(finished.waitForExistence(timeout: 30))
        snap("03-source-reread")
    }

    func testKnowledgeTopicsOpenWithoutManualReview() {
        let app = launch(["-UITestSeed"])
        app.tabBars.buttons["מרחבים"].tap()
        XCTAssertTrue(app.staticTexts["עולם הידע שלי"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["הבית"].waitForExistence(timeout: 5))
        app.staticTexts["הבית"].tap()
        XCTAssertTrue(app.buttons["שולחן אלון"].waitForExistence(timeout: 8))
        snap("13-knowledge-topics")
    }

    func testReviewAsksWhyTheScreenshotWasSaved() {
        let app = launch(["-UITestSeed"])
        let review = app.buttons["לסקירה"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        if !review.isHittable { app.swipeUp() }
        review.tap()
        XCTAssertTrue(app.staticTexts["מה חשוב לזכור? תקן אם צריך, ובחר למה שמרת את זה לפני שממשיכים."].waitForExistence(timeout: 5))
        snap("04-review-why")
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
        snap("05-favorite-kept")
    }

    func testHomeDiscoveryOpensLocalMemoryChat() {
        let app = launch(["-UITestSeed"])
        let chat = app.buttons["home.memoryChat"]
        for _ in 0..<6 where !chat.isHittable { app.swipeUp() }
        XCTAssertTrue(chat.waitForExistence(timeout: 8))
        XCTAssertTrue(chat.isHittable)
        snap("14-home-discovery")
        chat.tap()
        XCTAssertTrue(app.navigationBars["שיחה עם הזיכרון"].waitForExistence(timeout: 8))
        snap("15-local-memory-chat")
    }

    func testSettingsDescribeOnDeviceHebrew() {
        let app = launch(["-UITestReset"])
        app.buttons["הגדרות ופרטיות"].tap()
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Tesseract")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        snap("06-settings-on-device")
    }

    func testLargeTextAndDarkModeKeepTheTabsReachable() {
        let app = launch(["-UITestReset", "-UITestDark", "-UITestLargeText"])
        for name in ["בית", "ספרייה", "המוח", "מרחבים", "הצעד הבא"] {
            let tab = app.tabBars.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 8))
            XCTAssertTrue(tab.isHittable)
        }
        snap("07-large-text-dark")
    }

    func testBulkScanExplainsTheWholeAlbumBeforeItStarts() {
        let app = launch(["-UITestReset"])
        let scan = app.buttons["סרוק את כל צילומי המסך"]
        XCTAssertTrue(scan.waitForExistence(timeout: 8))
        scan.tap()
        XCTAssertTrue(app.buttons["סרוק הכול"].waitForExistence(timeout: 5))
        snap("08-album-confirm")
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
        snap("09-album-paused")
    }

    func testCleanupRequiresVerifiedBackupBeforeDeletion() {
        let app = launch(["-UITestSeed"])
        let open = app.buttons["בדוק מה אפשר לפנות"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        if !open.isHittable { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.staticTexts["כפילויות"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["שתף כ־Markdown"].exists)
        XCTAssertTrue(app.buttons["שתף כטקסט"].exists)
        XCTAssertTrue(app.staticTexts["בלי טקסט מועיל"].exists)
        let savedHeading = app.staticTexts["הטקסט כבר שמור"]
        if !savedHeading.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(savedHeading.waitForExistence(timeout: 3))
        let selectJunk = app.buttons["בחר את כל מה שבלי טקסט מועיל"]
        XCTAssertTrue(selectJunk.waitForExistence(timeout: 5))
        if selectJunk.frame.minY < 140 { app.swipeDown() }
        selectJunk.tap()
        let chosen = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "נבחר", "לא נבחר")).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["מחק את הבחירה מתמונות"].exists)
        app.buttons["ייצא ובדוק עותק לפני פינוי"].tap()
        XCTAssertTrue(app.navigationBars["שמירה ופינוי"].waitForExistence(timeout: 5))
        let deletion = app.buttons["verifiedPhotoDeletion"]
        for _ in 0..<6 {
            if deletion.exists && deletion.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(deletion.waitForExistence(timeout: 5))
        XCTAssertFalse(deletion.isEnabled)
        snap("10-cleanup-verified-only")
    }

    func testNewScreenshotCardDoesNotOfferDirectDeletion() {
        let app = launch(["-UITestReset", "-UITestSpaceOffer"])
        let options = app.buttons["פינוי תמונות (רשות)"]
        for _ in 0..<5 where !options.isHittable { app.swipeUp() }
        XCTAssertTrue(options.waitForExistence(timeout: 8))
        options.tap()
        XCTAssertTrue(app.staticTexts["2 צילומים חדשים נשמרו במוח."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["מחק מהתמונות"].exists)
        XCTAssertTrue(app.staticTexts["המקור נשאר בתמונות. אפשר לעיין בצילומים בלי למחוק אותם."].exists)
        snap("11-space-card-safe")
        app.buttons["השאר"].tap()
        let headline = app.staticTexts["2 צילומים חדשים נשמרו במוח."]
        XCTAssertTrue(headline.waitForNonExistence(timeout: 5))
    }
}
