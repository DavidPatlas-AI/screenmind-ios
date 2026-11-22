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
    func testBrainGroupsSpacesKeywordsAndIntentWithoutTheArchive() {
        let now = Date(timeIntervalSince1970: 1_763_769_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let homeTable = idea("home-table", title: "שולחן אלון", text: "מידות פסטה", collection: "הבית", at: now)
        let homeLamp = idea("home-lamp", title: "מנורה", text: "אור חם", collection: "הבית", at: now.addingTimeInterval(10))
        let pastaA = idea("pasta-a", title: "ספק פסטה", text: "מחיר", intent: .act, at: now.addingTimeInterval(20))
        let pastaB = idea("pasta-b", title: "פסטה סדנה", text: "מתכון", intent: .act, at: now.addingTimeInterval(30))
        let supplier = idea("supplier", title: "ספק אחר", text: "טלפון", at: now.addingTimeInterval(40))
        let extra = idea("extra", title: "ספק נוסף", text: "טלפון", at: now.addingTimeInterval(45))
        let leftover = idea("leftover", title: "של החשבון", text: "את את", at: now.addingTimeInterval(50))
        var archived = idea("archived", title: "פסטה ישנה", text: "פסטה", collection: "הבית", at: now)
        archived.isArchived = true
        let graph = BrainGraph.build(from: [homeTable, homeLamp, pastaA, pastaB, supplier, extra, leftover, archived], now: now, calendar: calendar)

        let home = try XCTUnwrap(graph.node("topic:space:הבית"))
        XCTAssertEqual(home.count, 2)
        XCTAssertEqual(graph.childIDs[home.id]?.count, 2)
        XCTAssertFalse(graph.nodes.values.contains { $0.captureID == archived.id })

        let pasta = try XCTUnwrap(graph.node("topic:word:פסטה"))
        XCTAssertEqual(Set(graph.childIDs[pasta.id] ?? []), Set(["item:pasta-a", "item:pasta-b"]))
        XCTAssertEqual(Set(graph.childIDs["topic:word:ספק"] ?? []), Set(["item:supplier", "item:extra"]))
        XCTAssertEqual(graph.node(BrainGraph.openTopicID)?.title, "רעיונות פתוחים")
        XCTAssertEqual(graph.childIDs[BrainGraph.openTopicID], ["item:leftover"])
        XCTAssertTrue(graph.links.contains { $0.label == "פסטה" && Set([$0.fromID, $0.toID]) == Set([home.id, pasta.id]) })
        XCTAssertTrue(graph.links.allSatisfy { degree($0.fromID, graph) <= 3 && degree($0.toID, graph) <= 3 })
    }
    func testBrainMomentsAreOpenTasksDueTodayOrEarlier() {
        let now = Date(timeIntervalSince1970: 1_763_769_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: now)
        let due = idea("due", title: "לחזור לספק", text: "פסטה", intent: .act, task: "להתקשר", due: today.addingTimeInterval(-3600))
        let later = idea("later", title: "לחזור אחר כך", text: "מנורה", intent: .act, task: "להשוות", due: calendar.date(byAdding: .day, value: 5, to: today))
        var done = idea("done", title: "כבר בוצע", text: "שולחן", intent: .act, task: "למדוד", due: today.addingTimeInterval(-3600))
        done.taskCompletedAt = now
        let unreviewed = idea("draft", title: "טיוטה", text: "רעיון", intent: .act, task: "לכתוב", due: today, reviewed: nil)
        let graph = BrainGraph.build(from: [due, later, done, unreviewed], now: now, calendar: calendar)
        XCTAssertEqual(graph.momentIDs, ["due"])
        XCTAssertTrue(graph.node("item:due")?.moment == true)
        XCTAssertTrue(graph.node("item:later")?.moment == false)
    }
    func testBrainLayoutStaysInsideTheViewportForHundredsOfItems() {
        let now = Date(timeIntervalSince1970: 1_763_769_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var captures: [Capture] = []
        for index in 0..<240 {
            captures.append(idea("pile-\(index)", title: "פריט \(index)", text: "ייחודי\(index)", collection: "פרויקט", at: now.addingTimeInterval(Double(index))))
        }
        for index in 0..<5 {
            captures.append(idea("hub-\(index)", title: "מילה\(index)", text: "גשר\(index)", collection: "מרכז", at: now))
            captures.append(idea("leaf-\(index)", title: "מילה\(index) צד", text: "אחר\(index)", collection: "עלה\(index)", at: now))
        }
        let graph = BrainGraph.build(from: captures, now: now, calendar: calendar)
        let root = BrainLayout.scene(graph: graph, focusID: BrainGraph.rootID, viewportWidth: 390)
        XCTAssertEqual(root.placements.count, 1 + (graph.childIDs[BrainGraph.rootID]?.count ?? 0))
        XCTAssertLessThan(root.placements.count, captures.count)
        assertInside(root)
        let topics = root.placements.filter { graph.node($0.id)?.kind == .topic }
        XCTAssertGreaterThanOrEqual(topics.count, 2)
        XCTAssertGreaterThan(topics[0].center.x, topics[1].center.x)
        XCTAssertEqual(root.hit(topics[0].center), topics[0].id)
        XCTAssertNil(root.hit(BrainPoint(x: -4, y: -4)))

        let project = try XCTUnwrap(graph.node("topic:space:פרויקט"))
        let drilled = BrainLayout.scene(graph: graph, focusID: project.id, viewportWidth: 390)
        XCTAssertEqual(drilled.placements.filter { graph.node($0.id)?.kind == .capture }.count, 240)
        assertInside(drilled)
        XCTAssertTrue(graph.links.allSatisfy { degree($0.fromID, graph) <= 3 && degree($0.toID, graph) <= 3 })
        let unrelated = BrainGraph.build(from: [
            idea("trip", title: "מזוודה", text: "דרכון", collection: "הטיול", at: now),
            idea("room", title: "שולחן", text: "כיסא", collection: "הבית", at: now)
        ], now: now, calendar: calendar)
        XCTAssertTrue(unrelated.links.isEmpty)
    }

    func testTwentyFiveHundredScreenshotsStayBatchedAndCluster() {
        let identifiers = (0..<2500).map { String(format: "asset-%04d", $0) }
        var done = Set(identifiers.prefix(800))
        var steps = 0
        let started = Date()
        while true {
            let batch = AlbumPlan.nextBatch(all: identifiers, done: done)
            if batch.isEmpty { break }
            XCTAssertLessThanOrEqual(batch.count, AlbumPlan.batchSize)
            XCTAssertTrue(batch.allSatisfy { !done.contains($0) })
            done.formUnion(batch)
            steps += 1
            if steps > 3000 { XCTFail("the batch plan did not finish"); return }
        }
        XCTAssertEqual(done.count, 2500)
        XCTAssertEqual(steps, 425)
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        var captures: [Capture] = []
        var fingerprints: [String: UInt64] = [:]
        captures.reserveCapacity(2500)
        for index in 0..<2500 {
            let text = index % 17 == 0 ? "" : "טקסט שמור \(index) מילה"
            var capture = idea("cap-\(index)", title: "צילום \(index)", text: text, at: moment.addingTimeInterval(Double(index)))
            capture.photoIdentifier = identifiers[index]
            capture.textStatus = text.isEmpty ? "noText" : "complete"
            captures.append(capture)
            var hash = UInt64(index &+ 1)
            let mixed = (UInt64(0x9E37_79B9) << 32) | UInt64(0x7F4A_7C15)
            hash = hash &* mixed
            hash ^= hash >> 30
            fingerprints[capture.id] = index == 1 ? fingerprints["cap-0"] ?? 0 : hash
        }
        let plan = CleanupPlan.build(captures: captures, fingerprints: fingerprints)
        let covered = plan.duplicates + plan.junk + plan.textSaved
        XCTAssertEqual(Set(covered).count, covered.count)
        XCTAssertEqual(Set(covered).count, 2500)
        XCTAssertTrue(plan.duplicates.contains("cap-0"))
        XCTAssertTrue(NotesExport.markdown(captures).contains("טקסט שמור 1 מילה"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testCleanupKeepsFavoritesAndSplitsDuplicatesFromJunk() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var favorite = idea("fav", title: "חשוב", text: "טקסט חשוב לשמור בבית", at: now)
        favorite.isFavorite = true
        favorite.photoIdentifier = "fav-photo"
        var copy = idea("copy", title: "עותק", text: "טקסט חשוב לשמור בבית", at: now.addingTimeInterval(10))
        copy.photoIdentifier = "copy-photo"
        var junk = idea("junk", title: "רעש", text: "", at: now.addingTimeInterval(20))
        junk.photoIdentifier = "junk-photo"
        junk.textStatus = "noText"
        var saved = idea("saved", title: "פתק ארוך", text: "רשימת קניות לשבת בבוקר", at: now.addingTimeInterval(30))
        saved.photoIdentifier = "saved-photo"
        var task = idea("task", title: "שיחה", text: "להתקשר לספק מחר בבוקר", intent: .act, task: "להתקשר", at: now)
        task.photoIdentifier = "task-photo"
        let plan = CleanupPlan.build(
            captures: [favorite, copy, junk, saved, task],
            fingerprints: [
                favorite.id: 0,
                copy.id: 0,
                junk.id: UInt64(0xFFFF_FFFF) << 32,
                saved.id: UInt64(0xFFFF_FFFF),
                task.id: (UInt64(0xFFFF) << 48) | (UInt64(0xFFFF) << 16)
            ]
        )
        XCTAssertEqual(plan.duplicates, ["copy"])
        XCTAssertEqual(plan.junk, ["junk"])
        XCTAssertEqual(plan.textSaved, ["saved"])
        XCTAssertFalse(plan.duplicates.contains("fav"))
        XCTAssertFalse(plan.textSaved.contains("task"))
        XCTAssertFalse(plan.junk.contains("task"))
    }

    func testNearDuplicateHashIgnoresATinyPixelChange() {
        var similar = [UInt8](repeating: 0, count: 9 * 8)
        for index in similar.indices { similar[index] = UInt8((index * 3) % 250) }
        var noisy = similar
        noisy[0] = noisy[0] &+ 2
        var other = [UInt8](repeating: 0, count: 9 * 8)
        for index in other.indices { other[index] = UInt8(255 - (index % 40)) }
        let close = ImageFingerprint.dHash(pixels: similar, width: 9, height: 8)
        let shifted = ImageFingerprint.dHash(pixels: noisy, width: 9, height: 8)
        let far = ImageFingerprint.dHash(pixels: other, width: 9, height: 8)
        XCTAssertLessThanOrEqual(ImageFingerprint.hamming(close, shifted), ImageFingerprint.nearDistance)
        XCTAssertGreaterThan(ImageFingerprint.hamming(close, far), ImageFingerprint.nearDistance)
    }

    func testAlbumResumeEtaAndReducedPixels() {
        XCTAssertTrue(AlbumPlan.shouldResume(.interrupted))
        for status in [AlbumScanStatus.paused, .cancelled, .finished, .running, .idle] {
            XCTAssertFalse(AlbumPlan.shouldResume(status))
        }
        XCTAssertEqual(AlbumPlan.etaLabel(30), "עוד פחות מדקה")
        XCTAssertEqual(AlbumPlan.etaLabel(120), "עוד כ־2 דקות")
        XCTAssertEqual(AlbumPlan.etaLabel(3600), "עוד כשעה")
        XCTAssertEqual(AlbumPlan.etaLabel(7200), "עוד כ־2 שעות")
        let shrunk = AlbumPlan.pixelSize(width: 1170, height: 2532)
        XCTAssertEqual(shrunk.1, 1280)
        XCTAssertLessThan(shrunk.0, 1170)
        XCTAssertEqual(AlbumPlan.pixelSize(width: 80, height: 40).0, 80)
        let note = idea("note", title: "שלום", text: "עולם שמור כאן", at: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(NotesExport.markdown([note]).contains("עולם שמור כאן"))
        XCTAssertTrue(NotesExport.plain([note]).contains("שלום"))
        XCTAssertFalse(NotesExport.markdown([note]).contains("API_KEY"))
    }

    private func degree(_ id: String, _ graph: BrainGraph) -> Int {
        graph.links.filter { $0.fromID == id || $0.toID == id }.count
    }
    private func assertInside(_ scene: BrainScene, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(scene.contentWidth, 390, accuracy: 0.001, file: file, line: line)
        for placement in scene.placements {
            XCTAssertGreaterThanOrEqual(placement.center.x - placement.width / 2, -0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(placement.center.x + placement.width / 2, scene.contentWidth + 0.001, file: file, line: line)
            XCTAssertGreaterThanOrEqual(placement.center.y - placement.height / 2, -0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(placement.center.y + placement.height / 2, scene.contentHeight + 0.001, file: file, line: line)
        }
    }
    private func idea(_ id: String, title: String, text: String, collection: String = "כללי", intent: SaveIntent = .remember, task: String? = nil, due: Date? = nil, reviewed: Date? = Date(timeIntervalSince1970: 1_700_000_000), at: Date) -> Capture {
        var capture = Capture(id: id, originalName: "\(id).png", createdAt: at, title: title, text: text, source: "test")
        capture.collection = collection
        capture.intent = intent
        capture.taskTitle = task
        capture.taskDueAt = due
        capture.reviewedAt = reviewed
        return capture
    }
}
