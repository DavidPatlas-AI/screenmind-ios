import SwiftUI
import UniformTypeIdentifiers
import UIKit

// Local, evidence-only project story. The displayed excerpts are OCR or
// user-edited source text, not a generated reconstruction of events.
struct StoryDraft: Sendable {
    struct Entry: Identifiable, Sendable {
        let capture: Capture
        let number: Int
        let excerpt: String
        let truncated: Bool
        var id: String { capture.id }
    }
    let title: String
    let entries: [Entry]
    let total: Int
    var omitted: Int { total - entries.count }
    var known: [Entry] { entries.filter { $0.capture.photoCreatedAt != nil } }
    var unknown: [Entry] { entries.filter { $0.capture.photoCreatedAt == nil } }
    var tasks: [Entry] {
        entries.filter { $0.capture.reviewedAt != nil && $0.capture.hasTask }
    }
    static let limit = 40

    static func build(title: String, captures: [Capture]) -> StoryDraft {
        var seen = Set<String>()
        let unique = captures.filter { !$0.isArchived && seen.insert($0.id).inserted }
        let known = unique.filter { $0.photoCreatedAt != nil }.sorted {
            $0.sourceDate == $1.sourceDate ? $0.id < $1.id : $0.sourceDate < $1.sourceDate
        }
        let unknown = unique.filter { $0.photoCreatedAt == nil }.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
        let ordered = known + unknown
        // Preserve both ends of a long collection; do not imply completeness.
        let selected = ordered.count > limit
            ? Array(ordered.prefix(limit / 2)) + Array(ordered.suffix(limit / 2))
            : ordered
        let entries = selected.enumerated().map { index, capture -> Entry in
            let text = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Entry(capture: capture, number: index + 1, excerpt: String(text.prefix(1100)),
                         truncated: text.count > 1100)
        }
        return StoryDraft(title: title, entries: entries, total: unique.count)
    }
    var introduction: String {
        var text = "התיעוד כולל \(entries.count) מתוך \(total) מקורות שנשמרו בנושא זה."
        if let first = known.first?.capture.photoCreatedAt, let last = known.last?.capture.photoCreatedAt {
            text += " תאריכי הצילום הידועים במקורות המוצגים: \(Self.date(first)) עד \(Self.date(last))."
        }
        if !unknown.isEmpty { text += " ל־\(unknown.count) מקורות מוצגים אין תאריך צילום ידוע." }
        if omitted > 0 { text += " \(omitted) מקורות נוספים אינם נכללים בכתבה זו; נבחרו תחילת וסוף סדר המקורות." }
        return text
    }
    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    // Self-contained HTML: no script, external requests, remote fonts or
    // user text inserted as raw HTML. The supplied bytes are JPEG previews.
    func html(images: [String: Data] = [:], includeTasks: Bool = true) -> String {
        let esc = Self.escape
        var result = """
        <!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <title>\(esc(title)) — ScreenMind</title>
        <style>
        body{margin:0;background:#f4f6fa;color:#172138;font-family:system-ui,-apple-system,sans-serif;line-height:1.65}
        main{max-width:780px;margin:auto;padding:24px}header,article,section{background:white;border:1px solid #e3e7ef;border-radius:18px;padding:24px;margin:0 0 18px}
        h1{font-size:clamp(26px,6vw,42px);line-height:1.25;margin:12px 0}h2{font-size:22px}h3{font-size:18px}small,.meta{color:#536176}
        blockquote{margin:12px 0;padding:12px;border-inline-start:3px solid #7669d8;background:#f7f8fc;white-space:pre-wrap;overflow-wrap:anywhere}
        img{max-width:100%;max-height:460px;object-fit:contain;border-radius:10px;display:block;margin:12px auto}
        code{direction:ltr;unicode-bidi:isolate;overflow-wrap:anywhere;font-size:11px}a{color:#4d45a5}
        @media print{body{background:white}article{break-inside:avoid}}
        </style></head><body><main>
        <header><small>SCREENMIND STORIES · טיוטה מבוססת מקורות</small><h1>\(esc(title))</h1>
        <p>\(esc(introduction))</p><small>לא סיכום גנרטיבי. קטעי המקור הם טקסט מזוהה או ערוך ועלולים לכלול שגיאות.</small></header>
        """
        func section(_ title: String, entries: [Entry]) -> String {
            guard !entries.isEmpty else { return "" }
            var html = "<h2>\(esc(title))</h2>"
            for entry in entries {
                let capture = entry.capture
                let dateLabel = capture.photoCreatedAt.map { "צילום: " + Self.date($0) }
                    ?? ("תאריך צילום לא ידוע · ייבוא: " + Self.date(capture.createdAt))
                html += "<article id=\"source-\(entry.number)\"><small>מקור \(entry.number) · \(esc(dateLabel))</small><h3 dir=\"auto\">\(esc(capture.displayTitle))</h3>"
                if let image = images[entry.id], !image.isEmpty, image.count <= 350_000 {
                    html += "<img alt=\"תצוגה מוקטנת של מקור \(entry.number)\" src=\"data:image/jpeg;base64,\(image.base64EncodedString())\">"
                }
                html += "<blockquote dir=\"auto\">\(esc(entry.excerpt.isEmpty ? "לא זוהה טקסט. יש לבדוק את הצילום." : entry.excerpt))</blockquote>"
                if entry.truncated { html += "<small>קטע מקוצר; הטקסט המלא נמצא במקור.</small>" }
                html += "<p class=\"meta\">קובץ: <span dir=\"auto\">\(esc(capture.originalName))</span><br>מזהה: <code>\(esc(capture.id))</code></p></article>"
            }
            return html
        }
        result += section("התפתחות התיעוד לפי תאריכי צילום", entries: known)
        result += section("מקורות ללא תאריך צילום", entries: unknown)
        if includeTasks {
            result += "<section><h2>צעדים שסימנת בעצמך</h2>"
            if tasks.isEmpty { result += "<p>אין משימות מאושרות במקורות המוצגים.</p>" }
            for entry in tasks {
                let c = entry.capture
                let status = c.taskCompletedAt == nil ? "פתוחה" : "בוצעה"
                let due = c.taskDueAt.map { " · יעד: " + Self.date($0) } ?? ""
                result += "<p><strong dir=\"auto\">\(esc(c.taskTitle ?? ""))</strong> · \(esc(status + due)) · <a href=\"#source-\(entry.number)\">מקור \(entry.number)</a></p>"
            }
            result += "</section>"
        }
        result += "<section><small>הכתבה היא עותק לקריאה, לא גיבוי של המקורות. תמונות מצורפות הן תצוגות מוקטנות. לאחר ייצוא, הקובץ נמצא בשליטתך ועשוי להכיל מידע פרטי.</small></section></main></body></html>"
        return result
    }
}

struct StoryHTMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }
    var html: String
    init(html: String) { self.html = html }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let html = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.html = html
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(html.utf8))
    }
}

struct ProjectStoryView: View {
    @EnvironmentObject private var library: NativeLibrary
    let identity: ProjectIdentity?
    private let selectedIDs: Set<String>?
    private let articleTitle: String
    let open: (Capture) -> Void
    @State private var draft: StoryDraft?
    @State private var images = true
    @State private var tasks = true
    @State private var exporting = false
    @State private var document: StoryHTMLDocument?
    @State private var message: String?
    @State private var revision = 0

    init(identity: ProjectIdentity, open: @escaping (Capture) -> Void) {
        self.identity = identity
        self.selectedIDs = nil
        self.articleTitle = identity.title
        self.open = open
    }

    init(title: String, selectedIDs: Set<String>, open: @escaping (Capture) -> Void) {
        self.identity = nil
        self.selectedIDs = selectedIDs
        self.articleTitle = title
        self.open = open
        _images = State(initialValue: false)
        _tasks = State(initialValue: false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ScreenMind Stories").font(.caption.bold()).foregroundStyle(NativeTheme.accent)
                Text(articleTitle).font(.largeTitle.bold()).textSelection(.enabled)
                if let draft {
                    Text(draft.introduction).font(.subheadline).foregroundStyle(.secondary)
                    Label("טיוטה מקומית מתוך המקורות, ללא כתיבה גנרטיבית.", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("כלול תמונות מוקטנות", isOn: $images)
                    Toggle("כלול משימות שאישרתי", isOn: $tasks)
                    Button { prepareExport(draft) } label: {
                        Label("ייצא כתבה מעוצבת ל־HTML", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(draft.entries.isEmpty)
                    Text("הקובץ עצמאי וניתן לפתיחה בדפדפן ללא אינטרנט. ייצוא כולל טקסט מזוהה, ועלול לחשוף מידע פרטי. הוא אינו גיבוי.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    if !draft.known.isEmpty {
                        Text("התפתחות התיעוד").font(.title2.bold())
                        ForEach(draft.known) { entry in sourceCard(entry) }
                    }
                    if !draft.unknown.isEmpty {
                        Text("תאריך צילום לא ידוע").font(.title2.bold())
                        ForEach(draft.unknown) { entry in sourceCard(entry) }
                    }
                    if tasks {
                        Text("צעדים שסימנת בעצמך").font(.title2.bold())
                        if draft.tasks.isEmpty {
                            Text("אין משימות מאושרות במקורות אלה.").foregroundStyle(.secondary)
                        }
                        ForEach(draft.tasks) { entry in
                            Button {
                                if let current = library.capture(entry.id) { open(current) }
                            } label: {
                                Label(entry.capture.taskTitle ?? "", systemImage: entry.capture.taskCompletedAt == nil ? "circle" : "checkmark.circle.fill")
                            }.buttonStyle(.plain)
                        }
                    }
                } else { ProgressView("מכין את טיוטת המקורות…") }
            }.padding(18)
        }
        .background(NativeTheme.canvas)
        .navigationTitle(identity == nil ? "כתבה מהמקורות" : "סיפור הפרויקט")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: library.captures) { _, _ in revision += 1 }
        .task(id: revision) {
            let snapshot = library.active
            let key = identity?.key
            let ids = selectedIDs
            let title = articleTitle
            draft = nil
            let worker = Task.detached(priority: .utility) {
                let selected: [Capture]
                if let ids {
                    selected = ArticleSelection.sources(from: snapshot, ids: ids)
                } else if let key {
                    selected = snapshot.filter { capture in
                        let links = ProjectIdentity.detect(in: capture.title + "\n" + capture.text)
                        return links.count == 1 && links.first?.key == key
                    }
                } else { selected = [] }
                return StoryDraft.build(title: title, captures: selected)
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            draft = result
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .html,
                      defaultFilename: "ScreenMind-Story") { result in
            switch result {
            case .success: message = "הכתבה יוצאה. פתח את הקובץ כדי לבדוק את התוצאה."
            case .failure(let error): message = "הייצוא לא הושלם: " + error.localizedDescription
            }
            document = nil
        }
    }
    private func sourceCard(_ entry: StoryDraft.Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("מקור \(entry.number)").font(.caption.bold()).foregroundStyle(NativeTheme.accent)
            if let date = entry.capture.photoCreatedAt {
                Text(StoryDraft.date(date)).font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.capture.displayTitle).font(.headline)
            if images, let image = library.thumbnail(entry.capture) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(entry.excerpt.isEmpty ? "לא זוהה טקסט." : entry.excerpt)
                .font(.subheadline).textSelection(.enabled)
            if entry.truncated {
                Text("קטע מקוצר").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                if let current = library.capture(entry.id) { open(current) }
            } label: { Label("פתח את המקור", systemImage: "arrow.up.right.square") }
                .font(.subheadline)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private func prepareExport(_ draft: StoryDraft) {
        var previews: [String: Data] = [:]
        if images {
            for entry in draft.entries {
                if let image = library.thumbnail(entry.capture),
                   let jpeg = image.jpegData(compressionQuality: 0.65), jpeg.count <= 350_000 {
                    previews[entry.id] = jpeg
                }
            }
        }
        document = StoryHTMLDocument(html: draft.html(images: previews, includeTasks: tasks))
        exporting = true
    }
}


// Local article selection: source IDs, not new copies of personal data.
enum ArticleSelection {
    static let limit = StoryDraft.limit
    static let pageSize = 60

    static func sources(from captures: [Capture], ids: Set<String>) -> [Capture] {
        var seen = Set<String>()
        let matches = captures.filter { !$0.isArchived && ids.contains($0.id) && seen.insert($0.id).inserted }
        return Array(matches.sorted {
            $0.sourceDate == $1.sourceDate ? $0.id < $1.id : $0.sourceDate > $1.sourceDate
        }.prefix(limit))
    }

    static func matches(_ capture: Capture, query: String) -> Bool {
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if query.isEmpty { return true }
        let haystack = capture.displayTitle + "\n" + capture.effectiveCollection + "\n" + String(capture.text.prefix(4000))
        return haystack.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func title(_ raw: String) -> String {
        let cleaned = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return cleaned.isEmpty ? "כתבה מהמקורות" : cleaned
    }
}

struct ArticleStudioView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var selected = Set<String>()
    @State private var query = ""
    @State private var title = ""
    @State private var onlySelected = false
    @State private var shown = ArticleSelection.pageSize

    private var validIDs: Set<String> {
        Set(ArticleSelection.sources(from: library.active, ids: selected).map(\.id))
    }

    var body: some View {
        let valid = validIDs
        let filtered = library.active.filter {
            (!onlySelected || valid.contains($0.id)) && ArticleSelection.matches($0, query: query)
        }
        List {
            Section {
                Text("מרעיון לכתבה").font(.title2.bold())
                Text("בחר עד \(ArticleSelection.limit) מקורות. ניצור מסמך מקומי עם קטעי טקסט, תאריכים ומקורות — לא כתיבה גנרטיבית.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("כותרת הכתבה (רשות)", text: $title)
                    .onChange(of: title) { _, value in
                        if value.count > 120 { title = String(value.prefix(120)) }
                    }
                Text("\(valid.count) מקורות נבחרו").font(.headline).foregroundStyle(NativeTheme.accent)
                    .accessibilityIdentifier("articleSelectedCount")
                Toggle("הצג נבחרים בלבד", isOn: $onlySelected)
                if !valid.isEmpty {
                    NavigationLink {
                        ProjectStoryView(title: ArticleSelection.title(title), selectedIDs: valid, open: open)
                    } label: {
                        Label("צור טיוטה מקומית", systemImage: "doc.text")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent)
                    if valid.count <= 8 {
                        NavigationLink {
                            GroundedArticleView(title: ArticleSelection.title(title),
                                                captures: ArticleSelection.sources(from: library.active, ids: valid),
                                                open: open)
                        } label: {
                            Label("כתיבת AI עם מקורות (ניסיוני)", systemImage: "sparkles")
                        }
                    } else {
                        Text("כתיבת AI מוגבלת ל־8 מקורות. הטיוטה המקומית מאפשרת עד 40.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("נקה בחירה", role: .destructive) { selected.removeAll() }
                }
            }
            Section("בחר מקורות") {
                if filtered.isEmpty {
                    Text("לא נמצאו מקורות מתאימים.").foregroundStyle(.secondary)
                }
                ForEach(Array(filtered.prefix(shown))) { capture in
                    Button {
                        if selected.contains(capture.id) { selected.remove(capture.id) }
                        else if valid.count < ArticleSelection.limit { selected.insert(capture.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: valid.contains(capture.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(NativeTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(capture.displayTitle).font(.headline).foregroundStyle(.primary)
                                Text(capture.effectiveCollection).font(.caption).foregroundStyle(.secondary)
                                Text(capture.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                        .disabled(valid.count >= ArticleSelection.limit && !valid.contains(capture.id))
                        .accessibilityValue(valid.contains(capture.id) ? "נבחר" : "לא נבחר")
                }
                if filtered.count > shown {
                    Button("הצג מקורות נוספים") { shown += ArticleSelection.pageSize }
                }
            }
            Section {
                Text("הבחירה אינה משנה את הצילומים, ואינה שולחת דבר לענן. ייצוא HTML עשוי לכלול מידע אישי. תמונות ומשימות אינן כלולות כברירת מחדל.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("יצירת כתבה")
        .searchable(text: $query, prompt: "חפש כותרת, נושא או טקסט")
        .onChange(of: query) { _, _ in shown = ArticleSelection.pageSize }
        .onChange(of: onlySelected) { _, _ in shown = ArticleSelection.pageSize }
        .onChange(of: library.captures) { _, _ in selected = validIDs }
    }
}


// Explicit, text-only article pilot. Nothing is sent or persisted automatically.
struct GroundedArticleInput: Codable, Equatable, Sendable {
    let id: String
    var title: String
    var text: String
}
struct GroundedArticleResult: Codable, Sendable {
    struct Evidence: Codable, Sendable {
        let id: String
        let quote: String
    }
    struct Section: Codable, Sendable {
        let heading: String
        let paragraph: String
        let evidence: [Evidence]
    }
    let title: String
    let sections: [Section]

    static func bounded(_ text: String, min: Int, max: Int) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count >= min &&
        text.utf16.count <= max
    }
    static func clip(_ text: String, limit: Int) -> String {
        var result = ""
        var length = 0
        for character in text {
            let n = String(character).utf16.count
            if length + n > limit { break }
            result.append(character); length += n
        }
        return result
    }
    func valid(for sources: [GroundedArticleInput]) -> Bool {
        guard Self.bounded(title, min: 1, max: 180),
              (1...6).contains(sections.count),
              Set(sources.map(\.id)).count == sources.count else { return false }
        let texts = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, Data($0.text.utf8)) })
        return sections.allSatisfy { section in
            guard Self.bounded(section.heading, min: 1, max: 160),
                  Self.bounded(section.paragraph, min: 1, max: 1200),
                  (1...3).contains(section.evidence.count),
                  Set(section.evidence.map(\.id)).count == section.evidence.count else { return false }
            return section.evidence.allSatisfy { evidence in
                Self.bounded(evidence.quote, min: 12, max: 240) &&
                texts[evidence.id]?.range(of: Data(evidence.quote.utf8)) != nil
            }
        }
    }
}

private final class ArticleNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum GroundedArticleClient {
    private struct Request: Encodable {
        let language: String
        let title: String
        let items: [GroundedArticleInput]
    }
    static let languages = ["he", "en", "ru", "es", "fr", "de", "ar", "it", "pt", "ja", "zh", "hi"]
    static func endpoint(_ raw: String) -> URL? {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path == "/article" else { return nil }
        return c.url
    }
    static func valid(title: String, language: String, items: [GroundedArticleInput]) -> Bool {
        guard languages.contains(language), GroundedArticleResult.bounded(title, min: 1, max: 120),
              (1...8).contains(items.count), Set(items.map(\.id)).count == items.count else { return false }
        return items.allSatisfy {
            (0..<8).map { "s\($0)" }.contains($0.id) &&
            GroundedArticleResult.bounded($0.title, min: 1, max: 240) &&
            GroundedArticleResult.bounded($0.text, min: 12, max: 3500)
        }
    }
    static func generate(url: URL, token: String, title: String, language: String,
                         items: [GroundedArticleInput]) async throws -> GroundedArticleResult {
        guard endpoint(url.absoluteString) == url, token.utf16.count >= 32,
              token.rangeOfCharacter(from: .controlCharacters) == nil,
              valid(title: title, language: language, items: items) else {
            throw NativeError.message("פרטי החיבור או המקורות אינם תקינים.")
        }
        var request = URLRequest(url: url, timeoutInterval: 70)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Request(language: language, title: title, items: items))
        guard (request.httpBody?.count ?? Int.max) <= 128 * 1024 else {
            throw NativeError.message("המידע גדול מדי.")
        }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: ArticleNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 128 * 1024 else { throw NativeError.message("השרת לא החזיר כתבה תקינה.") }
        let article = try JSONDecoder().decode(GroundedArticleResult.self, from: data)
        guard article.valid(for: items) else {
            throw NativeError.message("הציטוטים אינם תואמים למקורות שנשלחו.")
        }
        return article
    }
}

private struct MemoryNotebookEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let text: String
    let sourceIDs: [String]
}

private struct MemoryNotebookGraph: View {
    let notes: [MemoryNotebookEntry]
    let topic: (MemoryNotebookEntry) -> String
    let connected: (MemoryNotebookEntry, MemoryNotebookEntry) -> Bool
    @State private var selectedID: UUID?
    @State private var selectedTopic: String?
    private var topics: [String] { Array(Set(notes.map(topic))).sorted() }
    private var visible: [MemoryNotebookEntry] {
        Array(notes.filter { selectedTopic == nil || topic($0) == selectedTopic }.prefix(12))
    }
    private func color(_ note: MemoryNotebookEntry) -> Color {
        let palette: [Color] = [.purple, .blue, .teal, .orange, .pink, .indigo, .green]
        let index = topics.firstIndex(of: topic(note)) ?? 0
        return palette[index % palette.count]
    }
    @State private var yaw = 0.0
    @State private var pitch = 0.0
    @State private var zoom = 0.85
    private func projection(_ index: Int, size: CGSize) -> (point: CGPoint, depth: Double) {
        let n = Double(max(visible.count, 1))
        let y = 1 - 2 * (Double(index) + 0.5) / n
        let ring = sqrt(max(0, 1 - y * y))
        let angle = Double(index) * Double.pi * (3 - sqrt(5.0)) + yaw
        let x = ring * cos(angle)
        let z = ring * sin(angle)
        let vertical = y * cos(pitch) - z * sin(pitch)
        let depth = y * sin(pitch) + z * cos(pitch)
        let perspective = 3 / (3 - depth)
        let radius = max(0, min(size.width, size.height) / 2 - 36) * CGFloat(zoom)
        return (CGPoint(x: size.width / 2 + CGFloat(x * perspective) * radius,
                        y: size.height / 2 + CGFloat(vertical * perspective) * radius), depth)
    }
    private func point(_ index: Int, size: CGSize) -> CGPoint {
        projection(index, size: size).point
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("מוצגות עד 12 הרשומות האחרונות. קו מציין מקור משותף זמין.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("סינון לפי נושא", selection: $selectedTopic) {
                Text("כל הנושאים").tag(nil as String?)
                ForEach(topics, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
            }
            ForEach(topics, id: \.self) { name in
                if let sample = notes.first(where: { topic($0) == name }) {
                    Label(name + " · " + String(notes.filter { topic($0) == name }.count),
                          systemImage: "circle.fill").foregroundStyle(color(sample))
                        .font(.caption)
                }
            }
            GeometryReader { geometry in
                ZStack {
                    Canvas { context, size in
                        for i in visible.indices {
                            for j in visible.indices where j > i {
                                if connected(visible[i], visible[j]) {
                                    var line = Path()
                                    line.move(to: point(i, size: size))
                                    line.addLine(to: point(j, size: size))
                                    context.stroke(line, with: .color(.purple.opacity(0.5)), lineWidth: 2)
                                }
                            }
                        }
                    }.accessibilityHidden(true)
                    ForEach(visible.indices, id: \.self) { index in
                        let note = visible[index]
                        Button {
                            selectedID = note.id
                        } label: {
                            ZStack {
                                Circle().fill(color(note))
                                Text(String(index + 1)).font(.caption.bold()).foregroundStyle(.white)
                            }.frame(width: 44, height: 44)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: selectedID == note.id ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(note.title)
                        .scaleEffect(CGFloat(0.85 + 0.15 * projection(index, size: geometry.size).depth))
                        .zIndex(projection(index, size: geometry.size).depth + 2)
                        .position(point(index, size: geometry.size))
                    }
                }
            }.frame(height: 280)
            VStack(alignment: .leading) {
                Text("סיבוב אופקי").font(.caption)
                Slider(value: $yaw, in: -Double.pi...Double.pi)
                Text("הטיה אנכית").font(.caption)
                Slider(value: $pitch, in: -1.5...1.5)
                Text("מרחק תצוגה").font(.caption)
                Slider(value: $zoom, in: 0.45...1.0)
                Button("אפס תצוגה") { yaw = 0; pitch = 0; zoom = 0.85 }
                    .buttonStyle(.borderless)
            }
            if let note = visible.first(where: { $0.id == selectedID }) {
                Text(note.title).font(.headline)
                Text(topic(note)).font(.caption).foregroundStyle(.secondary)
                Text(note.text).font(.caption).textSelection(.enabled)
            }
            ForEach(visible.indices, id: \.self) { index in
                Button("\(index + 1). \(visible[index].title)") {
                    selectedID = visible[index].id
                }.buttonStyle(.borderless)
            }
        }
    }
}

struct GroundedArticleView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    private let origins: [String: Capture]
    @AppStorage("screenmind.memoryNotebook.v1") private var notebookData = Data()
    @State private var title: String
    @State private var items: [GroundedArticleInput]
    @State private var language = "he"
    @State private var address = ""
    @State private var token = ""
    @State private var approved = false
    @State private var running = false
    @State private var result: GroundedArticleResult?
    @State private var message = ""
    @State private var work: Task<Void, Never>?
    private let labels = ["עברית", "English", "Русский", "Español", "Français", "Deutsch", "العربية",
                          "Italiano", "Português", "日本語", "中文", "हिन्दी"]

    init(title: String, captures: [Capture], open: @escaping (Capture) -> Void) {
        self.open = open
        _title = State(initialValue: GroundedArticleResult.clip(title, limit: 120))
        let mapped = captures.prefix(8).enumerated().map { (index, capture) in ("s\(index)", capture) }
        origins = Dictionary(uniqueKeysWithValues: mapped)
        _items = State(initialValue: mapped.map { id, capture in
            GroundedArticleInput(id: id, title: GroundedArticleResult.clip(capture.displayTitle, limit: 240),
                                text: GroundedArticleResult.clip(capture.text, limit: 3500))
        })
    }
    private var current: Bool {
        items.allSatisfy { item in
            guard let origin = origins[item.id], let capture = library.capture(origin.id),
                  !capture.isArchived else { return false }
            return capture.text == origin.text && capture.displayTitle == origin.displayTitle
        }
    }
    private var ready: Bool {
        approved && !running && current && GroundedArticleClient.endpoint(address) != nil &&
        token.utf16.count >= 32 && GroundedArticleClient.valid(title: title, language: language, items: items)
    }
    var body: some View {
        List {
            Section {
                Text("כתבה עם ציטוטים").font(.title2.bold())
                Text("ניסוי בכתיבה גנרטיבית מ־1 עד 8 מקורות. הטקסט שנבחר יעבור לשרת פרטי ולספק AI רק לאחר אישור ושליחה. לא נשלחים תמונות או מזהי ספרייה.")
                Text("אין לשלוח סיסמאות, מידע צבאי, מסמכים אישיים או פרטי זיהוי. ייתכנו חיובים ושמירת מידע אצל הספק.")
                    .foregroundStyle(.orange).font(.caption)
            }
            Section("חיבור ושפה") {
                TextField("https://your-server.example/article", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("אסימון גישה לשרת", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("כותרת", text: $title)
                Picker("שפת הכתבה", selection: $language) {
                    ForEach(GroundedArticleClient.languages.indices, id: \.self) { index in
                        Text(labels[index]).tag(GroundedArticleClient.languages[index])
                    }
                }
            }.disabled(running)
            Section("הטקסט המדויק שישלח — אפשר לערוך ולהסיר") {
                Text("העריכה כאן אינה משנה את המקור. הטקסט ההתחלתי מוגבל ל־3,500 יחידות UTF-16 לכל מקור.")
                    .font(.caption)
                ForEach($items, id: \.id) { $item in
                    DisclosureGroup(item.title) {
                        TextField("כותרת מקור", text: $item.title)
                        TextEditor(text: $item.text).frame(minHeight: 120)
                        Text("\(item.text.utf16.count) / 3500").font(.caption)
                        Button("הסר מקור", role: .destructive) {
                            let id = item.id
                            items.removeAll { $0.id == id }
                        }
                    }
                }
                Toggle("בדקתי את הכותרות והטקסט והסרתי מידע רגיש", isOn: $approved)
                if !current { Text("מקור השתנה או הוסר. חזור למסך הבחירה והכן סבב חדש.").foregroundStyle(.orange) }
            }.disabled(running)
            Section {
                Button("שלח \(items.count) מקורות וכתוב טיוטה") { start() }
                    .disabled(!ready)
                if running {
                    ProgressView("מכין כתבה…")
                    Button("בטל המתנה") {
                        work?.cancel(); work = nil; running = false
                        approved = false
                        message = "ההמתנה בוטלה. ייתכן שהשרת כבר עיבד את הבקשה."
                    }
                }
                if !message.isEmpty { Text(message).font(.caption) }
            }
            if !notebook.isEmpty {
                Section("מפת קשרים מקומית") {
                    Text("קשרים מבוססים על צילומי מקור משותפים שעדיין זמינים. אין הסקת קשר סמנטי אוטומטית.")
                        .font(.caption).foregroundStyle(.secondary)
                    NavigationLink {
                        List {
                            Section("רשת מקורות משותפים") {
                                MemoryNotebookGraph(notes: notebook, topic: notebookTopic, connected: { first, second in
                                    !sharedSources(first, second).isEmpty
                                })
                            }
                            Section("קשרים אפשריים לפי מילים משותפות") {
                                Text("הצעות מקומיות בלבד, לא אימות של כפילות או קשר במשמעות.")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(notebook) { note in
                                    let matches = possibleMatches(for: note)
                                    if !matches.isEmpty {
                                        DisclosureGroup(note.title) {
                                            ForEach(matches, id: \.note.id) { match in
                                                VStack(alignment: .leading) {
                                                    Text(match.note.title).font(.headline)
                                                    Text("מילים משותפות: " + match.words.joined(separator: ", "))
                                                        .font(.caption)
                                                    Text(match.note.text).font(.caption).textSelection(.enabled)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            ForEach(notebook) { note in
                                let related = relatedNotes(to: note)
                                Section(note.title) {
                                    if related.isEmpty {
                                        Text("אין קשרי מקור זמינים").font(.caption)
                                    }
                                    ForEach(related) { other in
                                        DisclosureGroup {
                                            Text(other.text).textSelection(.enabled)
                                            ForEach(sharedSources(note, other), id: \.self) { id in
                                                if let capture = library.capture(id), !capture.isArchived {
                                                    Button("מקור משותף: " + capture.displayTitle) { open(capture) }
                                                }
                                            }
                                        } label: {
                                            Label(other.title, systemImage: "link")
                                        }
                                    }
                                }
                            }
                        }.navigationTitle("מפת קשרים")
                    } label: {
                        Label("גלה קשרים בין רשומות", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }
            }
            Section("מחברת הזיכרון — טיוטות AI") {
                Text("שמירה מקומית מפורשת בלבד. הטיוטות עשויות להכיל מידע אישי ולהיכלל בגיבוי המכשיר. מחיקת צילום אינה מוחקת טיוטה שנשמרה.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(notebook) { note in
                    DisclosureGroup(note.title) {
                        Text(note.date, style: .date).font(.caption)
                        Text(note.text).textSelection(.enabled)
                        ForEach(note.sourceIDs, id: \.self) { id in
                            if let capture = library.capture(id), !capture.isArchived {
                                Button("פתח מקור: " + capture.displayTitle) { open(capture) }
                            } else {
                                Text("מקור אינו זמין").font(.caption)
                            }
                        }
                        Button("מחק טיוטה", role: .destructive) {
                            if let encoded = try? JSONEncoder().encode(notebook.filter { $0.id != note.id }) {
                                notebookData = encoded
                            }
                        }
                    }
                }
            }
            if let result, current {
                Section("טיוטה לבדיקה — לא נשמרה") {
                    Text(result.title).font(.title.bold()).textSelection(.enabled)
                    Text("הציטוטים נבדקו מול הטקסט שנשלח. אין בכך אימות שהטענות נכונות או נתמכות במלואן.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(result.sections.indices, id: \.self) { index in
                        let section = result.sections[index]
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.heading).font(.headline)
                            Text(section.paragraph).textSelection(.enabled)
                            ForEach(section.evidence, id: \.id) { evidence in
                                Text(evidence.quote).font(.caption).textSelection(.enabled)
                                if let origin = origins[evidence.id], let capture = library.capture(origin.id) {
                                    Button { open(capture) } label: {
                                        Label("פתח מקור: " + capture.displayTitle, systemImage: "link")
                                    }.buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    Button("שמור במחברת הזיכרון במכשיר") {
                        guard current else { return }
                        var notes = notebook
                        let ids = Set(result.sections.flatMap { $0.evidence.map(\.id) })
                        let note = MemoryNotebookEntry(id: UUID(), date: Date(), title: result.title,
                            text: plainText(result), sourceIDs: ids.compactMap { origins[$0]?.id }.sorted())
                        notes.insert(note, at: 0)
                        guard notes.count <= 30, let encoded = try? JSONEncoder().encode(notes),
                              encoded.count <= 2_000_000 else {
                            message = "המחברת מלאה. מחק רשומה לפני שמירה נוספת."; return
                        }
                        notebookData = encoded
                        message = "הטיוטה נשמרה במחברת המקומית."
                    }
                    ShareLink(item: plainText(result)) {
                        Label("שתף טיוטת טקסט", systemImage: "square.and.arrow.up")
                    }
                    Text("שיתוף עשוי לחשוף מידע אישי. הטיוטה אינה גיבוי ואינה נשמרת אוטומטית.")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("סטודיו AI")
        .onChange(of: items) { _, _ in resetApproval() }
        .onChange(of: title) { _, _ in resetApproval() }
        .onChange(of: language) { _, _ in resetApproval() }
        .onChange(of: address) { _, _ in resetApproval() }
        .onChange(of: token) { _, _ in resetApproval() }
        .onDisappear {
            work?.cancel(); work = nil; running = false; token = ""; approved = false
        }
    }
    private struct NotebookMatch {
        let note: MemoryNotebookEntry
        let words: [String]
        let score: Double
    }
    private func notebookWords(_ note: MemoryNotebookEntry) -> Set<String> {
        let ignored: Set<String> = ["מקור", "טיוטת", "לבדיקה", "screenmind", "שלנו", "שלהם", "מתוך", "אפשר", "ניתן", "מידע", "המקור", "with", "from", "this", "that", "have", "source"]
        return Set((note.title + " " + note.text).lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !ignored.contains($0) && $0.contains(where: { $0.isLetter }) })
    }
    private func possibleMatches(for note: MemoryNotebookEntry) -> [NotebookMatch] {
        let words = notebookWords(note)
        guard !words.isEmpty else { return [] }
        return notebook.compactMap { other -> NotebookMatch? in
            guard other.id != note.id, Set(note.sourceIDs).isDisjoint(with: other.sourceIDs) else { return nil }
            let otherWords = notebookWords(other)
            let shared = words.intersection(otherWords)
            let score = Double(shared.count) / Double(max(1, words.union(otherWords).count))
            guard shared.count >= 3, score >= 0.15 else { return nil }
            return NotebookMatch(note: other, words: Array(shared.sorted().prefix(8)), score: score)
        }.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.note.id.uuidString < rhs.note.id.uuidString : lhs.score > rhs.score
        }.prefix(3).map { $0 }
    }
    private func notebookTopic(_ note: MemoryNotebookEntry) -> String {
        var counts: [String: Int] = [:]
        for id in Set(note.sourceIDs) {
            if let capture = library.capture(id), !capture.isArchived {
                counts[capture.effectiveCollection, default: 0] += 1
            }
        }
        let ranked = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        guard let first = ranked.first else { return "ללא נושא" }
        if ranked.count > 1 && ranked[1].value == first.value { return "מספר נושאים" }
        return first.key
    }
    private func sharedSources(_ first: MemoryNotebookEntry, _ second: MemoryNotebookEntry) -> [String] {
        Set(first.sourceIDs).intersection(second.sourceIDs).filter { id in
            guard let capture = library.capture(id) else { return false }
            return !capture.isArchived
        }.sorted()
    }
    private func relatedNotes(to note: MemoryNotebookEntry) -> [MemoryNotebookEntry] {
        notebook.filter { $0.id != note.id && !sharedSources(note, $0).isEmpty }
            .sorted { lhs, rhs in
                let left = sharedSources(note, lhs).count
                let right = sharedSources(note, rhs).count
                return left == right ? lhs.id.uuidString < rhs.id.uuidString : left > right
            }
    }
    private var notebook: [MemoryNotebookEntry] {
        (try? JSONDecoder().decode([MemoryNotebookEntry].self, from: notebookData)) ?? []
    }
    private func resetApproval() {
        approved = false; result = nil
    }
    private func start() {
        guard ready, let url = GroundedArticleClient.endpoint(address) else { return }
        let input = items, heading = title, lang = language, access = token
        running = true; result = nil; approved = false; message = ""
        work = Task {
            do {
                let draft = try await GroundedArticleClient.generate(url: url, token: access,
                    title: heading, language: lang, items: input)
                guard !Task.isCancelled else { return }
                if current && items == input { result = draft }
                else { message = "המקורות השתנו. הטיוטה נדחתה." }
            } catch {
                guard !Task.isCancelled else { return }
                message = "לא התקבלה כתבה תקינה. בדוק חיבור, מגבלות שימוש והפעלת השרת. דבר לא נשמר."
            }
            running = false
        }
    }
    private func plainText(_ draft: GroundedArticleResult) -> String {
        var output = "טיוטת AI לבדיקה — ScreenMind\n\n" + draft.title
        for section in draft.sections {
            output += "\n\n" + section.heading + "\n" + section.paragraph
            for evidence in section.evidence {
                let label = items.first { $0.id == evidence.id }?.title ?? evidence.id
                output += "\nמקור: " + label + "\n" + evidence.quote
            }
        }
        return output
    }
}
