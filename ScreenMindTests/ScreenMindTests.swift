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
        // Twelve Latin letters need at least as many Hebrew letters before a line is treated as visual Hebrew.
        XCTAssertEqual(TextRecognition.normalizePossibleVisualHebrew("םלוע Meeting Notes םולש"), "םלוע Meeting Notes םולש")
        XCTAssertEqual(TextRecognition.normalizePossibleVisualHebrew("םולש םלוע Meeting Notes םולש"), "שלום Meeting Notes עולם שלום")
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
    func testBrainGroupsSpacesKeywordsAndIntentWithoutTheArchive() throws {
        let now = Date(timeIntervalSince1970: 1_763_769_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let homeTable = idea("home-table", title: "שולחן אלון", text: "מידות פסטה", collection: "הבית", at: now)
        let homeLamp = idea("home-lamp", title: "מנורה", text: "אור חם", collection: "הבית", at: now.addingTimeInterval(10))
        let pastaA = idea("pasta-a", title: "ספק פסטה", text: "מחיר מתכון", intent: .act, at: now.addingTimeInterval(20))
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

        let pasta = try XCTUnwrap(graph.node("topic:smart:food"))
        XCTAssertEqual(Set(graph.childIDs[pasta.id] ?? []), Set(["item:pasta-a", "item:pasta-b"]))
        XCTAssertEqual(Set(graph.childIDs["topic:smart:work"] ?? []), Set(["item:supplier", "item:extra"]))
        XCTAssertEqual(graph.node(BrainGraph.openTopicID)?.title, "רעיונות פתוחים")
        XCTAssertEqual(graph.childIDs[BrainGraph.openTopicID], ["item:leftover"])
        XCTAssertTrue(graph.links.contains { $0.label == "פסטה" && Set([$0.fromID, $0.toID]) == Set([home.id, pasta.id]) })
        XCTAssertTrue(graph.links.allSatisfy { degree($0.fromID, graph) <= 3 && degree($0.toID, graph) <= 3 })
    }
    func testSmartTopicsAvoidChromeAndSupportSeveralLanguages() {
        XCTAssertNil(SmartTopic.classify(title: "add audio לכל שר שי", text: "private aviv"))
        XCTAssertEqual(SmartTopic.classify(title: "מדריך", text: "SwiftUI GitHub Python"), .technology)
        XCTAssertEqual(SmartTopic.classify(title: "Оплата", text: "квитанция"), .finance)
        XCTAssertEqual(SmartTopic.classify(title: "Receta", text: "ingredientes"), .food)
        XCTAssertEqual(SmartTopic.classify(title: "Programmation", text: "GitHub"), .technology)
        XCTAssertEqual(SmartTopic.classify(title: "برمجة", text: "ذكاء اصطناعي"), .technology)
        XCTAssertNil(SmartTopic.classify(title: "GitHub", text: "hotel"))
    }
    func testLegacyCaptureWithoutPhotoDatePreservesUserData() throws {
        var capture = idea("legacy", title: "כותרת אישית", text: "תוכן", collection: "פרויקט שלי", at: Date())
        capture.isFavorite = true
        let encoded = try JSONEncoder().encode(capture)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "photoCreatedAt")
        let decoded = try JSONDecoder().decode(Capture.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(decoded.id, capture.id)
        XCTAssertEqual(decoded.title, capture.title)
        XCTAssertEqual(decoded.collection, capture.collection)
        XCTAssertTrue(decoded.isFavorite)
        XCTAssertEqual(decoded.reviewedAt, capture.reviewedAt)
        XCTAssertNil(decoded.photoCreatedAt)
        XCTAssertEqual(decoded.sourceDate, decoded.createdAt)
    }
    func testProjectDiscoveryUsesExplicitRepeatedIdentityAndChronology() {
        let now = Date(timeIntervalSince1970: 1_763_769_600)
        var newer = idea("new", title: "Build", text: "https://github.com/example/my-app/issues/7", at: now)
        var older = idea("old", title: "Research", text: "github.com/Example/My-App.git", at: now.addingTimeInterval(20))
        newer.photoCreatedAt = now
        older.photoCreatedAt = now.addingTimeInterval(-100)
        let ambiguous = idea("ambiguous", title: "Links", text: "github.com/example/my-app and other.netlify.app", at: now)
        let single = idea("single", title: "Demo", text: "other.netlify.app", at: now)
        var archived = idea("archived", title: "Old", text: "github.com/example/my-app", at: now)
        archived.isArchived = true
        let groups = ProjectCluster.build(from: [newer, older, ambiguous, single, archived])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.id, "github:example/my-app")
        XCTAssertEqual(groups.first?.sources.map(\.id), ["old", "new"])
        XCTAssertTrue(groups.first?.brief.contains("מזהה מקור: old") == true)
        XCTAssertEqual(ProjectIdentity.detect(in: "github.com/features/copilot").count, 0)
        XCTAssertEqual(ProjectIdentity.detect(in: "evilgithub.com/example/my-app").count, 0)
    }
    func testAIAnalysisIsSeparateReversibleAndInvalidatedByEdits() throws {
        var capture = idea("ai", title: "raw", text: "invoice payment", reviewed: nil, at: Date())
        capture.aiAnalysis = AIAnalysis(sourceDigest: capture.aiSourceDigest, title: "כותרת AI",
            summary: "סיכום מוצע", topic: "finance", suggestedTask: "לבדוק תשלום", language: "he")
        XCTAssertEqual(capture.displayTitle, "כותרת AI")
        XCTAssertEqual(capture.effectiveCollection, "כספים ותשלומים")
        XCTAssertEqual(capture.title, "raw")
        XCTAssertEqual(capture.text, "invoice payment")
        XCTAssertNil(capture.taskTitle)
        XCTAssertNil(capture.reviewedAt)
        let saved = try JSONDecoder().decode(Capture.self, from: JSONEncoder().encode(capture))
        XCTAssertEqual(saved.currentAIAnalysis, capture.currentAIAnalysis)
        capture.collection = "התיקייה שלי"
        XCTAssertEqual(capture.effectiveCollection, "התיקייה שלי")
        capture.text = "GitHub SwiftUI"
        XCTAssertNil(capture.currentAIAnalysis)
        XCTAssertEqual(capture.smartTopic, .technology)
    }
    func testStoryKeepsChronologyAndDoesNotInventTasks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let earlier = now.addingTimeInterval(-60 * 86400)
        var first = idea("first", title: "תכנון ראשון", text: "מקור ראשון", at: now)
        first.photoCreatedAt = earlier
        var second = idea("second", title: "שינוי", text: "מקור שני", intent: .act, task: "בדוק את המודל", at: earlier)
        second.photoCreatedAt = now
        let uncertain = idea("unknown", title: "תאריך לא ידוע", text: "תיעוד", intent: .act, task: "טיוטה לא מאושרת", reviewed: nil, at: earlier)
        var archived = first
        archived.id = "archived"
        archived.isArchived = true
        let story = StoryDraft.build(title: "פרויקט", captures: [second, uncertain, first, archived, first])
        XCTAssertEqual(story.entries.map(\.id), ["first", "second", "unknown"])
        XCTAssertEqual(story.known.map(\.id), ["first", "second"])
        XCTAssertEqual(story.unknown.map(\.id), ["unknown"])
        XCTAssertEqual(story.tasks.map(\.id), ["second"])
        XCTAssertEqual(story.total, 3)
        XCTAssertTrue(story.html().contains("תאריך צילום לא ידוע"))
        XCTAssertTrue(story.html().contains("בדוק את המודל"))
        XCTAssertFalse(story.html().contains("טיוטה לא מאושרת"))
        XCTAssertFalse(story.html(includeTasks: false).contains("בדוק את המודל"))
    }
    func testStoryHTMLEscapesUntrustedTextAndDisclosesOmissions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sources = (0..<50).map { n -> Capture in
            var item = idea("story-\(n)", title: "פרק \(n)", text: "<script>alert('x')</script> & text",
                            at: now)
            item.photoCreatedAt = now.addingTimeInterval(Double(n))
            return item
        }
        let draft = StoryDraft.build(title: "<img src=evil>", captures: sources)
        XCTAssertEqual(draft.entries.count, 40)
        XCTAssertEqual(draft.omitted, 10)
        XCTAssertEqual(draft.entries.first?.id, "story-0")
        XCTAssertEqual(draft.entries.last?.id, "story-49")
        XCTAssertTrue(draft.introduction.contains("10"))
        let html = draft.html()
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("&amp; text"))
        XCTAssertTrue(html.contains("&lt;img src=evil&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<img src=evil>"))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("source-40"))
    }

    func testRediscoveryRequiresRealPhotoDatesAndSharedProjectEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let older = now.addingTimeInterval(-90 * 86400)
        let recent = now.addingTimeInterval(-5 * 86400)
        var original = idea("old", title: "First plan", text: "github.com/example/project", at: now)
        original.photoCreatedAt = older
        var updated = idea("new", title: "New plan", text: "github.com/example/project", at: now)
        updated.photoCreatedAt = recent
        var imported = idea("imported", title: "Uncertain", text: "github.com/example/project", at: older)
        imported.photoCreatedAt = nil
        var archived = idea("archived", title: "Hidden", text: "github.com/example/project", at: now)
        archived.photoCreatedAt = now
        archived.isArchived = true
        let suggestions = MemoryDiscovery.build(from: [original, updated, imported, archived], now: now)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.kind, .project)
        XCTAssertEqual(suggestions.first?.sourceIDs, ["old", "new"])
        XCTAssertTrue(MemoryDiscovery.build(from: [original, imported], now: now).isEmpty)
    }
    func testRediscoveryDoesNotInventTasksOrExposeArchivedFavorites() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-90 * 86400)
        var favorite = idea("favorite", title: "Saved manual", text: "reference", at: now)
        favorite.photoCreatedAt = old
        favorite.isFavorite = true
        var seen = favorite
        seen.id = "seen"
        seen.viewedAt = now
        var archived = favorite
        archived.id = "archived"
        archived.isArchived = true
        let approved = idea("due", title: "Approved", text: "reference", intent: .act, task: "Check document", due: old, at: now)
        let draft = idea("draft", title: "Draft", text: "reference", intent: .act, task: "Not approved", due: old, reviewed: nil, at: now)
        var completed = approved
        completed.id = "completed"
        completed.taskCompletedAt = now
        let result = MemoryDiscovery.build(from: [favorite, seen, archived, approved, draft, completed], now: now)
        XCTAssertEqual(Set(result.flatMap(\.sourceIDs)), Set(["favorite", "due"]))
        XCTAssertEqual(result.first?.kind, .dueTask)
    }

    func testLexicalRetrievalQualityAtLibraryScale() {
        // Synthetic OCR only: no user's private screenshots, no network.
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let samples: [(String, String, String, String)] = [
            ("mortgage", "Mortgage approval", "Home loan reference 2831", "איפה שמרתי את המשכנתה"),
            ("recipe", "Рецепт", "Картофель и зелень", "מתכון"),
            ("course", "קורס מכונאות", "שיעורים ומנועים", "course"),
            ("truck", "Truck maintenance", "Hydraulic inspection", "משאית"),
            ("invoice", "חשבונית ספק", "פריט 4908", "invoice"),
            ("drone", "Дрон", "Обзор камер и управления", "רחפן"),
            ("backup", "Backup policy", "Archive checksums", "גיבוי"),
            ("hotel", "Hôtel", "Réservation à Lyon", "מלון"),
            ("budget", "Budget estimate", "Materials and labor", "תקציב"),
            ("scholarship", "Стипендия", "Условия поступления", "מלגה"),
            ("contract", "חוזה ספק", "סעיף 12", "contract"),
            ("code", "SwiftUI GitHub", "View architecture", "המדריך GitHub SwiftUI")
        ]
        let relevant = samples.map { idea($0.0, title: $0.1, text: $0.2, at: old) }
        var archived = idea("archived", title: "Mortgage approval", text: "Home loan", at: old)
        archived.isArchived = true
        let distractorTexts = ["audio add menu settings", "weather clouds sunset", "green pencil paper", "keyboard mouse display", "street tree window"]
        for size in [100, 200, 3000, 10000] {
            let distractors = (0..<(size - relevant.count - 1)).map { i in
                idea("noise-\(i)", title: "record \(i)", text: distractorTexts[i % distractorTexts.count],
                     at: old.addingTimeInterval(Double(i + 1)))
            }
            let start = Date()
            let index = MemoryLexicalIndex(captures: relevant + [archived] + distractors)
            let buildSeconds = Date().timeIntervalSince(start)
            let queryStart = Date()
            var top1 = 0, top5 = 0
            for (id, _, _, query) in samples {
                let hits = index.search(query, limit: 5)
                if hits.first?.id == id { top1 += 1 }
                if hits.contains(where: { $0.id == id }) { top5 += 1 }
                XCTAssertFalse(hits.contains(where: { $0.id == "archived" }))
            }
            let querySeconds = Date().timeIntervalSince(queryStart)
            print("MEMORY_BENCHMARK n=\(size) top1=\(top1)/\(samples.count) recallAt5=\(top5)/\(samples.count) indexSeconds=\(buildSeconds) querySeconds=\(querySeconds)")
            XCTAssertGreaterThanOrEqual(top5, 11)
            XCTAssertGreaterThanOrEqual(top1, 10)
            XCTAssertTrue(index.search("unfindablexyz").isEmpty)
            XCTAssertTrue(index.search("איפה שמרתי את").isEmpty)
        }
    }
    func testLexicalIndexUsesRareSpecificTermsAndRejectsCategoryOnlyMatches() {
        let now = Date()
        let specific = idea("specific", title: "Orion hydraulic repair", text: "truck pump", at: now)
        let generic = idea("generic", title: "Hydraulic repair", text: "general equipment", at: now)
        let category = idea("category", title: "unrelated", text: "wood", collection: "משאית", at: now)
        let index = MemoryLexicalIndex(captures: [generic, category, specific])
        XCTAssertEqual(index.search("Orion hydraulic").first?.id, "specific")
        XCTAssertFalse(index.search("משאית").contains(where: { $0.id == "category" }))
        XCTAssertEqual(index.search("משאית").first?.match, .related)
    }
    func testMemorySearchRanksRelevantWordsAndRejectsUnrelatedSources() {
        let now = Date()
        let capture = idea("code", title: "מדריך GitHub", text: "SwiftUI פיתוח אפליקציה", at: now)
        let unrelated = idea("food", title: "מתכון", text: "אורז וירקות", at: now)
        let hit = MemorySearchEngine.lexical(query: "איפה שמרתי את המדריך GitHub", capture: capture)
        // Hebrew prefixes are not stemmed by the deterministic fallback.
        XCTAssertNotNil(hit)
        XCTAssertNil(MemorySearchEngine.lexical(query: "GitHub SwiftUI", capture: unrelated))
        XCTAssertEqual(MemorySearchEngine.lexical(query: "GitHub SwiftUI", capture: capture)?.match, .exact)
        XCTAssertEqual(MemorySearchEngine.cosine([1, 0], [1, 0]), 1)
        XCTAssertEqual(MemorySearchEngine.cosine([1, 0], [0, 1]), 0)
        XCTAssertNil(MemorySearchEngine.cosine([0, 0], [1, 0]))
    }
    func testSmartTopicCacheRespectsEdits() {
        XCTAssertEqual(SmartTopic.classify(title: "same", text: "GitHub SwiftUI"), .technology)
        XCTAssertEqual(SmartTopic.classify(title: "same", text: "invoice payment"), .finance)
        XCTAssertNil(SmartTopic.classify(title: "same", text: "add audio"))
        XCTAssertNil(SmartTopic.classify(title: "same", text: "add audio"))
        XCTAssertEqual(SmartTopic.classify(title: "same", text: "GitHub SwiftUI"), .technology)
    }
    func testAutoGroupingNeverApprovesDeletionOrOverridesManualCollection() {
        let now = Date()
        var capture = idea("smart", title: "add", text: "GitHub SwiftUI programming guide", reviewed: nil, at: now)
        XCTAssertEqual(capture.effectiveCollection, "טכנולוגיה ופיתוח")
        XCTAssertTrue(capture.needsReview)
        XCTAssertEqual(capture.displayTitle, "GitHub SwiftUI programming guide")
        capture.collection = "הפרויקט שלי"
        XCTAssertEqual(capture.effectiveCollection, "הפרויקט שלי")
        capture.photoCreatedAt = now.addingTimeInterval(-86400)
        XCTAssertEqual(capture.sourceDate, capture.photoCreatedAt!)
        XCTAssertEqual(capture.createdAt, now)
    }
    func testBrainMomentsAreOpenTasksDueTodayOrEarlier() {
        let now = Date(timeIntervalSince1970: 1_763_769_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: now)
        let due = idea("due", title: "לחזור לספק", text: "פסטה", intent: .act, task: "להתקשר", due: today.addingTimeInterval(-3600), at: now)
        let later = idea("later", title: "לחזור אחר כך", text: "מנורה", intent: .act, task: "להשוות", due: calendar.date(byAdding: .day, value: 5, to: today), at: now)
        var done = idea("done", title: "כבר בוצע", text: "שולחן", intent: .act, task: "למדוד", due: today.addingTimeInterval(-3600), at: now)
        done.taskCompletedAt = now
        let unreviewed = idea("draft", title: "טיוטה", text: "רעיון", intent: .act, task: "לכתוב", due: today, reviewed: nil, at: now)
        let graph = BrainGraph.build(from: [due, later, done, unreviewed], now: now, calendar: calendar)
        XCTAssertEqual(graph.momentIDs, ["due"])
        XCTAssertTrue(graph.node("item:due")?.moment == true)
        XCTAssertTrue(graph.node("item:later")?.moment == false)
    }
    func testBrainLayoutStaysInsideTheViewportForHundredsOfItems() throws {
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

    func testTwentyFiveHundredGeneratedScreenshotsClusterWithinTheBudget() {
        let started = Date()
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        var captures: [Capture] = []
        var fingerprints: [String: UInt64] = [:]
        var jpegBytes = 0
        captures.reserveCapacity(2_500)
        for index in 0..<2_500 {
            let image: UIImage = autoreleasepool {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format)
                return renderer.image { context in
                    let shade = CGFloat((index * 37) % 220) / 255
                    UIColor(white: shade, alpha: 1).setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
                    UIColor(white: index.isMultiple(of: 2) ? 1 : 0, alpha: 1).setFill()
                    context.fill(CGRect(x: CGFloat(index % 16), y: CGFloat((index / 16) % 16), width: 10, height: 10))
                }
            }
            let jpeg = ScreenshotPixels.jpeg(image, quality: 0.5)
            XCTAssertNotNil(jpeg)
            jpegBytes += jpeg?.count ?? 0
            let pixels = ScreenshotPixels.grayscale(image, width: 9, height: 8) ?? []
            XCTAssertEqual(pixels.count, 72)
            let text = index % 17 == 0 ? "" : "טקסט שמור \(index) מילה"
            var capture = idea("gen-\(index)", title: "צילום \(index)", text: text, at: moment.addingTimeInterval(Double(index)))
            capture.photoIdentifier = String(format: "generated-%04d", index)
            capture.textStatus = text.isEmpty ? "noText" : "complete"
            captures.append(capture)
            fingerprints[capture.id] = ImageFingerprint.dHash(pixels: pixels, width: 9, height: 8)
        }
        fingerprints["gen-3"] = fingerprints["gen-2"]
        let plan = CleanupPlan.build(captures: captures, fingerprints: fingerprints)
        let graph = BrainGraph.build(from: captures, now: moment.addingTimeInterval(4_000))
        XCTAssertGreaterThan(jpegBytes, 2_500)
        XCTAssertEqual(captures.count, 2_500)
        XCTAssertTrue(plan.duplicates.contains("gen-3"))
        XCTAssertFalse(graph.nodes.isEmpty)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 90, "2,500 generated screenshots took \(elapsed) seconds")
    }

    func testCleanupKeepsFavoritesAndSplitsDuplicatesFromJunk() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var favorite = idea("fav", title: "חשוב", text: "טקסט חשוב לשמור בבית", at: now)
        favorite.isFavorite = true
        favorite.photoIdentifier = "fav-photo"
        favorite.textStatus = "complete"
        var copy = idea("copy", title: "עותק", text: "טקסט חשוב לשמור בבית", at: now.addingTimeInterval(10))
        copy.photoIdentifier = "copy-photo"
        copy.textStatus = "complete"
        var junk = idea("junk", title: "רעש", text: "", at: now.addingTimeInterval(20))
        junk.photoIdentifier = "junk-photo"
        junk.textStatus = "noText"
        var saved = idea("saved", title: "פתק ארוך", text: "רשימת קניות לשבת בבוקר", at: now.addingTimeInterval(30))
        saved.photoIdentifier = "saved-photo"
        saved.textStatus = "complete"
        var task = idea("task", title: "שיחה", text: "להתקשר לספק מחר בבוקר", intent: .act, task: "להתקשר", at: now)
        task.photoIdentifier = "task-photo"
        task.textStatus = "complete"
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
        var failed = idea("failed", title: "נכשל", text: "", at: now.addingTimeInterval(40))
        failed.photoIdentifier = "failed-photo"
        failed.textStatus = "failed"
        let held = CleanupPlan.build(captures: [failed], fingerprints: [failed.id: 1])
        XCTAssertTrue(held.junk.isEmpty)
        XCTAssertTrue(held.duplicates.isEmpty)
        XCTAssertTrue(held.textSaved.isEmpty)
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

    func testNewScreenshotsSkipKnownOnesAndFormatTheFreedSpace() {
        let now = Date()
        let fresh = NewShotPlan.fresh(
            identifiers: ["new", "old", "known"],
            created: [now, now.addingTimeInterval(-120), now],
            since: now.addingTimeInterval(-30),
            known: ["known"]
        )
        XCTAssertEqual(fresh, ["new"])
        let previous = now.addingTimeInterval(-60)
        XCTAssertEqual(NewShotPlan.nextSeen(newestIndexed: nil, previous: previous), previous)
        XCTAssertEqual(NewShotPlan.nextSeen(newestIndexed: now, previous: previous), now)
        XCTAssertEqual(NewShotPlan.nextSeen(newestIndexed: previous, previous: now), now)
        XCTAssertEqual(SpaceEstimate.label(3_400_000), "כ־3.4 MB")
        XCTAssertEqual(SpaceEstimate.label(500_000), "כ־500 KB")
        XCTAssertEqual(SpaceEstimate.label(2_000_000), "כ־2 MB")
        XCTAssertEqual(SpaceEstimate.bytes(fileBytes: 42, pixelWidth: 1000, pixelHeight: 1000), 42)
        XCTAssertEqual(SpaceEstimate.bytes(fileBytes: nil, pixelWidth: 100, pixelHeight: 50), 2_500)
        var favorite = idea("fav-shot", title: "חשוב", text: "טקסט חשוב לשמור בבית", at: now)
        favorite.isFavorite = true
        XCTAssertTrue(CleanupPlan.isImportant(favorite))
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
    func testVerifiedBackupChecksHashesAndConflicts() throws {
        let bytes = Data("synthetic source bytes".utf8)
        let id = Vault.hash(bytes)
        var capture = idea(id, title: "מקור", text: "טקסט", at: Date(timeIntervalSince1970: 1234))
        capture.isFavorite = true
        let files: [(String, Data)] = [
            ("sources/" + id + "-" + capture.originalName, bytes),
            ("manifest.json", try JSONEncoder().encode([capture])),
            ("README.txt", Data("Test backup".utf8))
        ]
        let zip = try BackupArchive.zip(files)
        let checked = try VerifiedBackup.inspect(zip)
        XCTAssertEqual(checked.captures, [capture])
        XCTAssertEqual(checked.sourceBytes, bytes.count)
        XCTAssertEqual(checked.compare(with: []).newCount, 1)
        XCTAssertEqual(checked.compare(with: [capture]).identicalCount, 1)
        capture.title = "כותרת חדשה"
        XCTAssertEqual(checked.compare(with: [capture]).conflictCount, 1)
        var corrupt = zip
        corrupt[corrupt.count-22] = 0
        XCTAssertThrowsError(try VerifiedBackup.inspect(corrupt))
        XCTAssertThrowsError(try VerifiedBackup.inspect(Data(zip.dropLast())))
        var wrong = files
        wrong[0].1 = Data("changed content".utf8)
        XCTAssertThrowsError(try VerifiedBackup.inspect(BackupArchive.zip(wrong)))
        XCTAssertThrowsError(try VerifiedBackup.inspect(BackupArchive.zip(files + [files[0]])))
        var unknown = files
        unknown[0].0 = "../unexpected"
        XCTAssertThrowsError(try VerifiedBackup.inspect(BackupArchive.zip(unknown)))
    }

    func testBackupRestorePreservesMetadataAndNeverOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = try Vault(rootURL: folder)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let bytes = renderer.pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        var capture = idea(Vault.hash(bytes), title: "כותרת", text: "טקסט", intent: .act, task: "משימה", at: Date(timeIntervalSince1970: 1234))
        capture.photoIdentifier = "stale-photo-identifier"
        capture.photoDeletedAt = Date()
        capture.viewedAt = Date()
        capture.isFavorite = true
        let zip = try BackupArchive.zip([
            ("sources/" + capture.id + "-" + capture.originalName, bytes),
            ("manifest.json", try JSONEncoder().encode([capture])),
            ("README.txt", Data("backup".utf8))
        ])
        let backup = try VerifiedBackup.inspect(zip)
        let restored = try backup.restoreNew(to: vault)
        XCTAssertEqual(restored.inserted, 1)
        XCTAssertEqual(restored.failed, 0)
        let stored = try XCTUnwrap(vault.all().first)
        XCTAssertEqual(stored.title, capture.title)
        XCTAssertEqual(stored.text, capture.text)
        XCTAssertEqual(stored.taskTitle, capture.taskTitle)
        XCTAssertEqual(stored.createdAt, capture.createdAt)
        XCTAssertTrue(stored.isFavorite)
        XCTAssertNil(stored.photoIdentifier)
        XCTAssertNil(stored.photoDeletedAt)
        XCTAssertNil(stored.viewedAt)
        XCTAssertEqual(try vault.original(stored), bytes)
        try vault.update(stored.id) { $0.title = "עריכה מקומית" }
        let repeated = try backup.restoreNew(to: vault)
        XCTAssertEqual(repeated.inserted, 0)
        XCTAssertEqual(repeated.skipped, 1)
        XCTAssertEqual(try vault.all().first?.title, "עריכה מקומית")
    }

    func testRestoreRejectsNonImageBeforeWriting() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = try Vault(rootURL: folder)
        let bytes = Data("not an image".utf8)
        let capture = idea(Vault.hash(bytes), title: "test", text: "test", at: Date())
        let zip = try BackupArchive.zip([
            ("sources/" + capture.id + "-" + capture.originalName, bytes),
            ("manifest.json", try JSONEncoder().encode([capture])),
            ("README.txt", Data("backup".utf8))
        ])
        let backup = try VerifiedBackup.inspect(zip)
        XCTAssertThrowsError(try backup.restoreNew(to: vault))
        XCTAssertTrue(try vault.all().isEmpty)
    }

    func testLibraryBackupMultiplePartsRoundTripAndCorruption() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try Vault(rootURL: folder.appendingPathComponent("source"))
        let destination = try Vault(rootURL: folder.appendingPathComponent("destination"))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        for i in 0..<23 {
            let bytes = renderer.pngData { ctx in
                UIColor(red: CGFloat(i+1)/24, green: 0.3, blue: 0.5, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            }
            let capture = try source.save(data: bytes, name: "sample-\(i).png", photoIdentifier: nil, source: "test")
            try source.update(capture.id) { $0.title = "מקור \(i)"; $0.isFavorite = true }
        }
        let report = try LibraryBackup.export(vault: source, to: folder)
        XCTAssertEqual(report.count, 23)
        XCTAssertEqual(report.parts, 2)
        let backup = folder.appendingPathComponent(report.folder)
        let index = try LibraryBackup.inspect(backup)
        XCTAssertEqual(index.count, 23)
        let restored = try LibraryBackup.restore(backup, to: destination)
        XCTAssertEqual(restored.inserted, 23)
        XCTAssertEqual(restored.failed, 0)
        XCTAssertEqual(try destination.all().count, 23)
        XCTAssertTrue(try destination.all().allSatisfy { $0.isFavorite })
        XCTAssertEqual(try LibraryBackup.restore(backup, to: destination).skipped, 23)
        let empty = try Vault(rootURL: folder.appendingPathComponent("empty"))
        let last = backup.appendingPathComponent(try XCTUnwrap(index.parts.last).name)
        try Data("corrupt".utf8).write(to: last)
        XCTAssertThrowsError(try LibraryBackup.restore(backup, to: empty))
        XCTAssertTrue(try empty.all().isEmpty)
    }

    func testEncryptedLibraryBackupRoundTripWrongKeyAndTampering() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try Vault(rootURL: folder.appendingPathComponent("source"))
        let destination = try Vault(rootURL: folder.appendingPathComponent("destination"))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let bytes = renderer.pngData { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let capture = try source.save(data: bytes, name: "sample.png", photoIdentifier: nil, source: "test")
        try source.update(capture.id) { $0.title = "פרטי"; $0.text = "מידע לדוגמה" }
        let encryption = BackupEncryption.generate()
        let recovered = try BackupEncryption(recoveryCode: encryption.recoveryCode)
        XCTAssertThrowsError(try BackupEncryption(recoveryCode: "invalid"))
        let report = try LibraryBackup.export(vault: source, to: folder, encryption: encryption)
        let backup = folder.appendingPathComponent(report.folder)
        let names = try FileManager.default.contentsOfDirectory(atPath: backup.path)
        XCTAssertTrue(names.allSatisfy { $0.hasSuffix(".smenc") })
        XCTAssertThrowsError(try LibraryBackup.inspect(backup))
        XCTAssertThrowsError(try LibraryBackup.restore(backup, to: destination, encryption: .generate()))
        XCTAssertTrue(try destination.all().isEmpty)
        let index = try LibraryBackup.inspect(backup, encryption: recovered)
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(try LibraryBackup.restore(backup, to: destination, encryption: recovered).inserted, 1)
        XCTAssertEqual(try destination.all().first?.text, "מידע לדוגמה")
        let empty = try Vault(rootURL: folder.appendingPathComponent("empty"))
        let part = backup.appendingPathComponent(try XCTUnwrap(index.parts.first).name)
        var corrupted = try Data(contentsOf: part)
        corrupted[corrupted.count-1] ^= 1
        try corrupted.write(to: part)
        XCTAssertThrowsError(try LibraryBackup.restore(backup, to: empty, encryption: recovered))
        XCTAssertTrue(try empty.all().isEmpty)
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
    func testInsightsFlagTimeSensitiveAndUnverifiedClaims() {
        XCTAssertEqual(CaptureInsights.detect(title: "חופשה", text: "יתרת חופשה 12.5 ימים"), [.timeSensitive])
        XCTAssertEqual(CaptureInsights.detect(title: "אירוע", text: "פתיחת שערים 19:30, 8.12"), [.timeSensitive])
        XCTAssertTrue(CaptureInsights.detect(title: "GrokBot", text: "רווח של $5000 בלילה אחד, קריפטו").contains(.unverifiedClaim))
        XCTAssertEqual(CaptureInsights.detect(title: "מתכון", text: "קמח, ביצים וסוכר"), [])
        XCTAssertEqual(CaptureInsights.detect(title: "", text: "  "), [])
    }
    func testSequencesGroupFramesOfOneVideoInCaptureOrder() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func make(_ id: String, _ minutes: Double, _ text: String) -> Capture {
            Capture(id: id, originalName: id + ".png", createdAt: start.addingTimeInterval(minutes * 60), title: "אבטחה", text: text, source: "test")
        }
        let frames = [
            make("c", 2, "אבטחת אפליקציות שרת הרשאות"),
            make("a", 0, "אבטחת אפליקציות מפתחות סודיים"),
            make("b", 1, "אבטחת אפליקציות קובץ סביבה"),
            make("far", 120, "אבטחת אפליקציות שרת הרשאות"),
            make("other", 3, "מתכון עוגת שוקולד")
        ]
        let groups = CaptureSequences.sequences(in: frames)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(CaptureSequences.sequence(containing: "far", in: frames).count, 0)
    }
}
