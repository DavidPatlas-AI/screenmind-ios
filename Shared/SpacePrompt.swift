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

    var headline: String {
        if needsAccess { return "צולם מסך." }
        if count == 1 { return "צילום חדש נשמר במוח." }
        return "\(count) צילומים חדשים נשמרו במוח."
    }

    var question: String {
        if needsAccess { return "אפשר גישה לתמונות כדי לשמור אותו ולקרוא את הטקסט במכשיר." }
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
}

enum SpacePromptStore {
    static func file(_ vault: Vault) -> URL { vault.root.appendingPathComponent("space-cursor.json") }

    static func load(_ vault: Vault) -> SpaceCursor {
        guard let data = try? Data(contentsOf: file(vault)) else { return SpaceCursor() }
        return (try? JSONDecoder().decode(SpaceCursor.self, from: data)) ?? SpaceCursor()
    }

    static func save(_ cursor: SpaceCursor, vault: Vault) {
        guard let data = try? JSONEncoder().encode(cursor) else { return }
        try? data.write(to: file(vault), options: .atomic)
    }

    static func enqueue(_ prompt: SpacePrompt, vault: Vault) {
        var cursor = load(vault)
        cursor.prompts.removeAll { $0.captureID == prompt.captureID }
        cursor.prompts.append(prompt)
        save(cursor, vault: vault)
    }

    static func remove(_ ids: Set<String>, vault: Vault) {
        var cursor = load(vault)
        cursor.prompts.removeAll { ids.contains($0.captureID) }
        save(cursor, vault: vault)
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

    /// Keep the cursor on the newest shot Photos has already listed. Moving it to "now"
    /// hides a screenshot that was taken but not indexed yet.
    static func nextSeen(newestIndexed: Date?, previous: Date?) -> Date? {
        guard let newestIndexed else { return previous }
        return newestIndexed.addingTimeInterval(-1)
    }
}
