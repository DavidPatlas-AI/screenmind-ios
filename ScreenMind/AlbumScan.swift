import Foundation
import Photos
import UIKit

// The full Screenshots pass. It remembers localIdentifiers, keeps a small batch in flight,
// and never deletes a photo. Cleanup suggestions are a separate, confirmed step.
enum AlbumScanStatus: String, Codable, Equatable {
    case idle, running, paused, cancelled, finished, interrupted
}

struct ScanLedger: Codable, Equatable {
    var status: AlbumScanStatus = .idle
    var processed: Set<String> = []
    var failed: Set<String> = []
    var fingerprints: [String: UInt64] = [:]
    var total: Int = 0
    var durations: [Double] = []
}

struct AlbumScanSnapshot: Equatable {
    var status: AlbumScanStatus = .idle
    var done: Int = 0
    var total: Int = 0
    var failures: Int = 0
    var eta: String = ""
    var pausing: Bool = false
    var finishedToken: Int = 0
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }
    var progressLine: String {
        guard total > 0 else { return "" }
        var parts = ["\(done) מתוך \(total)"]
        if !eta.isEmpty { parts.append(eta) }
        if failures > 0 { parts.append("\(failures) לא נקראו") }
        return parts.joined(separator: " · ")
    }
}

struct CleanupSummary: Equatable {
    var duplicates = 0
    var junk = 0
    var textSaved = 0
    var isEmpty: Bool { duplicates + junk + textSaved == 0 }
}

enum AlbumPlan {
    static let batchSize = 4
    static let maxPixel = 1280

    static func shouldResume(_ status: AlbumScanStatus) -> Bool { status == .interrupted }

    static func nextBatch(all identifiers: [String], done: Set<String>, batchSize: Int = batchSize) -> [String] {
        var batch: [String] = []
        batch.reserveCapacity(batchSize)
        for identifier in identifiers where !done.contains(identifier) {
            batch.append(identifier)
            if batch.count == batchSize { break }
        }
        return batch
    }

    static func pixelSize(width: Int, height: Int, maxPixel: Int = maxPixel) -> (Int, Int) {
        let longest = max(width, height)
        guard longest > maxPixel, longest > 0 else { return (max(width, 1), max(height, 1)) }
        let scale = Double(maxPixel) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    static func etaLabel(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "עוד פחות מדקה" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "עוד כ־\(minutes) דקות" }
        let hours = Int((Double(minutes) / 60).rounded(.up))
        if hours <= 1 { return "עוד כשעה" }
        return "עוד כ־\(hours) שעות"
    }
}

enum ImageFingerprint {
    // dHash bits that still match are treated as the same screenshot. 6 of 64 is a tight bar.
    static let nearDistance = 6

    static func dHash(pixels: [UInt8], width: Int, height: Int) -> UInt64 {
        guard width > 1, height > 0, pixels.count == width * height, (width - 1) * height <= 64 else { return 0 }
        var hash: UInt64 = 0
        var bit: UInt64 = 1
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if pixels[y * width + x] > pixels[y * width + x + 1] { hash |= bit }
                bit <<= 1
            }
        }
        return hash
    }

    static func hamming(_ lhs: UInt64, _ rhs: UInt64) -> Int { (lhs ^ rhs).nonzeroBitCount }
}

struct CleanupPlan: Equatable {
    var duplicates: [String] = []
    var junk: [String] = []
    var textSaved: [String] = []
    var isEmpty: Bool { duplicates.isEmpty && junk.isEmpty && textSaved.isEmpty }

    static func isUseful(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { scalar in
            (scalar.value >= 0x05D0 && scalar.value <= 0x05EA) ||
                (scalar.value >= 65 && scalar.value <= 90) ||
                (scalar.value >= 97 && scalar.value <= 122)
        }
        return letters.count >= 8
    }

    static func isImportant(_ capture: Capture) -> Bool {
        capture.isFavorite || (capture.hasTask && capture.taskCompletedAt == nil)
    }

    /// A screenshot whose recognition never finished is not offered for deletion.
    static func canSuggest(_ capture: Capture) -> Bool {
        capture.textStatus != "failed" && capture.textStatus != "pending"
    }

    static func build(captures: [Capture], fingerprints: [String: UInt64]) -> CleanupPlan {
        let indexed = captures.filter { capture in
            !capture.isArchived && capture.photoDeletedAt == nil && !(capture.photoIdentifier ?? "").isEmpty
                && capture.source != "picker"
        }
        guard !indexed.isEmpty else { return CleanupPlan() }
        var parent = Array(indexed.indices)
        func find(_ start: Int) -> Int {
            var index = start
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        func unite(_ lhs: Int, _ rhs: Int) {
            let left = find(lhs)
            let right = find(rhs)
            if left != right { parent[right] = left }
        }
        var hashed: [(Int, UInt64)] = []
        hashed.reserveCapacity(indexed.count)
        for (index, capture) in indexed.enumerated() {
            if let hash = fingerprints[capture.id] { hashed.append((index, hash)) }
        }
        if hashed.count > 1 {
            for left in hashed.indices {
                for right in (left + 1)..<hashed.count {
                    if ImageFingerprint.hamming(hashed[left].1, hashed[right].1) <= ImageFingerprint.nearDistance {
                        unite(hashed[left].0, hashed[right].0)
                    }
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for index in indexed.indices { groups[find(index), default: []].append(index) }
        var plan = CleanupPlan()
        for members in groups.values {
            let ranked = members.sorted { lhs, rhs in
                let left = indexed[lhs]
                let right = indexed[rhs]
                if CleanupPlan.isImportant(left) != CleanupPlan.isImportant(right) { return CleanupPlan.isImportant(left) }
                if left.text.count != right.text.count { return left.text.count > right.text.count }
                if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
                return left.id < right.id
            }
            let keeper = indexed[ranked[0]]
            if members.count > 1 {
                for index in ranked.dropFirst() where !CleanupPlan.isImportant(indexed[index]) && CleanupPlan.canSuggest(indexed[index]) {
                    plan.duplicates.append(indexed[index].id)
                }
            }
            if CleanupPlan.isImportant(keeper) || !CleanupPlan.canSuggest(keeper) { continue }
            if CleanupPlan.isUseful(keeper.text) { plan.textSaved.append(keeper.id) }
            else { plan.junk.append(keeper.id) }
        }
        return plan
    }
}

enum NotesExport {
    static func markdown(_ captures: [Capture]) -> String { render(captures, markdown: true) }
    static func plain(_ captures: [Capture]) -> String { render(captures, markdown: false) }

    private static func render(_ captures: [Capture], markdown: Bool) -> String {
        let ordered = captures.filter { !$0.isArchived }.sorted { $0.createdAt > $1.createdAt }
        var lines = [markdown ? "# ScreenMind" : "ScreenMind", ""]
        for capture in ordered {
            lines.append(markdown ? "## \(capture.title)" : capture.title)
            lines.append("")
            if !capture.text.isEmpty { lines.append(capture.text); lines.append("") }
            lines.append((markdown ? "- " : "") + "מרחב: \(capture.collection)")
            lines.append((markdown ? "- " : "") + "כוונה: \(capture.intent.title)")
            if let task = capture.taskTitle, !task.isEmpty {
                lines.append((markdown ? "- " : "") + "צעד: \(task)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

enum ScanLedgerStore {
    static func file(_ vault: Vault) -> URL { vault.root.appendingPathComponent("scan-ledger.json") }

    static func load(_ vault: Vault) -> ScanLedger {
        guard let data = try? Data(contentsOf: file(vault)) else { return ScanLedger() }
        return (try? JSONDecoder().decode(ScanLedger.self, from: data)) ?? ScanLedger()
    }

    static func save(_ ledger: ScanLedger, vault: Vault) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        try? data.write(to: file(vault), options: .atomic)
    }
}

final class ScanGate {
    var pause = false
    var cancel = false
}

extension NativeLibrary {
    func scanAllScreenshots() async {
        guard !busy, !scanLoopActive, albumLedger.status != .running, let vault else { return }
        scanGate.pause = false
        scanGate.cancel = false
        albumLedger.status = .running
        albumScan.status = .running
        albumScan.pausing = false
        ScanLedgerStore.save(albumLedger, vault: vault)
        scanLoopActive = true
        defer {
            scanLoopActive = false
            if albumLedger.status == .running { albumLedger.status = .interrupted }
            ScanLedgerStore.save(albumLedger, vault: vault)
            publishAlbumScan()
            refresh()
            refreshCleanupSummary()
        }
        _ = await PhotoService.permission()
        guard PhotoService.hasAccess else {
            albumLedger.status = .paused
            error = "כדי לסרוק את האלבום צריך לאפשר גישה לתמונות."
            return
        }
        let identifiers: [String]
        do {
            identifiers = try await Task.detached(priority: .utility) {
                try PhotoService.screenshotIdentifiers()
            }.value
        } catch {
            albumLedger.status = .paused
            self.error = error.localizedDescription
            return
        }
        fingerprintStoredCaptures(vault: vault)
        let known = Set(captures.compactMap(\.photoIdentifier))
        for identifier in identifiers where known.contains(identifier) {
            albumLedger.processed.insert(identifier)
        }
        albumLedger.total = identifiers.count
        var done = identifiers.reduce(into: 0) { if albumLedger.processed.contains($1) { $0 += 1 } }
        publishAlbumScan(done: done, etaSeconds: nil)
        if identifiers.isEmpty {
            albumLedger.status = .finished
            albumScan.finishedToken += 1
            return
        }
        while !Task.isCancelled {
            if scanGate.cancel {
                albumLedger.status = .cancelled
                return
            }
            if scanGate.pause {
                albumLedger.status = .paused
                return
            }
            let batch = AlbumPlan.nextBatch(all: identifiers, done: albumLedger.processed)
            if batch.isEmpty {
                albumLedger.status = .finished
                albumScan.finishedToken += 1
                return
            }
            for identifier in batch {
                if Task.isCancelled || scanGate.cancel || scanGate.pause { break }
                let started = Date()
                await ingest(identifier, vault: vault)
                done += 1
                albumLedger.durations.append(Date().timeIntervalSince(started))
                if albumLedger.durations.count > 30 { albumLedger.durations.removeFirst(albumLedger.durations.count - 30) }
                let average = albumLedger.durations.reduce(0, +) / Double(max(albumLedger.durations.count, 1))
                let remaining = max(0, identifiers.count - done)
                publishAlbumScan(done: done, etaSeconds: average * Double(remaining))
                ScanLedgerStore.save(albumLedger, vault: vault)
                await Task.yield()
            }
        }
    }

    func pauseAlbumScan() {
        scanGate.pause = true
        albumScan.pausing = true
        albumLedger.status = .paused
        if let vault { ScanLedgerStore.save(albumLedger, vault: vault) }
        publishAlbumScan(etaSeconds: nil)
        guard scanLoopActive else { albumScan.pausing = false; return }
    }

    func cancelAlbumScan() {
        scanGate.cancel = true
        albumScan.pausing = true
        albumLedger.status = .cancelled
        if let vault { ScanLedgerStore.save(albumLedger, vault: vault) }
        publishAlbumScan(etaSeconds: nil)
        guard scanLoopActive else { albumScan.pausing = false; return }
    }

    func retryFailedAlbumScan() async {
        guard !scanLoopActive else { return }
        albumLedger.processed.subtract(albumLedger.failed)
        albumLedger.failed.removeAll()
        albumLedger.status = .paused
        if let vault { ScanLedgerStore.save(albumLedger, vault: vault) }
        publishAlbumScan(etaSeconds: nil)
        await scanAllScreenshots()
    }

    func deleteSuggested(ids: Set<String>) async throws {
        guard !busy, !scanLoopActive, let vault, !ids.isEmpty else {
            throw NativeError.message("אפשר לפנות רק כשאין סריקה או פעולה אחרת באמצע.")
        }
        let plan = CleanupPlan.build(captures: active, fingerprints: albumLedger.fingerprints)
        let allowed = Set(plan.duplicates + plan.junk + plan.textSaved)
        let chosen = captures.filter { capture in
            ids.contains(capture.id) && allowed.contains(capture.id) && !CleanupPlan.isImportant(capture)
        }
        guard !chosen.isEmpty else { throw NativeError.message("לא נבחרו צילומים שאפשר לפנות.") }
        _ = await PhotoService.permission()
        let deletion = PhotoService.deletionPlan(chosen)
        guard !deletion.present.isEmpty || !deletion.alreadyGone.isEmpty else {
            throw NativeError.message("אין מזהה של תמונות שאפשר למסור לאפל. הצילומים נשארים בתמונות.")
        }
        noteActivity("מבקש מאפל להעביר ל״נמחקו לאחרונה״…")
        defer { clearActivity(); refresh(); refreshCleanupSummary() }
        if !deletion.present.isEmpty { try await PhotoService.requestDeletion(deletion.present.map(\.1)) }
        for id in deletion.present.map(\.0) + deletion.alreadyGone {
            try vault.update(id) { $0.photoDeletedAt = Date() }
        }
        if !deletion.unresolved.isEmpty {
            throw NativeError.message("חלק מהצילומים נשארו בתמונות. אין להם מזהה שאפשר למסור לאפל.")
        }
    }

    func refreshCleanupSummary() {
        let plan = CleanupPlan.build(captures: active, fingerprints: albumLedger.fingerprints)
        cleanupSummary = CleanupSummary(duplicates: plan.duplicates.count, junk: plan.junk.count, textSaved: plan.textSaved.count)
    }

    func publishAlbumScan(done: Int? = nil, etaSeconds: TimeInterval? = nil) {
        var snapshot = albumScan
        snapshot.status = albumLedger.status
        if let done { snapshot.done = done }
        snapshot.total = max(albumLedger.total, snapshot.done)
        snapshot.failures = albumLedger.failed.count
        snapshot.pausing = scanLoopActive && (scanGate.pause || scanGate.cancel)
        if albumLedger.status == .running, let etaSeconds {
            snapshot.eta = AlbumPlan.etaLabel(etaSeconds)
        } else if albumLedger.status != .running {
            snapshot.eta = ""
        }
        albumScan = snapshot
    }

    private func fingerprintStoredCaptures(vault: Vault) {
        for capture in captures where albumLedger.fingerprints[capture.id] == nil
            && capture.photoDeletedAt == nil && !capture.isArchived
            && !(capture.photoIdentifier ?? "").isEmpty && capture.source != "picker" {
            autoreleasepool {
                guard let data = try? vault.original(capture),
                      let image = UIImage(data: data),
                      let pixels = ScreenshotPixels.grayscale(image) else { return }
                albumLedger.fingerprints[capture.id] = ImageFingerprint.dHash(pixels: pixels, width: 9, height: 8)
            }
        }
    }

    private func ingest(_ identifier: String, vault: Vault) async {
        guard let asset = PhotoService.asset(id: identifier) else {
            albumLedger.failed.insert(identifier)
            albumLedger.processed.insert(identifier)
            return
        }
        do {
            let image = try await PhotoService.downscaled(asset, maxPixel: AlbumPlan.maxPixel)
            let encoded: Data? = autoreleasepool { ScreenshotPixels.jpeg(image) }
            let fingerprint: UInt64? = autoreleasepool {
                guard let pixels = ScreenshotPixels.grayscale(image) else { return nil }
                return ImageFingerprint.dHash(pixels: pixels, width: 9, height: 8)
            }
            guard let encoded else { throw NativeError.message("לא הצלחתי להקטין את הצילום.") }
            let capture = try vault.save(data: encoded, name: "screenshot.jpg", photoIdentifier: identifier, source: "album")
            if let fingerprint { albumLedger.fingerprints[capture.id] = fingerprint }
            var stored = capture
            if capture.textStatus == "pending" {
                do { stored = try await recognize(capture, data: encoded) }
                catch { stored = (try? vault.update(capture.id) { $0.textStatus = "failed" }) ?? capture }
            }
            storeCapture(stored)
            albumLedger.processed.insert(identifier)
        } catch {
            albumLedger.failed.insert(identifier)
            albumLedger.processed.insert(identifier)
        }
    }
}
