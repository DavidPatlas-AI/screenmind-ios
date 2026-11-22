import Foundation

// A saved screenshot the user may delete from Photos. The image and its text stay in the archive.
struct SpacePrompt: Codable, Equatable, Identifiable {
    var captureID: String
    var photoIdentifier: String?
    var estimatedBytes: Int
    var createdAt: Date
    var id: String { captureID }
}

struct SpaceOffer: Equatable {
    var captureIDs: [String]
    var estimatedBytes: Int
    var count: Int
    var needsAccess = false
    /// False when none of the saved shots has a Photos identifier yet.
    var canDelete = true

    var headline: String {
        if needsAccess { return "צולם מסך." }
        if count == 1 { return "צילום חדש נשמר במוח." }
        return "\(count) צילומים חדשים נשמרו במוח."
    }

    var question: String {
        if needsAccess { return "אפשר גישה לתמונות כדי לשמור אותו ולקרוא את הטקסט במכשיר." }
        if !canDelete { return "הצילום נשמר. מחיקה מהתמונות תחכה עד שיהיה מזהה של התמונה." }
        let noun = count == 1 ? "אותו" : "אותם"
        return "למחוק \(noun) כדי לפנות \(SpaceEstimate.label(estimatedBytes))?"
    }
}

enum SpaceEstimate {
    static func bytes(fileBytes: Int?, pixelWidth: Int = 0, pixelHeight: Int = 0) -> Int {
        if let fileBytes, fileBytes > 0 { return fileBytes }
        let pixels = max(pixelWidth, 0) * max(pixelHeight, 0)
        guard pixels > 0 else { return 0 }
        return pixels / 2
    }

    static func label(_ bytes: Int) -> String {
        if bytes <= 0 { return "מעט מקום" }
        if bytes < 1_000_000 {
            let kilobytes = max(1, Int((Double(bytes) / 1000).rounded()))
            return "כ־\(kilobytes) KB"
        }
        let tenths = Int((Double(bytes) / 100_000).rounded())
        let whole = tenths / 10
        let fraction = abs(tenths % 10)
        if fraction == 0 { return "כ־\(whole) MB" }
        return "כ־\(whole).\(fraction) MB"
    }
}

struct SpaceCursor: Codable, Equatable {
    var prompts: [SpacePrompt] = []
    var lastSeenAt: Date?
    /// Captures the person already chose to leave in Photos.
    var keptCaptureIDs: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case prompts, lastSeenAt, keptCaptureIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompts = try container.decodeIfPresent([SpacePrompt].self, forKey: .prompts) ?? []
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        keptCaptureIDs = try container.decodeIfPresent([String].self, forKey: .keptCaptureIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompts, forKey: .prompts)
        try container.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try container.encode(keptCaptureIDs, forKey: .keptCaptureIDs)
    }
}

enum SpacePromptStore {
    static func file(_ vault: Vault) -> URL { vault.root.appendingPathComponent("space-cursor.json") }

    static func load(_ vault: Vault) -> SpaceCursor {
        var cursor = SpaceCursor()
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: file(vault), options: [], error: &coordinationError) { coordinated in
            if let data = try? Data(contentsOf: coordinated),
               let decoded = try? JSONDecoder().decode(SpaceCursor.self, from: data) {
                cursor = decoded
            }
        }
        if coordinationError != nil, let data = try? Data(contentsOf: file(vault)),
           let decoded = try? JSONDecoder().decode(SpaceCursor.self, from: data) {
            cursor = decoded
        }
        return cursor
    }

    /// Writes `lastSeenAt` without replacing prompts the share extension may have added.
    static func save(_ cursor: SpaceCursor, vault: Vault) {
        update(vault) { current in current.lastSeenAt = cursor.lastSeenAt }
    }

    static func enqueue(_ prompt: SpacePrompt, vault: Vault) {
        update(vault) { cursor in
            if cursor.keptCaptureIDs.contains(prompt.captureID) { return }
            cursor.prompts.removeAll { $0.captureID == prompt.captureID }
            cursor.prompts.append(prompt)
        }
    }

    static func remove(_ ids: Set<String>, vault: Vault) {
        update(vault) { cursor in
            cursor.prompts.removeAll { ids.contains($0.captureID) }
        }
    }

    static func keep(_ ids: Set<String>, vault: Vault) {
        update(vault) { cursor in
            cursor.prompts.removeAll { ids.contains($0.captureID) }
            for id in ids where !cursor.keptCaptureIDs.contains(id) {
                cursor.keptCaptureIDs.append(id)
            }
        }
    }

    private static func update(_ vault: Vault, change: (inout SpaceCursor) -> Void) {
        let url = file(vault)
        var ran = false
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinated in
            ran = true
            write(change, to: coordinated)
        }
        if !ran { write(change, to: url) }
    }

    private static func write(_ change: (inout SpaceCursor) -> Void, to url: URL) {
        var cursor = SpaceCursor()
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(SpaceCursor.self, from: data) {
            cursor = decoded
        }
        change(&cursor)
        guard let data = try? JSONEncoder().encode(cursor) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum NewShotPlan {
    static func fresh(identifiers: [String], created: [Date], since: Date?, known: Set<String>) -> [String] {
        zip(identifiers, created).compactMap { identifier, date in
            if known.contains(identifier) { return nil }
            if let since, date <= since { return nil }
            return identifier
        }
    }

    /// Stay on the newest shot already listed, and never move the cursor backward.
    static func nextSeen(newestIndexed: Date?, previous: Date?) -> Date? {
        guard let newestIndexed else { return previous }
        guard let previous else { return newestIndexed }
        return max(previous, newestIndexed)
    }
}
