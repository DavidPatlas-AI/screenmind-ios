import Foundation
import UIKit
import Vision
import TesseractSwift

struct TextResult: Sendable {
    let text: String
    let title: String
    let hebrewSupported: Bool
}

struct OCRLine: Equatable, Sendable {
    var text: String
    var boundingBox: CGRect
}

enum TextRecognitionError: LocalizedError {
    case unreadableImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "לא ניתן לקרוא את התמונה לזיהוי טקסט."
        case .recognitionFailed: return "זיהוי הטקסט נכשל."
        }
    }
}

/// Cloud OCR is not connected. The button stays off unless a key is present in the
/// process environment, and even then the image is not uploaded.
enum AccurateRecognition {
    static let keyName = "SCREENMIND_ACCURATE_OCR_KEY"
    static let unavailableMessage = "זיהוי מדויק בענן כבוי כברירת מחדל. התמונה נשארת במכשיר ולא נשלחת."

    static func isEnabled(environmentKey: String?) -> Bool {
        guard let environmentKey else { return false }
        return !environmentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var isEnabled: Bool {
        isEnabled(environmentKey: ProcessInfo.processInfo.environment[keyName])
    }
}

enum TextRecognition {
    /// Top strip of an iPhone screenshot (status bar / Dynamic Island), as a fraction of image height.
    static let statusBarHeightFraction: CGFloat = 0.08
    private static let bidiControls = CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")

    static var hebrewDataAvailable: Bool { tessdataDirectory() != nil }

    static func recognize(_ data: Data) async throws -> TextResult {
        try await Task.detached(priority: .userInitiated) {
            try recognizeSync(data)
        }.value
    }

    static func recognizeSync(_ data: Data) throws -> TextResult {
        let prepared = try preparedImageData(data)
        let tessdata = tessdataDirectory()
        var lines: [String] = []
        var attempts = 0
        var failures = 0

        if let tessdata {
            attempts += 1
            do { lines = cleanedLines(from: try tesseractText(prepared, tessdataDirectory: tessdata)) }
            catch { failures += 1 }
        }
        // Vision has no Hebrew model. Use it only when Tesseract did not find Hebrew.
        if hebrewLetters(in: lines.joined()).count < 3 {
            attempts += 1
            do {
                let vision = try recognizeWithVision(prepared)
                if vision.joined().count > lines.joined().count { lines = vision }
            } catch {
                failures += 1
            }
        }
        if lines.isEmpty && attempts > 0 && failures == attempts {
            throw TextRecognitionError.recognitionFailed
        }
        let text = lines.joined(separator: "\n")
        let title = String((lines.first ?? "צילום חדש").prefix(90))
        return TextResult(text: text, title: title, hebrewSupported: tessdata != nil)
    }

    static func statusBarCropPixels(imageHeight: Int) -> Int {
        guard imageHeight > 1 else { return 0 }
        let pixels = Int((CGFloat(imageHeight) * statusBarHeightFraction).rounded(.up))
        return min(max(pixels, 0), imageHeight / 2)
    }

    static func croppingStatusBar(_ image: CGImage) -> CGImage {
        let top = statusBarCropPixels(imageHeight: image.height)
        guard top > 0, image.height - top >= 1 else { return image }
        // CGImage's origin is the top-left, so this drops the status bar rather than the bottom.
        let rect = CGRect(x: 0, y: CGFloat(top), width: CGFloat(image.width), height: CGFloat(image.height - top))
        return image.cropping(to: rect) ?? image
    }

    static func cleanedLines(from text: String) -> [String] {
        let stripped = String(text.unicodeScalars.filter { !bidiControls.contains($0) })
        let lines = stripped.components(separatedBy: .newlines).map { line in
            normalizePossibleVisualHebrew(line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
        }.filter { !$0.isEmpty }
        return dropStatusBarChrome(lines)
    }

    static func hebrewLetters(in text: String) -> String {
        String(text.filter(isHebrewLetter))
    }

    static func dropStatusBarChrome(_ lines: [String]) -> [String] {
        lines.filter { !isStatusBarChrome($0) }
    }

    static func isStatusBarChrome(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        let patterns = [
            #"^(5G|4G|LTE|5G\+|5GE|SOS|Wi-?Fi|WLAN|GPS)$"#,
            #"^\d{1,2}:\d{2}(\s?(AM|PM|am|pm))?$"#,
            #"^\d{1,3}%$"#,
            #"^(No SIM|No Service|Carrier|SOS Only)$"#
        ]
        for pattern in patterns {
            if compact.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
            if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        }
        return false
    }

    /// Top-to-bottom. On a mostly-Hebrew line, boxes are joined right-to-left.
    static func orderedLines(_ lines: [OCRLine]) -> [String] {
        guard !lines.isEmpty else { return [] }
        let sorted = lines.sorted { a, b in
            if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.015 {
                return a.boundingBox.midY > b.boundingBox.midY
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        var groups: [[OCRLine]] = []
        for line in sorted {
            if let last = groups.last, let sample = last.first,
               abs(sample.boundingBox.midY - line.boundingBox.midY) <= 0.015 {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map { group in
            let hebrewLine = hebrewLetterRatio(group.map(\.text).joined()) >= 0.4
            let ordered = group.sorted { hebrewLine ? $0.boundingBox.midX > $1.boundingBox.midX : $0.boundingBox.midX < $1.boundingBox.midX }
            return normalizePossibleVisualHebrew(ordered.map(\.text).joined(separator: " "))
        }
    }

    /// If an engine returns Hebrew in visual (left-to-right) order, final-form letters appear at the
    /// start of words. Correct logical Hebrew keeps those forms at the end. Only then do we reverse.
    /// Latin words, numbers and punctuation are reversed back, so a mixed line does not turn "50" into "05".
    static func normalizePossibleVisualHebrew(_ line: String) -> String {
        let scalars = Array(line)
        let letterCount = scalars.filter(isHebrewLetter).count
        let visible = max(scalars.filter { !$0.isWhitespace && !$0.isNewline }.count, 1)
        guard letterCount >= 3, Double(letterCount) / Double(visible) >= 0.5 else { return line }

        let words = line.split { $0.isWhitespace || $0.isNewline }
        func finalScore(_ words: [Substring], atStart: Bool) -> Int {
            words.reduce(0) { score, word in
                let letters = word.filter(isHebrewLetter)
                guard let edge = atStart ? letters.first : letters.last else { return score }
                return score + (isHebrewFinalForm(edge) ? 1 : 0)
            }
        }
        let startScore = finalScore(words, atStart: true)
        let endScore = finalScore(words, atStart: false)
        guard startScore > endScore else { return line }
        return restoreEmbeddedLTR(String(line.reversed()))
    }

    /// After a whole-line reverse, put each Latin, number or punctuation run back in its own order.
    private static func restoreEmbeddedLTR(_ line: String) -> String {
        var result = ""
        var run = ""
        func flush() {
            if !run.isEmpty {
                result.append(contentsOf: run.reversed())
                run.removeAll(keepingCapacity: true)
            }
        }
        for character in line {
            if character.isWhitespace || isHebrewLetter(character) {
                flush()
                result.append(character)
            } else {
                run.append(character)
            }
        }
        flush()
        return result
    }

    private static func preparedImageData(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data)?.normalizedUp(), let cgImage = image.cgImage else {
            throw TextRecognitionError.unreadableImage
        }
        let cropped = croppingStatusBar(cgImage)
        guard let png = UIImage(cgImage: cropped).pngData() else { throw TextRecognitionError.unreadableImage }
        return png
    }

    /// Tesseract 5 expects this directory to contain `heb.traineddata` and `eng.traineddata`.
    private static func tessdataDirectory() -> String? {
        let bundles = [Bundle.main, Bundle(for: TextRecognitionBundleToken.self)]
        for bundle in bundles {
            let named = bundle.url(forResource: "heb", withExtension: "traineddata", subdirectory: "tessdata")
            let flat = bundle.url(forResource: "heb", withExtension: "traineddata")
            guard let hebrew = named ?? flat else { continue }
            let directory = hebrew.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("eng.traineddata").path) {
                return directory.path
            }
        }
        return nil
    }

    private static func tesseractText(_ data: Data, tessdataDirectory: String) throws -> String {
        TesseractSwiftLog.isEnabled = false
        let api = try TesseractSwiftAPI(
            dataPath: tessdataDirectory,
            language: "heb+eng",
            ocrEngineMode: .lstmOnly,
            variables: [OCRVariable.preserveInterwordSpaces: "1"]
        )
        api.pageSegmentationMode = .singleColumn
        guard let pix = PixImage(data: data) else { throw TextRecognitionError.unreadableImage }
        try api.setImage(pix)
        try api.setSourceResolution(ppi: 300)
        return try api.recognizeText() ?? ""
    }

    private static func recognizeWithVision(_ data: Data) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequest.currentRevision
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        if supported.contains("en-US") {
            request.recognitionLanguages = ["en-US"]
            request.automaticallyDetectsLanguage = false
        } else if let first = supported.first {
            request.recognitionLanguages = [first]
            request.automaticallyDetectsLanguage = false
        }
        try VNImageRequestHandler(data: data, options: [:]).perform([request])
        let observations = (request.results ?? []).compactMap { observation -> OCRLine? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return OCRLine(text: text, boundingBox: observation.boundingBox)
        }
        return dropStatusBarChrome(orderedLines(observations))
    }

    private static func hebrewLetterRatio(_ text: String) -> Double {
        let visible = text.filter { !$0.isWhitespace && !$0.isNewline }
        guard !visible.isEmpty else { return 0 }
        return Double(visible.filter(isHebrewLetter).count) / Double(visible.count)
    }

    private static func isHebrewLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (scalar.value >= 0x05D0 && scalar.value <= 0x05EA) || (scalar.value >= 0x05C6 && scalar.value <= 0x05C7)
        }
    }

    private static func isHebrewFinalForm(_ character: Character) -> Bool {
        "ךםןףץ".contains(character)
    }
}

private final class TextRecognitionBundleToken: NSObject {}

private extension UIImage {
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
