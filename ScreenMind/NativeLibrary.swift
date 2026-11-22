import Foundation
import SwiftUI
import PhotosUI
import Photos
import ImageIO
import UniformTypeIdentifiers

struct BackupReceipt: Sendable {
    let url: URL
    let digest: String
    let captureIDs: Set<String>
}
struct PreparedBackup: Sendable {
    let data: Data
    let captureIDs: Set<String>
}
struct ImportReport: Identifiable, Sendable {
    let id = UUID()
    let saved: Int
    let duplicates: Int
    let failures: Int
    let reviewIDs: [String]
}
@MainActor final class NativeLibrary: ObservableObject {
    @Published private(set) var captures: [Capture] = []
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    @Published var error: String?
    @Published var report: ImportReport?
    @Published private(set) var backupReceipt: BackupReceipt?
    @Published private(set) var hebrewRecognitionSupported: Bool?
    @Published var albumScan = AlbumScanSnapshot()
    @Published var cleanupSummary = CleanupSummary()
    var albumLedger = ScanLedger()
    let scanGate = ScanGate()
    var scanLoopActive = false
    var startGate = false
    private(set) var vault: Vault?
    private let thumbnails = NSCache<NSString, UIImage>()
    var active: [Capture] { captures.filter { !$0.isArchived } }
    var pending: [Capture] { active.filter(\.needsReview) }
    var collections: [String] { Array(Set(active.map(\.collection))).sorted() }

    init() {
        thumbnails.countLimit = 60
        thumbnails.totalCostLimit = 32 * 1024 * 1024
        do {
            let opened = try Vault()
            vault = opened
            try UITestLaunch.prepare(opened)
            albumLedger = ScanLedgerStore.load(opened)
            if albumLedger.status == .running {
                albumLedger.status = .interrupted
                ScanLedgerStore.save(albumLedger, vault: opened)
            }
            refresh()
            publishAlbumScan(done: albumLedger.processed.count)
            refreshCleanupSummary()
        } catch { self.error = error.localizedDescription }
        hebrewRecognitionSupported = TextRecognition.hebrewDataAvailable
    }
    func refresh() {
        guard let vault else { return }
        do { captures = try vault.all() }
        catch { self.error = error.localizedDescription }
    }
    func noteActivity(_ message: String) {
        busy = true
        progress = message
    }
    func clearActivity() {
        busy = false
        progress = ""
    }
    func storeCapture(_ stored: Capture) {
        if let index = captures.firstIndex(where: { $0.id == stored.id }) { captures[index] = stored }
        else { captures.insert(stored, at: 0) }
    }
    @discardableResult func update(_ id: String, change: (inout Capture) -> Void) -> Bool {
        guard let vault else { return false }
        do { try vault.update(id, change: change); refresh(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func capture(_ id: String) -> Capture? { captures.first { $0.id == id } }
    func image(_ capture: Capture) -> UIImage? {
        guard let vault else { return nil }
        return UIImage(contentsOfFile: vault.originalURL(capture).path)
    }
    func thumbnail(_ capture: Capture) -> UIImage? {
        if let cached = thumbnails.object(forKey: capture.id as NSString) { return cached }
        guard let vault,
              let source = CGImageSourceCreateWithURL(vault.originalURL(capture) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 420
              ] as CFDictionary) else { return nil }
        let result = UIImage(cgImage: image)
        thumbnails.setObject(result, forKey: capture.id as NSString, cost: image.bytesPerRow * image.height)
        return result
    }
    func start() async {
        if startGate { return }
        startGate = true
        defer { startGate = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestAlbumRunning") {
            if albumScan.status == .paused || albumScan.status == .cancelled { return }
            albumLedger.status = .running
            albumLedger.total = 2500
            albumScan.status = .running
            albumScan.done = 400
            albumScan.total = 2500
            albumScan.eta = AlbumPlan.etaLabel(20 * 60)
            return
        }
        #endif
        refresh()
        guard let vault else { return }
        if !busy && albumScan.status != .running {
            let items = captures.filter { $0.textStatus == "pending" }.prefix(20)
            if !items.isEmpty {
                busy = true
                progress = "מזהה טקסט במכשיר…"
                for (index, capture) in items.enumerated() {
                    progress = "מזהה טקסט במכשיר · \(index + 1) מתוך \(items.count)"
                    do { try await recognize(capture, data: vault.original(capture)) }
                    catch { try? vault.update(capture.id) { $0.textStatus = "failed" } }
                }
                busy = false
                progress = ""
                refresh()
            }
        }
        guard AlbumPlan.shouldResume(albumLedger.status), PhotoService.hasAccess, !busy else { return }
        await scanAllScreenshots()
    }
    @discardableResult func recognize(_ capture: Capture, data: Data, overwrite: Bool = false) async throws -> Capture {
        guard let vault else { throw NativeError.message("הארכיון אינו זמין.") }
        let result = try await TextRecognition.recognize(data)
        hebrewRecognitionSupported = result.hebrewSupported
        return try vault.update(capture.id) { current in
            let fill = overwrite || (current.reviewedAt == nil && current.text.isEmpty)
            if fill {
                current.text = result.text
                let placeholder = current.title.isEmpty || current.title == "צילום חדש"
                if !overwrite || current.reviewedAt == nil || placeholder {
                    current.title = result.title
                }
            }
            current.textStatus = result.text.isEmpty ? "noText" : "complete"
        }
    }
    func rerecognize(_ id: String) async {
        guard !busy, let vault, let capture = captures.first(where: { $0.id == id }) else { return }
        busy = true
        progress = "מזהה טקסט מחדש במכשיר…"
        defer { busy = false; progress = ""; refresh() }
        do { try await recognize(capture, data: vault.original(capture), overwrite: true) }
        catch {
            self.error = error.localizedDescription
            try? vault.update(id) { $0.textStatus = "failed" }
        }
    }
    func importPicker(_ items: [PhotosPickerItem]) async {
        guard albumScan.status != .running else {
            error = "הסריקה של האלבום עדיין רצה. אפשר להשהות אותה ולהמשיך אחר כך."
            return
        }
        guard !busy, let vault, !items.isEmpty else { return }
        busy = true
        progress = "שומר את הצילומים שנבחרו…"
        var saved = 0, duplicates = 0, failures = 0
        var reviewIDs: [String] = []
        defer { busy = false; progress = ""; refresh(); report = ImportReport(saved: saved, duplicates: duplicates, failures: failures, reviewIDs: reviewIDs) }
        for (index, item) in items.prefix(20).enumerated() {
            progress = "שומר מקור ומזהה טקסט · \(index + 1) מתוך \(min(items.count, 20))"
            do {
                let bytes: Data, name: String
                if let identifier = item.itemIdentifier, let asset = PhotoService.asset(id: identifier) {
                    (bytes, name) = try await PhotoService.original(asset)
                } else {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw NativeError.message("לא ניתן לקרוא את התמונה.") }
                    bytes = data
                    let type = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
                    let ext = type.flatMap { UTType($0)?.preferredFilenameExtension } ?? "png"
                    name = "Screenshot." + ext
                }
                let existed = captures.contains { $0.id == Vault.hash(bytes) }
                let capture = try vault.save(data: bytes, name: name, photoIdentifier: item.itemIdentifier, source: "picker")
                if capture.needsReview && !reviewIDs.contains(capture.id) { reviewIDs.append(capture.id) }
                refresh()
                if existed { duplicates += 1 } else { saved += 1 }
                if capture.textStatus == "pending" {
                    do { try await recognize(capture, data: bytes) }
                    catch { try? vault.update(capture.id) { $0.textStatus = "failed" } }
                }
            } catch { failures += 1 }
        }
    }
    func scanScreenshots() async {
        guard albumScan.status != .running else {
            error = "הסריקה של האלבום עדיין רצה. אפשר להשהות אותה ולהמשיך אחר כך."
            return
        }
        guard !busy, let vault else { return }
        busy = true
        progress = "מבקש גישה לצילומי מסך…"
        var saved = 0, duplicates = 0, failures = 0
        var reviewIDs: [String] = []
        defer { busy = false; progress = ""; refresh(); report = ImportReport(saved: saved, duplicates: duplicates, failures: failures, reviewIDs: reviewIDs) }
        _ = await PhotoService.permission()
        progress = "מחפש צילומי מסך חדשים…"
        await Task.yield()
        do {
            let known = Set(captures.compactMap(\.photoIdentifier))
            let identifiers = try await Task.detached(priority: .userInitiated) {
                try PhotoService.screenshots().map(\.localIdentifier)
            }.value.filter { !known.contains($0) }
            let pending = Array(identifiers.prefix(20))
            for (index, identifier) in pending.enumerated() {
                progress = "שומר צילום · \(index + 1) מתוך \(pending.count)"
                guard let asset = PhotoService.asset(id: identifier) else { failures += 1; continue }
                do {
                    let (bytes, name) = try await PhotoService.original(asset)
                    let existed = captures.contains { $0.id == Vault.hash(bytes) }
                    let capture = try vault.save(data: bytes, name: name, photoIdentifier: identifier, source: "scan")
                    if capture.needsReview && !reviewIDs.contains(capture.id) { reviewIDs.append(capture.id) }
                    refresh()
                    if existed { duplicates += 1 } else { saved += 1 }
                    if capture.textStatus == "pending" {
                        do { try await recognize(capture, data: bytes) }
                        catch { try? vault.update(capture.id) { $0.textStatus = "failed" } }
                    }
                } catch { failures += 1 }
            }
        } catch { self.error = error.localizedDescription }
    }
    func prepareBackup(ids: Set<String>) async throws -> PreparedBackup {
        guard !busy, let vault else { throw NativeError.message("המתן לסיום הפעולה הנוכחית.") }
        let selected = captures.filter { ids.contains($0.id) }
        guard !selected.isEmpty, selected.count <= 20 else { throw NativeError.message("בחר בין מקור אחד ל־20 מקורות.") }
        busy = true; progress = "מכין את המקורות לייצוא…"
        defer { busy = false; progress = "" }
        return try await Task.detached(priority: .userInitiated) {
            var files: [(String, Data)] = [], total = 0
            for capture in selected {
                let data = try vault.original(capture)
                total += data.count
                guard total <= 32 * 1024 * 1024 else { throw NativeError.message("הייצוא גדול מ־32MB. בחר פחות צילומים בכל פעם.") }
                files.append(("sources/" + capture.id + "-" + capture.originalName, data))
            }
            files.append(("manifest.json", try JSONEncoder().encode(selected)))
            files.append(("README.txt", Data("ScreenMind backup: originals in sources/. manifest.json includes SHA-256 identifiers and user metadata. Keep this archive outside the app and open the originals before deleting from Photos.".utf8)))
            return PreparedBackup(data: try BackupArchive.zip(files), captureIDs: Set(selected.map(\.id)))
        }.value
    }
    func verifyExport(url: URL, prepared: PreparedBackup) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let path = url.resolvingSymlinksInPath().path
        guard !path.hasPrefix(NSHomeDirectory() + "/"), !(vault.map { path.hasPrefix($0.root.path + "/") } ?? true) else {
            throw NativeError.message("בחר מיקום ב־Files מחוץ לתיקיות של ScreenMind.")
        }
        let digest = Vault.hash(prepared.data)
        guard Vault.hash(try Data(contentsOf: url)) == digest else { throw NativeError.message("הייצוא נוצר, אך אימות העותק לא הצליח. אפשרות המחיקה נשארת חסומה.") }
        backupReceipt = BackupReceipt(url: url, digest: digest, captureIDs: prepared.captureIDs)
    }
    private func verifyReceipt(_ ids: Set<String>) throws {
        guard let receipt = backupReceipt, ids.isSubset(of: receipt.captureIDs) else {
            throw NativeError.message("תחילה יש לייצא ולאמת עותק נוסף דרך מסך הפינוי.")
        }
        let access = receipt.url.startAccessingSecurityScopedResource()
        defer { if access { receipt.url.stopAccessingSecurityScopedResource() } }
        guard Vault.hash(try Data(contentsOf: receipt.url)) == receipt.digest else {
            throw NativeError.message("העותק החיצוני השתנה או אינו זמין. ייצא עותק חדש.")
        }
    }
    func deletionBlockReason(_ capture: Capture) -> String? {
        if capture.photoDeletedAt != nil { return "כבר נשלחה בקשת מחיקה לתמונות." }
        if capture.reviewedAt == nil { return "ממתין לאישור שלך." }
        if capture.viewedAt == nil { return "פתח את המקור בגודל מלא לפני הפינוי." }
        if capture.photoIdentifier == nil { return "אין קישור לצילום המקורי. אפשר לשייך בסריקה באישור גישה לתמונות." }
        if backupReceipt?.captureIDs.contains(capture.id) != true { return "ממתין לייצוא ולאימות עותק נוסף." }
        return nil
    }
    func deleteFromPhotos(ids: Set<String>) async throws {
        guard albumScan.status != .running else { throw NativeError.message("הסריקה של האלבום עדיין רצה. אפשר להשהות אותה קודם.") }
        guard !busy, let vault, !ids.isEmpty, ids.count <= 20 else { throw NativeError.message("בחר עד 20 צילומים והמתן לסיום הפעולה הנוכחית.") }
        busy = true; progress = "בודק את העותקים והמקורות לפני בקשת המחיקה…"
        defer { busy = false; progress = ""; refresh() }
        try verifyReceipt(ids)
        _ = await PhotoService.permission()
        var verified: [(PHAsset, Date?)] = []
        for id in ids {
            guard let capture = captures.first(where: { $0.id == id }),
                  deletionBlockReason(capture) == nil, let identifier = capture.photoIdentifier,
                  let asset = PhotoService.asset(id: identifier) else {
                throw NativeError.message("אחד המקורות אינו עומד בתנאי הפינוי. לא נשלחה בקשת מחיקה.")
            }
            let local = try vault.original(capture)
            guard PhotoService.isUneditedScreenshot(asset) else {
                throw NativeError.message("צילום שעבר עריכה או מכיל כמה משאבים אינו מוצע למחיקה בגרסה זו.")
            }
            let (current, _) = try await PhotoService.original(asset)
            let facts = CleanupFacts(reviewed: capture.reviewedAt != nil, viewedOriginal: capture.viewedAt != nil,
                                     archiveMatches: Vault.hash(local) == id, externalBackupMatches: true,
                                     exactPhotoMatches: Vault.hash(current) == id,
                                     isUneditedScreenshot: PhotoService.isUneditedScreenshot(asset))
            guard facts.permitsDeletion else { throw NativeError.message("אחד המקורות השתנה. לא נשלחה בקשת מחיקה.") }
            verified.append((asset, asset.modificationDate))
        }
        try verifyReceipt(ids)
        var fresh: [PHAsset] = []
        for (asset, date) in verified {
            guard let current = PhotoService.asset(id: asset.localIdentifier),
                  current.modificationDate == date, PhotoService.isUneditedScreenshot(current) else {
                throw NativeError.message("הספרייה השתנתה בזמן הבדיקה. נסה שוב.")
            }
            fresh.append(current)
        }
        // PhotoKit presents Apple's final confirmation. No deletion happens before this call.
        try await PhotoService.requestDeletion(fresh)
        do { for id in ids { try vault.update(id) { $0.photoDeletedAt = Date() } } }
        catch { throw NativeError.message("אפל אישרה את השינוי בתמונות, אך סימון הרשומות לא נשמר. הארכיון המקומי נשאר זמין.") }
    }
}
