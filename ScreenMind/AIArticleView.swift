import SwiftUI
import Foundation

struct ArticleWireSource: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var title: String
    var text: String
}
struct ArticleWireRequest: Encodable, Sendable {
    let language: String
    let title: String
    let items: [ArticleWireSource]
}
struct ArticleWireDraft: Decodable, Sendable {
    struct Evidence: Decodable, Sendable {
        let id: String
        let quote: String
    }
    struct Section: Decodable, Sendable {
        let heading: String
        let paragraph: String
        let evidence: [Evidence]
    }
    let title: String
    let sections: [Section]

    func valid(for request: ArticleWireRequest) -> Bool {
        func bounded(_ s: String, _ min: Int, _ max: Int) -> Bool {
            s.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count >= min && s.utf16.count <= max
        }
        guard bounded(title, 1, 180), (1...6).contains(sections.count) else { return false }
        let sources = Dictionary(request.items.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        return sections.allSatisfy { section in
            guard bounded(section.heading, 1, 160), bounded(section.paragraph, 1, 1200),
                  (1...3).contains(section.evidence.count) else { return false }
            var seen = Set<String>()
            return section.evidence.allSatisfy { e in
                guard let source = sources[e.id], seen.insert(e.id).inserted,
                      bounded(e.quote, 12, 240) else { return false }
                return source.range(of: e.quote, options: .literal) != nil
            }
        }
    }
}
private final class ArticleNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum ArticleGateway {
    static func endpoint(_ raw: String) -> URL? {
        guard let parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path == "/article" else { return nil }
        return parts.url
    }
    static func clipped(_ raw: String, max: Int) -> String {
        var result = ""
        var count = 0
        for char in raw {
            let length = String(char).utf16.count
            if count + length > max { break }
            result.append(char)
            count += length
        }
        return result
    }
    static func valid(_ request: ArticleWireRequest) -> Bool {
        let languages = ["he","en","ru","es","fr","de","ar","it","pt","ja","zh","hi"]
        guard languages.contains(request.language), (1...8).contains(request.items.count),
              !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.title.utf16.count <= 120,
              Set(request.items.map(\.id)).count == request.items.count else { return false }
        return request.items.allSatisfy { item in
            (0..<8).contains { item.id == "s\($0)" } &&
            !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            item.title.utf16.count <= 240 &&
            item.text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count >= 12 &&
            item.text.utf16.count <= 3500
        }
    }
    static func generate(endpoint: URL, token: String, request: ArticleWireRequest) async throws -> ArticleWireDraft {
        guard valid(request), token.count >= 32 else { throw NativeError.message("פרטי הבקשה אינם תקינים.") }
        var http = URLRequest(url: endpoint, timeoutInterval: 70)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        http.httpBody = try JSONEncoder().encode(request)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForResource = 75
        let session = URLSession(configuration: config, delegate: ArticleNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(for: http)
        guard let status = response as? HTTPURLResponse, status.statusCode == 200 else {
            throw NativeError.message("השרת לא אישר את הבקשה. בדוק את ההגדרות ומגבלת השימוש.")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 128*1024 else { throw NativeError.message("תשובה גדולה מדי.") }
            data.append(byte)
        }
        let output = try JSONDecoder().decode(ArticleWireDraft.self, from: data)
        guard output.valid(for: request) else { throw NativeError.message("התשובה לא עברה בדיקת ציטוטים.") }
        return output
    }
}

struct AIArticleView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var sources: [ArticleWireSource]
    private let localIDs: [String: String]
    @State private var title: String
    @State private var language = "he"
    @State private var address = ""
    @State private var token = ""
    @State private var approved = false
    @State private var running = false
    @State private var confirming = false
    @State private var result: ArticleWireDraft?
    @State private var sentRequest: ArticleWireRequest?
    @State private var work: Task<Void, Never>?
    @State private var message = ""

    init(title: String, captures: [Capture], open: @escaping (Capture) -> Void) {
        let selected = Array(captures.filter { !$0.isArchived }.prefix(8))
        self.open = open
        self.localIDs = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ("s\($0.offset)", $0.element.id) })
        _title = State(initialValue: ArticleGateway.clipped(title, max: 120))
        _sources = State(initialValue: selected.enumerated().map {
            ArticleWireSource(id: "s\($0.offset)", title: ArticleGateway.clipped($0.element.displayTitle, max: 240),
                              text: ArticleGateway.clipped($0.element.text, max: 3500))
        })
    }

    private var request: ArticleWireRequest { ArticleWireRequest(language: language, title: title, items: sources) }
    private var ready: Bool { approved && !running && ArticleGateway.endpoint(address) != nil && token.count >= 32 && ArticleGateway.valid(request) }

    var body: some View {
        List {
            Section {
                Text("כתבה בעזרת AI").font(.title2.bold())
                Text("ניסוי אופציונלי. הכותרת והטקסטים המוצגים יישלחו לשרת ולספק AI רק באישור. אין שליחת תמונות או מזהי ספרייה. הספק עשוי לשמור מידע ולחייב לפי שימוש.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("אין לשלוח מידע צבאי, סיסמאות, פרטי זיהוי או מסמכים רגישים. השתמש תחילה בטקסטים סינתטיים.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Section("חיבור לשרת פרטי") {
                TextField("https://your-server.example/article", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("אסימון שרת, לא מפתח API", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("שפת הכתבה", selection: $language) {
                    ForEach(["he","en","ru","es","fr","de","ar","it","pt","ja","zh","hi"], id: \.self) { Text($0).tag($0) }
                }
                TextField("כותרת שתישלח", text: $title)
            }.disabled(running)
            Section("הטקסט המדויק לשליחה — ניתן לצנזר") {
                ForEach($sources) { $source in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.id).font(.caption).foregroundStyle(.secondary)
                        TextField("כותרת מקור", text: $source.title)
                        TextEditor(text: $source.text).frame(minHeight: 120)
                        Text("\(source.text.utf16.count) / 3500").font(.caption)
                        Button("הסר מקור מהבקשה", role: .destructive) {
                            let id = source.id
                            sources.removeAll { $0.id == id }
                        }
                    }
                }
                Text("העריכות כאן אינן משנות את הספרייה. טקסטים ארוכים קוצרו בתחילת ההכנה.")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(running)
            Section {
                Toggle("בדקתי וצנזרתי את כל הטקסט; אני מסכים לשליחתו לשרת ולספק", isOn: $approved)
                    .disabled(running)
                Button("שלח וצור טיוטה") { confirming = true }.disabled(!ready)
                if running {
                    ProgressView()
                    Button("בטל המתנה") { work?.cancel() }
                }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            if let result, let sentRequest {
                Section("טיוטת AI — לא מידע מאומת") {
                    Text(result.title).font(.title2.bold())
                    Text("הציטוטים נמצאו בטקסט שנשלח; אין בכך הוכחה שהמסקנות נכונות. יש לבדוק כל מקור.")
                        .font(.caption).foregroundStyle(.orange)
                    ForEach(Array(result.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.heading).font(.headline)
                            Text(section.paragraph).textSelection(.enabled)
                            ForEach(Array(section.evidence.enumerated()), id: \.offset) { _, e in
                                Text(e.quote).font(.caption).textSelection(.enabled)
                                if let item = sentRequest.items.first(where: { $0.id == e.id }) {
                                    Text(item.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Button("פתח את המקור \(e.id)") {
                                    if let id = localIDs[e.id], let capture = library.capture(id) { open(capture) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("כתבה עם AI")
        .onChange(of: sources) { _, _ in approved = false }
        .onChange(of: title) { _, _ in approved = false }
        .onChange(of: language) { _, _ in approved = false }
        .onChange(of: address) { _, _ in approved = false }
        .onChange(of: token) { _, _ in approved = false }
        .confirmationDialog("לשלוח את הטקסט המוצג לשרת החיצוני?", isPresented: $confirming, titleVisibility: .visible) {
            Button("שלח בקשה אחת") { send() }
            Button("ביטול", role: .cancel) {}
        } message: { Text("הפעולה עשויה לצרוך קרדיטים. אין ניסיון חוזר אוטומטי.") }
        .onDisappear { work?.cancel(); token = ""; approved = false }
    }

    private func send() {
        guard ready, let endpoint = ArticleGateway.endpoint(address) else { return }
        let snapshot = request
        let credential = token
        approved = false
        result = nil
        sentRequest = nil
        running = true
        message = ""
        work = Task {
            defer { running = false; work = nil }
            do {
                let draft = try await ArticleGateway.generate(endpoint: endpoint, token: credential, request: snapshot)
                guard !Task.isCancelled else { return }
                sentRequest = snapshot
                result = draft
            } catch {
                message = Task.isCancelled ? "ההמתנה בוטלה; ייתכן שהשרת כבר קיבל את הבקשה." : "לא התקבלה טיוטה תקינה. לא נשמר דבר בספרייה."
            }
        }
    }
}
