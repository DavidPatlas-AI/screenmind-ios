import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

final class Vault: @unchecked Sendable {
    static let groupID = "group.app.screenmind.next"
    let root: URL
    private let records: URL
    private let originals: URL

    init(rootURL: URL? = nil) throws {
        let container: URL
        if let rootURL {
            container = rootURL
        } else if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID) {
            container = shared
        } else {
            // Unsigned simulator builds have no App Group container. Keep the archive in the app.
            container = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
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
    @discardableResult func save(data: Data, name: String, photoIdentifier: String?, source: String) throws -> Capture {
        guard !data.isEmpty, data.count <= 24 * 1024 * 1024,
              let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 19, height > 19, width <= 12000, height <= 16000,
              width * height <= 32_000_000 else {
            throw NativeError.message("בחר תמונה יחידה תקינה, עד 24MB. תמונות מונפשות אינן נתמכות.")
        }
        let id = Self.hash(data)
        let original = originals.appendingPathComponent(id + ".original")
        try data.write(to: original, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard Self.hash(try Data(contentsOf: original)) == id else { throw NativeError.message("שמירת המקור לא אומתה.") }
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        let initial = Capture(id: id, originalName: safeName.isEmpty ? "Screenshot.png" : safeName,
                              photoIdentifier: photoIdentifier, createdAt: Date(), title: "צילום חדש",
                              text: "", source: source)
        return try coordinatedUpdate(id: id, initial: initial) { existing in
            if existing.photoIdentifier == nil { existing.photoIdentifier = photoIdentifier }
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

