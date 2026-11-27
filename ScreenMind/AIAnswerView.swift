import SwiftUI
import Foundation

struct AnswerRequest: Encodable, Sendable {
    let language: String
    let question: String
    let items: [ArticleWireSource]
}
struct AnswerDraft: Decodable, Sendable {
    let status: String
    let answer: String
    let evidence: [ArticleWireDraft.Evidence]

    func valid(for request: AnswerRequest) -> Bool {
        if status == "insufficient" { return answer.isEmpty && evidence.isEmpty }
        guard ["answered", "conflicting"].contains(status),
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              answer.utf16.count <= 1800,
              ((status == "conflicting" ? 2 : 1)...4).contains(evidence.count) else { return false }
        let sources = Dictionary(request.items.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return evidence.allSatisfy { e in
            guard let source = sources[e.id], seen.insert(e.id).inserted,
                  e.quote.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count >= 12,
                  e.quote.utf16.count <= 240 else { return false }
            return source.range(of: e.quote, options: .literal) != nil
        }
    }
}
private final class AnswerNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum AnswerGateway {
    static func endpoint(_ raw: String) -> URL? {
        guard let parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path == "/answer" else { return nil }
        return parts.url
    }
    static func valid(_ request: AnswerRequest) -> Bool {
        !request.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        request.question.utf16.count <= 500 &&
        ArticleGateway.valid(ArticleWireRequest(language: request.language, title: "question", items: request.items))
    }
    static func answer(endpoint: URL, token: String, request: AnswerRequest) async throws -> AnswerDraft {
        guard valid(request), token.count >= 32, Self.endpoint(endpoint.absoluteString) != nil else {
            throw NativeError.message("פרטי הבקשה אינם תקינים.")
        }
        var http = URLRequest(url: endpoint, timeoutInterval: 70)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        http.httpBody = try JSONEncoder().encode(request)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForResource = 75
        let session = URLSession(configuration: config, delegate: AnswerNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: http)
        guard let status = response as? HTTPURLResponse, status.statusCode == 200 else {
            throw NativeError.message("השרת לא אישר את הבקשה.")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 128*1024 else { throw NativeError.message("תשובה גדולה מדי.") }
            data.append(byte)
        }
        let result = try JSONDecoder().decode(AnswerDraft.self, from: data)
        guard result.valid(for: request) else { throw NativeError.message("התשובה לא עברה בדיקת מקורות.") }
        return result
    }
}

struct AIAnswerView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    private let localIDs: [String: String]
    @State private var question: String
    @State private var sources: [ArticleWireSource]
    @State private var language = "he"
    @State private var address = ""
    @State private var token = ""
    @State private var approved = false
    @State private var confirming = false
    @State private var running = false
    @State private var result: AnswerDraft?
    @State private var sent: AnswerRequest?
    @State private var work: Task<Void, Never>?
    @State private var message = ""

    init(turn: MemoryChatTurn, open: @escaping (Capture) -> Void) {
        self.open = open
        let selected = Array(turn.evidence.prefix(6))
        localIDs = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ("s\($0.offset)", $0.element.id) })
        _question = State(initialValue: ArticleGateway.clipped(turn.question, max: 500))
        _sources = State(initialValue: selected.enumerated().map {
            ArticleWireSource(id: "s\($0.offset)", title: ArticleGateway.clipped($0.element.title, max: 240),
                              text: ArticleGateway.clipped($0.element.excerpt, max: 3500))
        })
    }

    private var request: AnswerRequest { AnswerRequest(language: language, question: question, items: sources) }
    private var available: Bool {
        sources.allSatisfy { source in
            guard let id = localIDs[source.id], let capture = library.capture(id) else { return false }
            return !capture.isArchived
        }
    }
    private var ready: Bool {
        approved && !running && available && AnswerGateway.endpoint(address) != nil && token.count >= 32 && AnswerGateway.valid(request)
    }
    var body: some View {
        List {
            Section {
                Text("תשובה בעזרת AI").font(.title2.bold())
                Text("ניסוי אופציונלי: יישלחו רק השאלה וקטעי הטקסט שמופיעים כאן, אחרי אישור. לא יישלחו תמונות, מזהי ספרייה או היסטוריית השיחה. השרת והספק עשויים לשמור מידע ולחייב לפי שימוש.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("אין לשלוח מידע צבאי, סיסמאות, פרטי זיהוי או מסמכים רגישים. בדוק תחילה עם טקסט סינתטי.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Section("חיבור ושאלה") {
                TextField("https://your-server.example/answer", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("אסימון גישה לשרת", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("שפת תשובה", selection: $language) {
                    ForEach(["he","en","ru","es","fr","de","ar","it","pt","ja","zh","hi"], id: \.self) { Text($0).tag($0) }
                }
                TextField("השאלה שתישלח", text: $question, axis: .vertical)
            }.disabled(running)
            Section("קטעי מקור לשליחה — ניתן לצנזר") {
                ForEach($sources) { $source in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.id).font(.caption).foregroundStyle(.secondary)
                        TextField("כותרת", text: $source.title)
                        TextEditor(text: $source.text).frame(minHeight: 100)
                        Button("הסר קטע מהבקשה", role: .destructive) {
                            let id = source.id
                            sources.removeAll { $0.id == id }
                        }
                    }
                }
                Text("העריכות אינן משנות את הספרייה. הציטוטים בתשובה ייבדקו מול הקטעים הערוכים שנשלחו, לא מול התמונה.")
                    .font(.caption).foregroundStyle(.secondary)
                if !available { Text("אחד המקורות אינו זמין עוד; הסר אותו או חזור לחיפוש.").foregroundStyle(.orange) }
            }.disabled(running)
            Section {
                Toggle("בדקתי וצנזרתי את כל הטקסט ואני מאשר שליחה", isOn: $approved).disabled(running)
                Button("שלח שאלה אחת") { confirming = true }.disabled(!ready)
                if running {
                    ProgressView("ממתין לתשובה…")
                    Button("בטל המתנה") { work?.cancel() }
                }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            if let result, let sent {
                Section("תוצאת AI — לא מידע מאומת") {
                    Text(sent.question).font(.headline)
                    if result.status == "insufficient" {
                        Label("אין מספיק מידע בקטעים שנשלחו", systemImage: "questionmark.circle")
                    } else {
                        if result.status == "conflicting" {
                            Label("המודל זיהה מידע סותר", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                        Text(result.answer).textSelection(.enabled)
                        Text("נבדקה התאמת הציטוטים לקטעים שנשלחו. המסקנות עדיין דורשות בדיקה.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(result.evidence.enumerated()), id: \.offset) { _, evidence in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(evidence.quote).font(.subheadline).textSelection(.enabled)
                                if let id = localIDs[evidence.id], let capture = library.capture(id), !capture.isArchived {
                                    Button("פתח צילום מקור") { open(capture) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("תשובה חכמה")
        .onChange(of: sources) { _, _ in approved = false }
        .onChange(of: question) { _, _ in approved = false }
        .onChange(of: language) { _, _ in approved = false }
        .onChange(of: address) { _, _ in approved = false }
        .onChange(of: token) { _, _ in approved = false }
        .confirmationDialog("לשלוח את השאלה והקטעים המוצגים?", isPresented: $confirming, titleVisibility: .visible) {
            Button("שלח לשרת") { send() }
            Button("ביטול", role: .cancel) {}
        } message: { Text("ייתכן חיוב לפי שימוש. אין ניסיון חוזר אוטומטי.") }
        .onDisappear { work?.cancel(); token = ""; approved = false }
    }

    private func send() {
        guard ready, let endpoint = AnswerGateway.endpoint(address) else { return }
        let snapshot = request
        let credential = token
        approved = false
        running = true
        result = nil
        sent = nil
        message = ""
        work = Task {
            defer { running = false; work = nil }
            do {
                let draft = try await AnswerGateway.answer(endpoint: endpoint, token: credential, request: snapshot)
                guard !Task.isCancelled else { return }
                sent = snapshot
                result = draft
            } catch {
                message = Task.isCancelled ? "ההמתנה בוטלה; ייתכן שהשרת כבר קיבל את הבקשה." : "לא התקבלה תשובה תקינה. לא נשמר דבר בספרייה."
            }
        }
    }
}
