import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

final class Vault: @unchecked Sendable {
    static let groupID = "group.app.screenmind.next"
    static var runsInsideAppExtension: Bool { Bundle.main.bundleURL.pathExtension == "appex" }
    let root: URL
    private let records: URL
    private let originals: URL

    init(rootURL: URL? = nil) throws {
        let container: URL
        if let rootURL {
            container = rootURL
        } else if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID) {
            container = shared
        } else if Self.runsInsideAppExtension {
            throw NativeError.message("לא ניתן לפתוח את הארכיון המשותף. יש להגדיר App Group בשני היעדים ב־Xcode.")
        } else {
            #if DEBUG || SCREENMIND_PERSONAL
            // The unsigned simulator has no App Group. A release build, and the share extension, still require it.
            container = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            #else
            throw NativeError.message("לא ניתן לפתוח את הארכיון המשותף. יש להגדיר App Group בשני היעדים ב־Xcode.")
            #endif
        }
        root = container.appendingPathComponent("ScreenMindVault", isDirectory: true)
        records = root.appendingPathComponent("Records", isDirectory: true)
        originals = root.appendingPathComponent("Originals", isDirectory: true)
        for directory in [root, records, originals] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
    }
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func originalURL(_ capture: Capture) -> URL { originals.appendingPathComponent(capture.id + ".original") }
    func delete(id: String) throws {
        let record = try recordURL(id)
        let original = originals.appendingPathComponent(id + ".original")
        if FileManager.default.fileExists(atPath: record.path) { try FileManager.default.removeItem(at: record) }
        if FileManager.default.fileExists(atPath: original.path) { try FileManager.default.removeItem(at: original) }
    }
    func original(_ capture: Capture) throws -> Data {
        _ = try recordURL(capture.id)
        let data = try Data(contentsOf: originalURL(capture))
        guard Self.hash(data) == capture.digest else { throw NativeError.message("בדיקת המקור נכשלה. לא ניתן להציע מחיקה.") }
        return data
    }
    private func recordURL(_ id: String) throws -> URL {
        guard id.count == 64, id.allSatisfy({ $0.isHexDigit }) else { throw NativeError.message("מזהה מקור אינו תקין.") }
        return records.appendingPathComponent(id + ".json")
    }
    func all() throws -> [Capture] {
        try FileManager.default.contentsOfDirectory(at: records, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try read(at: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private func read(at url: URL) throws -> Capture {
        var coordinationError: NSError?
        var result: Result<Capture, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result { try JSONDecoder().decode(Capture.self, from: Data(contentsOf: coordinated)) }
        }
        if let error = coordinationError { throw error }
        guard let result else { throw NativeError.message("לא ניתן לקרוא את הרשומה.") }
        let capture = try result.get()
        guard capture.id == url.deletingPathExtension().lastPathComponent,
              capture.id.count == 64, capture.id.allSatisfy({ $0.isHexDigit }) else {
            throw NativeError.message("הרשומה אינה תואמת למקור.")
        }
        return capture
    }
    static func validateSourceImage(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 24 * 1024 * 1024,
              let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 19, height > 19, width <= 12000, height <= 16000,
              width * height <= 32_000_000 else {
            throw NativeError.message("בחר תמונה יחידה תקינה, עד 24MB. תמונות מונפשות אינן נתמכות.")
        }
    }

    // Add only missing records. The coordinator serializes against other
    // cooperating record writers. Never replace an existing record.
    func restoreNewCapture(_ capture: Capture, data: Data) throws -> Bool {
        guard capture.id.utf8.count == 64,
              capture.id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              Self.hash(data) == capture.id else {
            throw NativeError.message("מקור הגיבוי אינו תקין.")
        }
        try Self.validateSourceImage(data)
        let url = try recordURL(capture.id)
        let imageURL = originalURL(capture)
        var restored = capture
        // A PhotoKit identifier from a backup is not proof of current ownership.
        restored.photoIdentifier = nil
        restored.photoDeletedAt = nil
        restored.viewedAt = nil
        let metadata = try JSONEncoder().encode(restored)
        var coordinationError: NSError?
        var result: Result<Bool, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinated in
            result = Result {
                if FileManager.default.fileExists(atPath: coordinated.path) { return false }
                if FileManager.default.fileExists(atPath: imageURL.path) {
                    guard Self.hash(try Data(contentsOf: imageURL)) == capture.id else {
                        throw NativeError.message("נמצא מקור מקומי שאינו תואם לגיבוי.")
                    }
                } else {
                    try data.write(to: imageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                guard Self.hash(try Data(contentsOf: imageURL)) == capture.id else {
                    throw NativeError.message("אימות המקור המשוחזר נכשל.")
                }
                // Commit the record last. A crash can leave an orphan image,
                // but cannot publish a record before its source exists.
                try metadata.write(to: coordinated, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                return true
            }
        }
        if let error = coordinationError { throw error }
        guard let result else { throw NativeError.message("השחזור לא הושלם.") }
        return try result.get()
    }
    @discardableResult func save(data: Data, name: String, photoIdentifier: String?, source: String, photoCreationDate: Date? = nil) throws -> Capture {
        try Self.validateSourceImage(data)
        let id = Self.hash(data)
        let original = originals.appendingPathComponent(id + ".original")
        try data.write(to: original, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard Self.hash(try Data(contentsOf: original)) == id else { throw NativeError.message("שמירת המקור לא אומתה.") }
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        let initial = Capture(id: id, originalName: safeName.isEmpty ? "Screenshot.png" : safeName,
                              photoIdentifier: photoIdentifier, createdAt: Date(), photoCreatedAt: photoCreationDate, title: "צילום חדש",
                              text: "", source: source)
        return try coordinatedUpdate(id: id, initial: initial) { existing in
            if existing.photoIdentifier == nil { existing.photoIdentifier = photoIdentifier }
            if let photoIdentifier, existing.photoIdentifier == photoIdentifier, let photoCreationDate {
                existing.photoCreatedAt = photoCreationDate
            }
        }
    }
    @discardableResult func update(_ id: String, change: (inout Capture) throws -> Void) throws -> Capture {
        try coordinatedUpdate(id: id, initial: nil, change: change)
    }
    private func coordinatedUpdate(id: String, initial: Capture?, change: (inout Capture) throws -> Void) throws -> Capture {
        let url = try recordURL(id)
        var coordinationError: NSError?
        var result: Result<Capture, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinated in
            result = Result {
                var capture: Capture
                if FileManager.default.fileExists(atPath: coordinated.path) {
                    capture = try JSONDecoder().decode(Capture.self, from: Data(contentsOf: coordinated))
                } else if let initial { capture = initial }
                else { throw NativeError.message("המקור אינו זמין.") }
                guard capture.id == id else { throw NativeError.message("הרשומה אינה תקינה.") }
                try change(&capture)
                try JSONEncoder().encode(capture).write(to: coordinated, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                return capture
            }
        }
        if let error = coordinationError { throw error }
        guard let result else { throw NativeError.message("השינוי לא נשמר.") }
        return try result.get()
    }
}

