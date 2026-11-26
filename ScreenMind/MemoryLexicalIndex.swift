import Foundation

// Deterministic lexical retrieval. Related matches are curated vocabulary or
// conservative Hebrew prefixes, not a translation model or semantic AI.
struct MemoryLexicalIndex: Sendable {
    private struct Document: Sendable {
        let id: String
        let weights: [String: Double]
        let related: [String: Double]
    }
    private let documents: [Document]
    private let frequencies: [String: Int]
    private static let stopWords: Set<String> = [
        "את","של","על","עם","מה","איך","איפה","מתי","לי","אני","כל","מצא","תמצא","צילמתי","שמרתי","האם","רוצה","למצוא","תראה","שהיה",
        "the","a","an","to","of","in","my","me","what","where","find","show","saved","about","did","i","is","was","please","can","you",
        "где","что","мне","найди","как","про","это","мой","мои","сохранил","покажи","пожалуйста"
    ]
    // Deliberately small, auditable vocabulary. Ambiguous aliases are omitted.
    private static let concepts: [[String]] = [
        ["משכנתה","משכנתא","mortgage","ипотека"],
        ["חשבונית","invoice","factura","facture","rechnung","счёт"],
        ["מתכון","recipe","рецепт","receta","recette","rezept"],
        ["טיסה","flight","рейс","vuelo"],
        ["מלון","hotel","отель","hôtel"],
        ["קורס","course","курс","curso","cours"],
        ["מדריך","tutorial","учебник","tutoriel"],
        ["תכנות","programming","программирование","programmation"],
        ["תקציב","budget","бюджет","presupuesto"],
        ["תשלום","payment","оплата","paiement","pago"],
        ["חוזה","contract","договор","contrato","contrat"],
        ["סוללה","battery","батарея","batterie","batería"],
        ["גיבוי","backup","резервирование","sauvegarde"],
        ["רחפן","drone","дрон"],
        ["מלגה","scholarship","стипендия","bourse"],
        ["משאית","truck","грузовик","camion"]
    ]
    private static let conceptKeys: [String: String] = {
        var result: [String: String] = [:]
        for (index, words) in concepts.enumerated() {
            for word in words { result[normalize(word)] = "concept:\(index)" }
        }
        return result
    }()
    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }
    static func terms(_ query: String) -> [String] {
        let all = normalize(query).split(separator: " ").map(String.init)
        let useful = all.filter { !stopWords.contains($0) }
        return Array(Set(useful)).sorted()
    }
    private static func keys(_ word: String) -> Set<String> {
        var keys: Set<String> = [word]
        // One prefix, at least four remaining Hebrew letters; no stemming of
        // numbers, URLs, English or Russian. This is a lower-weight match.
        if word.count >= 5, let first = word.first, "הובלמשכ".contains(first),
           word.unicodeScalars.allSatisfy({ (0x05D0...0x05EA).contains($0.value) }) {
            keys.insert(String(word.dropFirst()))
        }
        for key in Array(keys) {
            if let concept = conceptKeys[key] { keys.insert(concept) }
        }
        return keys
    }
    init(captures: [Capture]) {
        var docs: [Document] = []
        var counts: [String: Int] = [:]
        for capture in captures where !capture.isArchived {
            var weights: [String: Double] = [:]
            // The actual OCR and title are more reliable than a category name.
            for (field, weight) in [(capture.title, 4.0), (capture.text, 2.0), (capture.effectiveCollection, 0.6)] {
                for word in Self.terms(field) {
                    weights[word] = max(weights[word] ?? 0, weight)
                }
            }
            var related: [String: Double] = [:]
            for (word, weight) in weights {
                for key in Self.keys(word) { related[key] = max(related[key] ?? 0, weight) }
            }
            for key in related.keys { counts[key, default: 0] += 1 }
            docs.append(Document(id: capture.id, weights: weights, related: related))
        }
        documents = docs
        frequencies = counts
    }
    func search(_ query: String, limit: Int = 60) -> [MemorySearchHit] {
        let queryTerms = Self.terms(String(query.prefix(500)))
        guard !queryTerms.isEmpty, limit > 0 else { return [] }
        let queries = queryTerms.map { term -> (String, Set<String>, Double) in
            let keys = Self.keys(term)
            let count = keys.map { frequencies[$0] ?? 0 }.max() ?? 0
            let rarity = 1 + log(Double(documents.count + 1) / Double(count + 1))
            return (term, keys, rarity)
        }
        var results: [MemorySearchHit] = []
        for doc in documents {
            if Task.isCancelled { break }
            var matched = 0, direct = 0, sourceMatches = 0
            var score = 0.0
            for (term, keys, rarity) in queries {
                if let weight = doc.weights[term], weight >= 2 {
                    direct += 1; matched += 1; sourceMatches += 1
                    score += weight * rarity
                } else if let weight = keys.compactMap({ doc.related[$0] }).max() {
                    matched += 1
                    if weight >= 2 { sourceMatches += 1 }
                    score += weight * rarity * 0.55
                }
            }
            // A category alone cannot prove the source contains the answer.
            guard sourceMatches > 0, matched * 2 >= queries.count else { continue }
            let kind: MemorySearchHit.Match
            let base: Double
            if direct == queries.count { kind = .exact; base = 100 }
            else if matched == queries.count { kind = .related; base = 75 }
            else { kind = .partial; base = 50 }
            // Bound the bonus to keep match tiers stable regardless of corpus size.
            results.append(MemorySearchHit(id: doc.id,
                score: base + min(20, score / Double(queries.count)), match: kind))
        }
        return Array(results.sorted {
            $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
        }.prefix(limit))
    }
}
