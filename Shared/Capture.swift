import Foundation

enum SaveIntent: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case remember, act, inspiration, evidence
    var id: String { rawValue }
    var title: String {
        switch self {
        case .remember: return "לזכור ולחזור"
        case .act: return "לעשות עם זה משהו"
        case .inspiration: return "לשמור כהשראה"
        case .evidence: return "לשמור כתיעוד"
        }
    }
}
struct Capture: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var originalName: String
    var photoIdentifier: String?
    var createdAt: Date
    var title: String
    var text: String
    var collection: String = "כללי"
    var intent: SaveIntent = .remember
    var reviewedAt: Date?
    var viewedAt: Date?
    var photoDeletedAt: Date?
    var isArchived: Bool = false
    var isFavorite: Bool = false
    var textStatus: String = "pending"
    var source: String
    var taskTitle: String?
    var taskDueAt: Date?
    var taskCompletedAt: Date?
    var digest: String { id }
    var needsReview: Bool { reviewedAt == nil }
    var hasTask: Bool { intent == .act && !(taskTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
enum NativeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
struct CleanupFacts {
    let reviewed: Bool
    let viewedOriginal: Bool
    let archiveMatches: Bool
    let externalBackupMatches: Bool
    let exactPhotoMatches: Bool
    let isUneditedScreenshot: Bool
    var permitsDeletion: Bool {
        reviewed && viewedOriginal && archiveMatches && externalBackupMatches && exactPhotoMatches && isUneditedScreenshot
    }
}
