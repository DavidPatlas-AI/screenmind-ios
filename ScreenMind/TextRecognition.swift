import Foundation
import Vision

struct TextResult: Sendable {
    let text: String
    let title: String
    let hebrewSupported: Bool
}
enum TextRecognition {
    static func recognize(_ data: Data) async throws -> TextResult {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = try request.supportedRecognitionLanguages()
            let desired = ["he-IL", "en-US"].filter { supported.contains($0) }
            if !desired.isEmpty { request.recognitionLanguages = desired }
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(data: data, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            let title = String((lines.first ?? "צילום חדש").prefix(90))
            return TextResult(text: text, title: title, hebrewSupported: supported.contains("he-IL"))
        }.value
    }
}
