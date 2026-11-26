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
    var photoCreatedAt: Date?
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


// Conservative multilingual local baseline. Not a semantic AI model.
enum SmartTopic: String, CaseIterable, Sendable {
    case technology, learning, finance, shopping, work, media, travel, food, documents
    var label: String {
        switch self {
        case .technology: return "טכנולוגיה ופיתוח"
        case .learning: return "למידה ומדריכים"
        case .finance: return "כספים ותשלומים"
        case .shopping: return "קניות ומוצרים"
        case .work: return "עבודה ועסקים"
        case .media: return "תוכן ויצירה"
        case .travel: return "נסיעות ומקומות"
        case .food: return "אוכל ומתכונים"
        case .documents: return "מסמכים ותיעוד"
        }
    }
    private var keywords: [String] {
        switch self {
        case .technology: return ["github","swiftui","python","javascript","claude","chatgpt","gemini","api","codex","docker","typescript","programming","repository","קוד","תכנות","מפתחים","בינה מלאכותית","программирование","репозиторий","programación","programmation","programmierung","برمجة","ذكاء اصطناعي"]
        case .learning: return ["tutorial","course","lecture","curriculum","exam","study guide","lesson","מדריך","קורס","לימודים","שיעור","בגרות","מחקר","учебник","курс","лекция","tutoriales","curso","cours","examen","unterricht","درس","دورة"]
        case .finance: return ["invoice","receipt","payment","banking","mortgage","salary","budget","חשבונית","קבלה","תשלום","משכנתא","משכנתה","תקציב","оплата","квитанция","ипотека","factura","pago","paiement","facture","rechnung","zahlung","فاتورة","دفع"]
        case .shopping: return ["shopping","product","discount","black friday","checkout","קניות","מוצר","מבצע","הנחה","משלוח","скидка","покупка","товар","descuento","compra","achat","réduction","rabatt","einkauf","تسوق","خصم"]
        case .work: return ["job vacancy","resume","recruitment","hiring","supplier","project management","משרה","דרושים","קורות חיים","ספק","עסקים","вакансия","резюме","поставщик","empleo","recrutement","stellenangebot","وظيفة","توظيف"]
        case .media: return ["youtube","tiktok","instagram","podcast","video editing","thumbnail","סרטון","עריכה","פודקאסט","יוטיוב","תוכן","видео","подкаст","vidéo","vídeo","video","فيديو","بودكاست"]
        case .travel: return ["flight","hotel","boarding pass","itinerary","passport","טיסה","מלון","מסלול טיול","דרכון","рейс","отель","билет","vuelo","vol","hôtel","flug","رحلة","فندق"]
        case .food: return ["recipe","ingredients","cooking","pasta","מתכון","מצרכים","בישול","פסטה","рецепт","ингредиенты","receta","recette","rezept","وصفة","مكونات"]
        case .documents: return ["certificate","contract","application form","passport number","תעודה","חוזה","טופס","מסמך","договор","справка","contrato","certificado","contrat","vertrag","شهادة","عقد"]
        }
    }
    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    private static let vocabulary: [SmartTopic: [[String]]] =
        Dictionary(uniqueKeysWithValues: allCases.map { topic in (topic, topic.keywords.map { words($0) }) })
    // Bounded in-memory cache: exact bounded input is the key, so edits invalidate
    // the result. NSCache is thread-safe and evicts under memory pressure.
    private static let cache: NSCache<NSString, NSString> = {
        let result = NSCache<NSString, NSString>()
        result.countLimit = 3000
        result.totalCostLimit = 12 * 1024 * 1024
        return result
    }()
    static func classify(title: String, text: String) -> SmartTopic? {
        let head = String(title.prefix(240))
        let body = String(text.prefix(6000))
        let key = "\(head.utf16.count):\(head)\(body)" as NSString
        if let saved = cache.object(forKey: key) {
            return SmartTopic(rawValue: saved as String)
        }
        let result = classifyUncached(head + " " + body)
        cache.setObject((result?.rawValue ?? "") as NSString, forKey: key, cost: key.length * 2 + 64)
        return result
    }
    private static func classifyUncached(_ source: String) -> SmartTopic? {
        let tokens = words(source)
        let unique = Set(tokens)
        guard !unique.isEmpty else { return nil }
        let padded = " " + tokens.joined(separator: " ") + " "
        let ranked = allCases.map { topic -> (SmartTopic, Int) in
            let score = (vocabulary[topic] ?? []).reduce(0) { score, phrase in
                if phrase.count == 1, let word = phrase.first { return score + (unique.contains(word) ? 1 : 0) }
                return score + (padded.contains(" " + phrase.joined(separator: " ") + " ") ? 2 : 0)
            }
            return (topic, score)
        }.sorted { $0.1 == $1.1 ? $0.0.rawValue < $1.0.rawValue : $0.1 > $1.1 }
        guard let best = ranked.first, best.1 > 0,
              ranked.dropFirst().first?.1 != best.1 else { return nil }
        return best.0
    }
    static func readableTitle(title: String, text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let line = lines.first { value in
            value.count >= 18 && words(value).count >= 3 && value.filter(\.isLetter).count >= 10
        }
        if let line { return String(line.prefix(100)) }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 5 ? String(trimmed.prefix(100)) : "צילום מסך"
    }
}
extension Capture {
    var hasManualCollection: Bool {
        let value = collection.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value != "כללי"
    }
    var smartTopic: SmartTopic? { SmartTopic.classify(title: title, text: text) }
    var effectiveCollection: String { hasManualCollection ? collection : (smartTopic?.label ?? "רעיונות פתוחים") }
    var displayTitle: String { reviewedAt != nil ? title : SmartTopic.readableTitle(title: title, text: text) }
    var sourceDate: Date { photoCreatedAt ?? createdAt }
    var needsTextAttention: Bool { textStatus == "failed" || textStatus == "noText" }
}
