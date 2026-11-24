import Foundation

// On-device hints from the ChatGPT research on 100 real screenshots:
// information that goes stale, claims that need checking, and frames
// of one video or thread that belong together. Nothing is uploaded or changed.
enum CaptureInsight: String, CaseIterable, Equatable, Sendable {
    case timeSensitive
    case unverifiedClaim

    var title: String {
        switch self {
        case .timeSensitive: return "מידע שתלוי בזמן"
        case .unverifiedClaim: return "טענה שכדאי לבדוק"
        }
    }

    var detail: String {
        switch self {
        case .timeSensitive: return "יש כאן תאריך, יתרה או מכסה. זה היה נכון ביום הצילום, ואולי השתנה מאז."
        case .unverifiedClaim: return "נראה כמו פרסום, מבצע או הבטחת רווח. לא אומת."
        }
    }

    var symbol: String {
        switch self {
        case .timeSensitive: return "clock.badge.exclamationmark"
        case .unverifiedClaim: return "exclamationmark.shield"
        }
    }
}

enum CaptureInsights {
    private static let timeWords = [
        "יתרה", "יתרת", "מכסה", "מכסת", "איפוס", "מתאפס", "בתוקף", "נותרו", "נשארו", "תאריך אחרון",
        "פתיחת שערים", "כרטיס", "הזמנה", "ינואר", "פברואר", "מרץ", "אפריל", "מאי", "יוני", "יולי",
        "אוגוסט", "ספטמבר", "אוקטובר", "נובמבר", "דצמבר", "deadline", "expires", "resets", "reset", "remaining", "quota"
    ]
    private static let claimWords = [
        "רווח", "תשואה", "הכנסה פסיבית", "מובטח", "בחינם", "חינם", "מבצע", "הטבה", "הנחה", "קריפטו", "ביטקוין",
        "giveaway", "guaranteed", "profit", "passive income", "crypto", "bitcoin", "free for", "% off"
    ]
    private static let datePattern = try? NSRegularExpression(pattern: "(?<!\\d)\\d{1,2}[./]\\d{1,2}(?:[./]\\d{2,4})?(?!\\d)")
    private static let moneyPattern = try? NSRegularExpression(pattern: "[$₪€]\\s?\\d|\\d\\s?[$₪€]")

    static func detect(title: String, text: String) -> [CaptureInsight] {
        let body = (title + "\n" + text).lowercased()
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var result: [CaptureInsight] = []
        if timeWords.contains(where: { body.contains($0) }) || matches(datePattern, body) {
            result.append(.timeSensitive)
        }
        let claimHits = claimWords.filter { body.contains($0) }.count
        if claimHits >= 2 || (claimHits >= 1 && matches(moneyPattern, body)) {
            result.append(.unverifiedClaim)
        }
        return result
    }

    private static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

enum CaptureSequences {
    static let window: TimeInterval = 15 * 60
    static let minimumLength = 3

    // Consecutive captures, at most `window` apart, each sharing at least two
    // words with the previous one, form one sequence (one reel, one thread).
    static func sequences(in captures: [Capture]) -> [[Capture]] {
        let active = captures.filter { !$0.isArchived }.sorted { lhs, rhs in
            lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.id < rhs.id
        }
        var groups: [[Capture]] = []
        var current: [Capture] = []
        var previousTokens: Set<String> = []
        for capture in active {
            let tokens = Set(BrainText.tokens(title: capture.title, text: capture.text))
            if let last = current.last,
               capture.createdAt.timeIntervalSince(last.createdAt) <= window,
               tokens.intersection(previousTokens).count >= 2 {
                current.append(capture)
            } else {
                if current.count >= minimumLength { groups.append(current) }
                current = [capture]
            }
            previousTokens = tokens
        }
        if current.count >= minimumLength { groups.append(current) }
        return groups
    }

    static func sequence(containing id: String, in captures: [Capture]) -> [Capture] {
        sequences(in: captures).first { group in group.contains { $0.id == id } } ?? []
    }
}
