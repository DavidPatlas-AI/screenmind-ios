import XCTest
import UIKit
@testable import ScreenMind

@MainActor final class ScreenMindTests: XCTestCase {
    func testReviewSessionKeepsBatchStableAndOnlyExportsApprovedItems() {
        var session = ReviewSession(ids: ["first", "second", "first", "third"])
        XCTAssertEqual(session.ids, ["first", "second", "third"])
        // A stale save callback must not approve a different or already resolved item.
        session.finish("second", as: .approved)
        XCTAssertEqual(session.resolvedCount, 0)
        session.finish("first", as: .deferred)
        session.finish("first", as: .approved)
        XCTAssertEqual(session.currentID, "second")
        XCTAssertTrue(session.approvedIDs.isEmpty)
        session.finish("second", as: .approved)
        session.finish("third", as: .archived)
        XCTAssertNil(session.currentID)
        XCTAssertEqual(session.approvedIDs, Set(["second"]))
        XCTAssertEqual(session.deferredCount, 1)
        XCTAssertEqual(session.archivedCount, 1)
    }
    func testReviewSessionNeverExceedsExportBatchLimit() {
        let session = ReviewSession(ids: (0..<35).map { "source-\($0)" })
        XCTAssertEqual(session.ids.count, 20)
        XCTAssertEqual(session.currentID, "source-0")
        XCTAssertNil(ReviewSession(ids: []).currentID)
    }
    func testLegacyRecordDecodesWithoutNewActionFields() throws {
        let capture = Capture(id: String(repeating: "a", count: 64), originalName: "source.png", createdAt: Date(), title: "רעיון", text: "פרטים", source: "picker")
        let restored = try JSONDecoder().decode(Capture.self, from: JSONEncoder().encode(capture))
        XCTAssertNil(restored.taskTitle)
        XCTAssertFalse(restored.hasTask)
    }
    func testBriefKeepsUserTaskAndSourceIdentity() {
        var capture = Capture(id: String(repeating: "a", count: 64), originalName: "source.png", createdAt: Date(), title: "פינת עבודה", text: "מידות", source: "picker")
        capture.collection = "הבית"; capture.intent = .act; capture.taskTitle = "למדוד את השולחן"
        XCTAssertTrue(capture.hasTask)
        let brief = CollectionBrief.text(name: "הבית", captures: [capture])
        XCTAssertTrue(brief.contains("למדוד את השולחן"))
        XCTAssertTrue(brief.contains(capture.id))
        capture.isArchived = true
        XCTAssertFalse(CollectionBrief.text(name: "הבית", captures: [capture]).contains(capture.id))
    }
    func testCleanupRequiresEveryCheck() {
        let all = CleanupFacts(reviewed: true, viewedOriginal: true, archiveMatches: true,
                               externalBackupMatches: true, exactPhotoMatches: true, isUneditedScreenshot: true)
        XCTAssertTrue(all.permitsDeletion)
        for missing in 0..<6 {
            var flags = Array(repeating: true, count: 6)
            flags[missing] = false
            let facts = CleanupFacts(reviewed: flags[0], viewedOriginal: flags[1], archiveMatches: flags[2],
                                     externalBackupMatches: flags[3], exactPhotoMatches: flags[4], isUneditedScreenshot: flags[5])
            XCTAssertFalse(facts.permitsDeletion)
        }
    }
    func testStandardCRCAndZipSignatures() throws {
        XCTAssertEqual(BackupArchive.crc32(Data("123456789".utf8)), 0xcbf43926)
        let zip = try BackupArchive.zip([("מקור.txt", Data("שלום".utf8)), ("manifest.json", Data("{}".utf8))])
        XCTAssertEqual(Array(zip.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertEqual(Array(zip.suffix(22).prefix(4)), [0x50, 0x4b, 0x05, 0x06])
        XCTAssertTrue(zip.range(of: Data("מקור.txt".utf8)) != nil)
    }
    func testOriginalsPersistAndDuplicateImportKeepsCorrections() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(rootURL: directory)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let bytes = renderer.pngData { context in UIColor.systemGreen.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
        let first = try vault.save(data: bytes, name: "capture.png", photoIdentifier: nil, source: "share")
        try vault.update(first.id) { $0.title = "כותרת שבחרתי"; $0.reviewedAt = Date() }
        let duplicate = try vault.save(data: bytes, name: "capture.png", photoIdentifier: "photo/identifier", source: "scan")
        XCTAssertEqual(duplicate.title, "כותרת שבחרתי")
        XCTAssertEqual(duplicate.photoIdentifier, "photo/identifier")
        XCTAssertEqual(try vault.all().count, 1)
        XCTAssertEqual(try vault.original(duplicate), bytes)
        try Data("changed".utf8).write(to: vault.originalURL(duplicate), options: .atomic)
        XCTAssertThrowsError(try vault.original(duplicate))
    }
    func testInvalidImageDoesNotCreateRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(rootURL: directory)
        XCTAssertThrowsError(try vault.save(data: Data("not an image".utf8), name: "../image.png", photoIdentifier: nil, source: "share"))
        XCTAssertTrue(try vault.all().isEmpty)
    }
    func testStatusBarChromeIsDroppedAndTopStripIsMeasured() {
        XCTAssertTrue(TextRecognition.isStatusBarChrome("5G"))
        XCTAssertTrue(TextRecognition.isStatusBarChrome("16:12"))
        XCTAssertTrue(TextRecognition.isStatusBarChrome("87%"))
        XCTAssertTrue(TextRecognition.isStatusBarChrome("LTE"))
        XCTAssertFalse(TextRecognition.isStatusBarChrome("TOPMARK"))
        XCTAssertFalse(TextRecognition.isStatusBarChrome("חשוב לזכור את המועד"))
        XCTAssertEqual(
            TextRecognition.dropStatusBarChrome(["5G", "חשוב לזכור", "16:12", "פרטים נוספים"]),
            ["חשוב לזכור", "פרטים נוספים"]
        )
        XCTAssertEqual(TextRecognition.statusBarCropPixels(imageHeight: 1600), 128)
        XCTAssertEqual(TextRecognition.statusBarCropPixels(imageHeight: 2532), 203)
        XCTAssertEqual(TextRecognition.cleanedLines(from: "5G\nשלום עולם\n16:12"), ["שלום עולם"])
    }
    func testVisualHebrewIsReversedOnlyWhenFinalFormsSitAtWordStarts() {
        XCTAssertEqual(TextRecognition.normalizePossibleVisualHebrew("שלום עולם"), "שלום עולם")
        XCTAssertEqual(TextRecognition.normalizePossibleVisualHebrew("םלוע םולש"), "שלום עולם")
        XCTAssertEqual(TextRecognition.normalizePossibleVisualHebrew("Meeting at 5"), "Meeting at 5")
        XCTAssertEqual(TextRecognition.normalizePossibleVisualHebrew("שלום 50"), "שלום 50")
        XCTAssertEqual(TextRecognition.normalizePossibleVisualHebrew("םולש 50"), "50 שלום")
        XCTAssertEqual(TextRecognition.normalizePossibleVisualHebrew("50.00 םלוע םולש"), "שלום עולם 50.00")
        XCTAssertEqual(TextRecognition.normalizePossibleVisualHebrew("םלוע Meeting םולש"), "שלום Meeting עולם")
    }
    func testHebrewLineBoxesAreJoinedRightToLeft() {
        let lines = [
            OCRLine(text: "שני", boundingBox: CGRect(x: 0.10, y: 0.70, width: 0.20, height: 0.05)),
            OCRLine(text: "ראשון", boundingBox: CGRect(x: 0.60, y: 0.70, width: 0.25, height: 0.05)),
            OCRLine(text: "למטה", boundingBox: CGRect(x: 0.20, y: 0.40, width: 0.30, height: 0.05))
        ]
        XCTAssertEqual(TextRecognition.orderedLines(lines), ["ראשון שני", "למטה"])
    }
    func testAccurateRecognitionStaysOffWithoutAKey() {
        XCTAssertFalse(AccurateRecognition.isEnabled(environmentKey: nil))
        XCTAssertFalse(AccurateRecognition.isEnabled(environmentKey: "   "))
        XCTAssertTrue(AccurateRecognition.isEnabled(environmentKey: "present"))
        XCTAssertFalse(AccurateRecognition.unavailableMessage.isEmpty)
    }
    func testHebrewSampleImageIsReadAndSkipsTheStatusBar() throws {
        XCTAssertTrue(TextRecognition.hebrewDataAvailable, "heb.traineddata and eng.traineddata must be in the app bundle")
        let bundle = Bundle(for: ScreenMindTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "hebrew-sample", withExtension: "png"))
        let result = try TextRecognition.recognizeSync(try Data(contentsOf: url))
        let letters = TextRecognition.hebrewLetters(in: result.text)
        XCTAssertTrue(letters.contains("שלוםעולם"), result.text)
        XCTAssertTrue(letters.contains("מהחשובלזכור"), result.text)
        XCTAssertTrue(letters.contains("תחתית"), result.text)
        XCTAssertFalse(result.text.contains("TOPMARK"), result.text)
        XCTAssertFalse(result.text.contains("5G"), result.text)
        XCTAssertFalse(result.text.contains("16:12"), result.text)
        XCTAssertFalse(letters.contains("םלועםולש"), result.text)
        XCTAssertTrue(result.hebrewSupported)
    }
}
