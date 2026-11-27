import SwiftUI
import NaturalLanguage

struct NativeActionsView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var completed = false
    private var tasks: [Capture] {
        library.active.filter { $0.hasTask && $0.reviewedAt != nil && ($0.taskCompletedAt != nil) == completed }
            .sorted { ($0.taskDueAt ?? .distantFuture) < ($1.taskDueAt ?? .distantFuture) }
    }
    var body: some View {
        List {
            Section {
                Text("מהצילום לצעד הבא.").font(.title2.bold())
                Text("רק פעולות שבחרת ואישרת. המקור נשאר במרחק נגיעה.")
                    .foregroundStyle(.secondary)
                Picker("מצב פעולות", selection: $completed) {
                    Text("פתוחות").tag(false)
                    Text("בוצעו").tag(true)
                }.pickerStyle(.segmented)
            }
            if tasks.isEmpty {
                ContentUnavailableView(completed ? "הצעדים שביצעת יופיעו כאן." : "לכל רעיון יכול להיות צעד.", systemImage: "checklist",
                    description: Text("פתח מקור, בחר ״לעשות עם זה משהו״, כתוב צעד קטן ושמור."))
            }
            ForEach(tasks) { capture in
                HStack(alignment: .top, spacing: 14) {
                    Button {
                        library.update(capture.id) { $0.taskCompletedAt = completed ? nil : Date() }
                    } label: {
                        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                            .font(.title2).frame(width: 44, height: 44)
                    }.buttonStyle(.borderless).disabled(library.busy)
                        .accessibilityLabel(completed ? "החזר לפעולות פתוחות" : "סמן שבוצע")
                    Button { open(capture) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(capture.taskTitle ?? "").foregroundStyle(.primary)
                                .strikethrough(completed).font(.headline)
                            Text(capture.collection + " · " + capture.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if let due = capture.taskDueAt {
                                Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                    .font(.caption).foregroundStyle(due < Calendar.current.startOfDay(for: Date()) && !completed ? Color.orange : Color.secondary)
                            }
                            Text("פתח את המקור").font(.caption).foregroundStyle(NativeTheme.accent)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                    }.buttonStyle(.borderless)
                }
            }
            Section {
                Text("תאריכי היעד נשמרים כאן. התראות ושילוב ביומן עדיין אינם מחוברים.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("הצעד הבא")
    }
}

enum CollectionBrief {
    static func text(name: String, captures: [Capture]) -> String {
        let sources = captures.filter { !$0.isArchived && $0.effectiveCollection == name }
        var lines = ["# " + name, "איסוף מהמקורות ששמרתי ב־ScreenMind; לא סיכום שנוצר ב־AI.", ""]
        for (index, capture) in sources.enumerated() {
            lines.append("## \(index + 1). \(capture.title)")
            lines.append(capture.text.isEmpty ? "לא צורף טקסט. יש לעיין במקור." : capture.text)
            if capture.hasTask {
                lines.append("הצעד הבא: " + (capture.taskTitle ?? ""))
                lines.append("מצב: " + (capture.taskCompletedAt == nil ? "פתוח" : "בוצע"))
                if let due = capture.taskDueAt { lines.append("תאריך יעד: " + due.formatted(date: .abbreviated, time: .omitted)) }
            }
            lines.append("קובץ מקור: " + capture.originalName)
            lines.append("SHA-256: " + capture.id)
            lines.append("")
        }
        lines.append("הטקסט אינו כולל תמונות. לייצוא המקורות עצמם יש להשתמש בייצוא ZIP מתוך הספרייה.")
        return lines.joined(separator: "\n")
    }
}


// Local evidence-based project identities. No external network requests.
struct ProjectIdentity: Hashable, Sendable {
    let key: String
    let title: String
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![\w@./-])(?:https?://)?(?:www\.)?(?:github\.com/([a-z0-9][a-z0-9-]{0,38})/([a-z0-9_.-]{1,100})|([a-z0-9][a-z0-9-]{0,62})\.netlify\.app)(?=$|[\s/?:#)\],.!;"'])"#,
        options: [.caseInsensitive]
    )
    private static let reserved: Set<String> = [
        "features", "topics", "collections", "marketplace", "settings",
        "search", "orgs", "users", "login", "signup", "notifications", "explore", "sponsors", "about"
    ]
    static func detect(in source: String) -> Set<ProjectIdentity> {
        let text = String(source.prefix(10000))
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = Set<ProjectIdentity>()
        for match in matches {
            func value(_ index: Int) -> String? {
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range]).lowercased()
            }
            if let owner = value(1), let rawRepo = value(2), !reserved.contains(owner) {
                var repo = rawRepo.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if repo.hasSuffix(".git") { repo.removeLast(4) }
                guard !repo.isEmpty else { continue }
                result.insert(ProjectIdentity(key: "github:" + owner + "/" + repo, title: owner + "/" + repo))
            } else if let site = value(3) {
                result.insert(ProjectIdentity(key: "netlify:" + site, title: site + ".netlify.app"))
            }
        }
        return result
    }
}

struct ProjectCluster: Identifiable, Sendable {
    let identity: ProjectIdentity
    let sources: [Capture]
    var id: String { identity.key }
    var title: String { identity.title }
    var hasUnknownDates: Bool { sources.contains { $0.photoCreatedAt == nil } }

    static func build(from captures: [Capture]) -> [ProjectCluster] {
        var groups: [ProjectIdentity: [Capture]] = [:]
        for capture in captures where !capture.isArchived {
            let references = ProjectIdentity.detect(in: capture.title + "\n" + capture.text)
            // Multiple distinct links are ambiguous. Do not force membership.
            guard references.count == 1, let identity = references.first else { continue }
            groups[identity, default: []].append(capture)
        }
        return groups.compactMap { identity, sources -> ProjectCluster? in
            guard sources.count >= 2 else { return nil }
            let ordered = sources.sorted {
                $0.sourceDate == $1.sourceDate ? $0.id < $1.id : $0.sourceDate < $1.sourceDate
            }
            return ProjectCluster(identity: identity, sources: ordered)
        }.sorted {
            $0.sources.count == $1.sources.count ? $0.id < $1.id : $0.sources.count > $1.sources.count
        }
    }

    // Evidence-only article draft, not a generative summary.
    var brief: String {
        var lines = ["# " + title, "טיוטת מקורות לפי ציר זמן, לא סיכום AI.", ""]
        if hasUnknownDates { lines += ["בחלק מהמקורות מוצג תאריך הייבוא במקום תאריך הצילום.", ""] }
        for (index, capture) in sources.enumerated() {
            lines += [
                "## \(index + 1). \(capture.displayTitle)",
                (capture.photoCreatedAt == nil ? "תאריך ייבוא: " : "תאריך צילום: ") +
                    capture.sourceDate.formatted(date: .abbreviated, time: .shortened),
                capture.text.isEmpty ? "אין טקסט מזוהה." : capture.text,
                "מזהה מקור: " + capture.id,
                ""
            ]
        }
        return lines.joined(separator: "\n")
    }
}

struct ProjectTimelineView: View {
    let cluster: ProjectCluster
    let open: (Capture) -> Void
    @EnvironmentObject private var library: NativeLibrary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("ציר זמן של הפרויקט", systemImage: "clock.arrow.circlepath")
                    .font(.title2.bold())
                Text(cluster.title).font(.headline).textSelection(.enabled)
                Text("\(cluster.sources.count) מקורות עם כתובת פרויקט משותפת")
                    .foregroundStyle(.secondary)
                if cluster.hasUnknownDates {
                    Label("למקורות ללא תאריך צילום מוצג תאריך הייבוא.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                NavigationLink {
                    ProjectStoryView(identity: cluster.identity, open: open)
                } label: {
                    Label("צור כתבה מהפרויקט", systemImage: "book.pages")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                ShareLink(item: cluster.brief) {
                    Label("ייצא טיוטת מקורות", systemImage: "square.and.arrow.up")
                }.buttonStyle(.borderedProminent)
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(cluster.sources) { capture in
                        Button {
                            if let current = library.capture(capture.id) { open(current) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                if let image = library.thumbnail(capture) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: 76, height: 92).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(capture.sourceDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(capture.displayTitle).font(.headline).lineLimit(3)
                                    Text(capture.text).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.backward").font(.caption).foregroundStyle(.secondary)
                            }.padding(12).background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(18)
        }.background(NativeTheme.canvas)
            .navigationTitle("פרויקט")
            .navigationBarTitleDisplayMode(.inline)
    }
}


// Search is deliberately read-only. Apple sentence embeddings are used only
// when the OS supplies one for the query language; lexical search always works.
struct MemorySearchHit: Identifiable, Sendable {
    enum Match: String, Sendable { case exact, partial, semantic, related }
    let id: String
    let score: Double
    let match: Match
}
struct MemorySearchResponse: Sendable {
    let hits: [MemorySearchHit]
    let semanticAvailable: Bool
    let semanticExamined: Int
    let total: Int
}
actor MemorySearchEngine {
    static let shared = MemorySearchEngine()
    private var embeddings: [String: NLEmbedding] = [:]
    private var vectors: [String: [Double]] = [:]
    private var vectorOrder: [String] = []
    private var vectorHead = 0
    private let vectorCapacity = 4096
    private var indexedCaptures: [Capture] = []
    private var lexicalIndex: MemoryLexicalIndex?
    nonisolated static func lexical(query: String, capture: Capture) -> MemorySearchHit? {
        MemoryLexicalIndex(captures: [capture]).search(query, limit: 1).first
    }
    nonisolated static func semanticCandidates(_ captures: [Capture], excluding: Set<String>) -> [Capture] {
        captures.filter { !$0.isArchived && !excluding.contains($0.id) }
    }
    nonisolated static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot = 0.0, a = 0.0, b = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            a += lhs[index] * lhs[index]
            b += rhs[index] * rhs[index]
        }
        guard a > 0, b > 0 else { return nil }
        let score = dot / (sqrt(a) * sqrt(b))
        return score.isFinite ? score : nil
    }
    private func vector(_ text: String, language: NLLanguage, model: NLEmbedding) -> [Double]? {
        let key = language.rawValue + "\u{001F}" + text
        if let cached = vectors[key] { return cached }
        guard let value = model.vector(for: text), !value.isEmpty else { return nil }
        if vectors.count >= vectorCapacity {
            vectors.removeValue(forKey: vectorOrder[vectorHead])
            vectorHead += 1
            if vectorHead >= 1024 {
                vectorOrder.removeFirst(vectorHead)
                vectorHead = 0
            }
        }
        vectors[key] = value
        vectorOrder.append(key)
        return value
    }
    func search(query: String, captures: [Capture]) -> MemorySearchResponse {
        let active = captures.filter { !$0.isArchived }
        let cleaned = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        var hits: [MemorySearchHit] = []
        guard !cleaned.isEmpty else {
            return MemorySearchResponse(hits: [], semanticAvailable: false, semanticExamined: 0, total: active.count)
        }
        if lexicalIndex == nil || indexedCaptures != active {
            lexicalIndex = MemoryLexicalIndex(captures: active)
            indexedCaptures = active
        }
        hits = lexicalIndex?.search(cleaned) ?? []
        var available = false
        var examined = 0
        if !Task.isCancelled, let language = NLLanguageRecognizer.dominantLanguage(for: cleaned) {
            let key = language.rawValue
            if let model = embeddings[key] ?? NLEmbedding.sentenceEmbedding(for: language) {
                embeddings[key] = model
                if let queryVector = vector(cleaned, language: language, model: model) {
                    available = true
                    let exactIDs = Set(hits.filter { $0.match == .exact }.map(\.id))
                    let recent = Self.semanticCandidates(active, excluding: exactIDs)
                    // Search every active capture when the local language model is available.
                    // Cancellation remains cooperative between documents.
                    for capture in recent {
                        if Task.isCancelled { break }
                        let sample = String((capture.title + "\n" + capture.text).prefix(600))
                        guard NLLanguageRecognizer.dominantLanguage(for: sample) == language,
                              let value = vector(sample, language: language, model: model) else { continue }
                        examined += 1
                        if let similarity = Self.cosine(queryVector, value), similarity >= 0.72 {
                            hits.append(MemorySearchHit(id: capture.id, score: similarity * 10, match: .semantic))
                        }
                    }
                }
            }
        }
        var best: [String: MemorySearchHit] = [:]
        for hit in hits where hit.score > (best[hit.id]?.score ?? -1) { best[hit.id] = hit }
        let ranked = best.values.sorted {
            $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
        }
        return MemorySearchResponse(hits: Array(ranked.prefix(60)), semanticAvailable: available,
                                    semanticExamined: examined, total: active.count)
    }
}

struct MemorySearchView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var query = ""
    @State private var response: MemorySearchResponse?
    @State private var running = false
    @State private var revision = 0
    @State private var recentQuestions: [String] = []
    @State private var contextQuestion = ""
    @State private var useContext = false
    private struct Request: Hashable {
        let query: String
        let revision: Int
        let context: String
    }
    private var activeContext: String { useContext ? contextQuestion : "" }
    var body: some View {
        List {
            Section {
                Text("חפש בזיכרון שלך").font(.title2.bold())
                Text("אפשר לכתוב שאלה או כמה מילים. התוצאות מקושרות לצילום המקורי.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if running { ProgressView("מחפש במכשיר…") }
                if let response, !running {
                    if response.semanticAvailable {
                        Text("חיפוש מילים ב־\(response.total) מקורות; דמיון סמנטי נבדק ב־\(response.semanticExamined) מקורות נוספים, מכל הספרייה הפעילה.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("חיפוש מקומי לפי מילים ב־\(response.total) מקורות. מודל סמנטי אינו זמין לשאלה זו.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !recentQuestions.isEmpty {
                Section("שאלות אחרונות — בהפעלה זו בלבד") {
                    ForEach(recentQuestions, id: \.self) { question in
                        Button { useContext = false; query = question } label: {
                            Label(question, systemImage: "clock.arrow.circlepath")
                        }
                    }
                    Button("נקה היסטוריה", role: .destructive) { recentQuestions.removeAll(); contextQuestion = ""; useContext = false }
                }
            }
            if !contextQuestion.isEmpty {
                Section("הקשר לחיפוש המשך") {
                    Text(contextQuestion).font(.caption).textSelection(.enabled)
                    Toggle("כלול שאלה קודמת בחיפוש המקומי", isOn: $useContext)
                    Button("הסר הקשר") { useContext = false; contextQuestion = "" }
                }
            }
            if let response, !running {
                Section {
                    Button {
                        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !question.isEmpty else { return }
                        recentQuestions.removeAll { $0 == question }
                        recentQuestions.insert(question, at: 0)
                        recentQuestions = Array(recentQuestions.prefix(12))
                    } label: {
                        Label("שמור שאלה להפעלה זו", systemImage: "bookmark")
                    }
                    Button("השתמש בשאלה זו כהקשר לשאלה הבאה") {
                        contextQuestion = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
                        query = ""
                        useContext = true
                    }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("ההקשר משמש להרחבת החיפוש המקומי בלבד. אין עדיין הבנה של תשובות קודמות.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                let candidates = Array(response.hits.compactMap { library.capture($0.id) }
                    .filter { !$0.isArchived && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count >= 12 }
                    .prefix(8))
                if !candidates.isEmpty {
                    Section("תשובה מתוך הזיכרון") {
                        Text("נמצאו מקורות אפשריים לשאלה. בדוק אותם לפני יצירת טיוטה. החיפוש המקומי אינו תשובה מאומתת.")
                            .font(.caption).foregroundStyle(.secondary)
                        NavigationLink {
                            GroundedArticleView(title: GroundedArticleResult.clip(query, limit: 120),
                                                captures: candidates, open: open)
                        } label: {
                            Label("הכן טיוטת כתבה בנושא מ־\(candidates.count) מקורות באמצעות AI", systemImage: "sparkles")
                        }
                        Text("השליחה לשרת פרטי אופציונלית ודורשת אישור. ניתן להסיר מקורות ולערוך את הטקסט לפני השליחה. גם כותרת השאלה תישלח.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if response.hits.isEmpty {
                    ContentUnavailableView("לא נמצאה התאמה", systemImage: "magnifyingglass",
                                           description: Text("נסה שם, מילה אחרת או ביטוי קצר. צילומים שלא זוהה בהם טקסט עלולים שלא להופיע."))
                }
                ForEach(response.hits) { hit in
                    if let capture = library.capture(hit.id) {
                        Button { open(capture) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(hit.match == .semantic ? "דמיון במשמעות" : hit.match == .exact ? "התאמת מילות חיפוש" : hit.match == .related ? "מילים מקבילות או נטייה" : "התאמה חלקית",
                                      systemImage: hit.match == .semantic ? "sparkles" : "magnifyingglass")
                                    .font(.caption).foregroundStyle(NativeTheme.accent)
                                Text(capture.displayTitle).font(.headline).foregroundStyle(.primary)
                                Text(capture.text).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("חיפוש חכם")
        .searchable(text: $query, prompt: "מה אני רוצה למצוא?")
        .onChange(of: library.captures) { _, _ in revision += 1 }
        .task(id: Request(query: query, revision: revision, context: activeContext)) {
            response = nil
            let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { running = false; return }
            running = true
            do { try await Task.sleep(nanoseconds: 350_000_000) }
            catch { return }
            let searchText = activeContext.isEmpty ? input : activeContext + " " + input
            let result = await MemorySearchEngine.shared.search(query: searchText, captures: library.captures)
            guard !Task.isCancelled else { return }
            response = result
            running = false
        }
    }
}


// Optional cloud enrichment. The provider API key belongs on the user's
// gateway, never in this app. The gateway token is kept only for this screen.
private struct AIWireInput: Codable, Sendable {
    let id: String
    let title: String
    let text: String
}
private struct AIBatchSource: Identifiable, Sendable {
    let id: String
    let captureID: String
    let digest: String
    let wire: AIWireInput
}
private struct AIWireResult: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let topic: String
    let suggestedTask: String
}
private struct AIWireRequest: Encodable {
    let language: String
    let items: [AIWireInput]
}
private struct AIWireResponse: Decodable {
    let items: [AIWireResult]
}
private final class AIGatewayNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
private enum AIGateway {
    static func endpoint(_ raw: String) -> URL? {
        guard let parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path == "/analyze" else { return nil }
        return parts.url
    }
    static func analyze(endpoint: URL, token: String, language: String,
                        sources: [AIBatchSource]) async throws -> [AIWireResult] {
        guard !sources.isEmpty, sources.count <= 12, token.count >= 32 else {
            throw NativeError.message("חסרים פרטי חיבור או מקורות.")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 70)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(AIWireRequest(language: language, items: sources.map(\.wire)))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: AIGatewayNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 128 * 1024 else {
            throw NativeError.message("השרת לא החזיר ניתוח תקין. בדוק כתובת, הרשאה ומגבלת שימוש.")
        }
        let output = try JSONDecoder().decode(AIWireResponse.self, from: data).items
        let expected = Set(sources.map(\.id))
        guard output.count == expected.count, Set(output.map(\.id)) == expected,
              output.allSatisfy({ item in
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  item.title.utf16.count <= 240 && item.summary.utf16.count <= 1200 &&
                  item.suggestedTask.utf16.count <= 300 &&
                  (item.topic == "unknown" || SmartTopic(rawValue: item.topic) != nil)
              }) else { throw NativeError.message("התקבלה תשובה חסרה או לא תקינה. דבר לא נשמר.") }
        return output
    }
}

struct AIEnrichmentView: View {
    @EnvironmentObject private var library: NativeLibrary
    @State private var endpointText = ""
    @State private var token = ""
    @State private var language = "he"
    @State private var sources: [AIBatchSource] = []
    @State private var output: [AIWireResult] = []
    @State private var resultLanguage = "he"
    @State private var running = false
    @State private var message = ""
    @State private var work: Task<Void, Never>?
    private let languages = [
        ("he","עברית"),("en","English"),("ru","Русский"),("es","Español"),
        ("fr","Français"),("de","Deutsch"),("ar","العربية"),("it","Italiano"),
        ("pt","Português"),("ja","日本語"),("zh","中文"),("hi","हिन्दी")
    ]
    private var ready: Bool {
        AIGateway.endpoint(endpointText) != nil && token.count >= 32 && !sources.isEmpty && !running
    }
    var body: some View {
        List {
            Section {
                Text("הבנת תוכן באמצעות AI").font(.title2.bold())
                Text("אפשרות ניסיונית. חיבור לשרת פרטי נדרש. רק הטקסט המוצג בסבב יישלח לשרת ולספק AI לאחר לחיצה מפורשת. אין שליחת תמונות ואין שליחה אוטומטית.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("אין לשלוח סיסמאות, מידע צבאי, מסמכים אישיים או פרטי זיהוי. הספק עשוי לשמור נתונים בהתאם למדיניותו ולחייב לפי שימוש.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Section("חיבור לשרת") {
                TextField("https://your-server.example/analyze", text: $endpointText)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("אסימון גישה לשרת (לא מפתח OpenAI)", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("שפת התוצאה", selection: $language) {
                    ForEach(languages.indices, id: \.self) { index in Text(languages[index].1).tag(languages[index].0) }
                }
            }.disabled(running)
            Section("תצוגה מקדימה של המידע שישלח") {
                Button("הכן עד 12 מקורות שטרם נותחו") { prepare() }
                    .disabled(running || library.busy)
                if sources.isEmpty {
                    Text("לא נבחרו מקורות. לחיצה על הכנה אינה שולחת מידע.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(sources) { source in
                    DisclosureGroup(source.wire.title.isEmpty ? "צילום" : source.wire.title) {
                        Text(source.wire.text).font(.caption).textSelection(.enabled)
                        Button("הסר מהסבב", role: .destructive) {
                            sources.removeAll { $0.id == source.id }; output = []
                        }
                    }.disabled(running)
                }
                Button {
                    start()
                } label: {
                    Label("אשר שליחת \(sources.count) מקורות ל־AI", systemImage: "sparkles")
                }.disabled(!ready)
                if running {
                    ProgressView("מנתח את הסבב…")
                    Button("בטל") { work?.cancel(); work = nil; running = false }
                }
            }
            if !output.isEmpty {
                Section("תוצאות מוצעות — עדיין לא נשמרו") {
                    ForEach(output) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.title).font(.headline)
                            Text(item.summary).font(.subheadline)
                            Text(SmartTopic(rawValue: item.topic)?.label ?? "נושא לא ודאי")
                                .font(.caption).foregroundStyle(.secondary)
                            if !item.suggestedTask.isEmpty {
                                Label(item.suggestedTask, systemImage: "checklist").font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                    Button("שמור את המיון והסיכומים של כל הסבב") { apply() }
                        .disabled(running || library.busy || library.scanLoopActive)
                }
            }
            if !message.isEmpty { Section { Text(message).font(.subheadline) } }
            Section {
                Text("הניתוח נשמר בשדה נפרד. תיקונים ידניים, המקורות ואישורי מחיקה אינם משתנים. שינוי בטקסט מבטל ניתוח ישן. משימות הן הצעות בלבד.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("ScreenMind AI")
            .onDisappear { work?.cancel(); work = nil; running = false; token = "" }
    }
    private func prepare() {
        let candidates = library.active.filter {
            $0.currentAIAnalysis == nil && !$0.aiInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.sourceDate > $1.sourceDate }
        sources = Array(candidates.prefix(12).enumerated()).map { index, capture in
            let id = "s\(index)"
            return AIBatchSource(id: id, captureID: capture.id, digest: capture.aiSourceDigest,
                                 wire: AIWireInput(id: id, title: capture.aiInputTitle, text: capture.aiInputText))
        }
        output = []
        message = sources.isEmpty ? "אין מקורות נוספים עם טקסט מזוהה." : "בדוק את הטקסט והסר מידע רגיש לפני השליחה."
    }
    private func start() {
        guard ready, let url = AIGateway.endpoint(endpointText) else { return }
        let batch = sources, accessToken = token, selectedLanguage = language
        running = true; output = []; message = ""
        work = Task {
            do {
                let result = try await AIGateway.analyze(endpoint: url, token: accessToken,
                                                         language: selectedLanguage, sources: batch)
                guard !Task.isCancelled else { return }
                resultLanguage = selectedLanguage
                output = result
                message = "בדוק את ההצעות. אפשר לשמור את כל הסבב בלחיצה אחת."
            } catch {
                guard !Task.isCancelled else { return }
                message = "הניתוח נכשל. לא נשמר דבר. בדוק את החיבור לשרת."
            }
            running = false
        }
    }
    private func apply() {
        var analyses: [String: AIAnalysis] = [:]
        for item in output {
            guard let source = sources.first(where: { $0.id == item.id }) else { continue }
            analyses[source.captureID] = AIAnalysis(sourceDigest: source.digest, title: item.title,
                summary: item.summary, topic: item.topic, suggestedTask: item.suggestedTask, language: resultLanguage)
        }
        let count = library.applyAIAnalyses(analyses)
        message = "נשמרו \(count) ניתוחים מתוך \(analyses.count). מקורות שהשתנו או לא נשמרו לא עודכנו."
        sources = []; output = []
    }
}
