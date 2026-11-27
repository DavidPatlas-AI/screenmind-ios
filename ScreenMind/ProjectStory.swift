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
