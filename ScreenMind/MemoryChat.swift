import SwiftUI
import Foundation

// Local retrieval conversation. No model, network request or database mutation.
// Excerpts are literal source text, not generated answers.
struct MemoryChatEvidence: Identifiable, Sendable {
    let id: String
    let title: String
    let excerpt: String
    let photoDate: Date?
    let importDate: Date
    let match: MemorySearchHit.Match
}
struct MemoryChatTurn: Identifiable, Sendable {
    let id = UUID()
    let question: String
    let scopeCount: Int
    let narrowed: Bool
    let evidence: [MemoryChatEvidence]
}

enum MemoryChat {
    static let maxEvidence = 6
    static let maxTurns = 20

    static func scope(_ captures: [Capture], previousIDs: Set<String>?) -> [Capture] {
        captures.filter { !$0.isArchived && (previousIDs?.contains($0.id) ?? true) }
    }

    // Prefer a short window around a matching query term. If retrieval was
    // semantic or cross-language, show a labeled source excerpt instead.
    static func excerpt(text: String, query: String) -> String {
        guard !text.isEmpty else { return "" }
        let terms = MemoryLexicalIndex.terms(String(query.prefix(500)))
            .sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        let matches = terms.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }
        if let match = matches.min(by: { $0.lowerBound < $1.lowerBound }) {
            let start = text.index(match.lowerBound, offsetBy: -100, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(start, offsetBy: 360, limitedBy: text.endIndex) ?? text.endIndex
            return String(text[start..<end])
        }
        return String(text.prefix(360))
    }

    static func makeTurn(question: String, captures: [Capture], hits: [MemorySearchHit], narrowed: Bool) -> MemoryChatTurn {
        let byID = Dictionary(captures.filter { !$0.isArchived }.map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var evidence: [MemoryChatEvidence] = []
        for hit in hits {
            guard let capture = byID[hit.id], seen.insert(hit.id).inserted else { continue }
            evidence.append(MemoryChatEvidence(id: capture.id, title: capture.displayTitle,
                excerpt: excerpt(text: capture.text, query: question),
                photoDate: capture.photoCreatedAt, importDate: capture.createdAt, match: hit.match))
            if evidence.count >= maxEvidence { break }
        }
        return MemoryChatTurn(question: question, scopeCount: byID.count, narrowed: narrowed, evidence: evidence)
    }
}

struct MemoryChatView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var question = ""
    @State private var turns: [MemoryChatTurn] = []
    @State private var narrow = false
    @State private var running = false
    @State private var work: Task<Void, Never>?
    @State private var generation = UUID()

    private var previousIDs: Set<String> { Set(turns.last?.evidence.map(\.id) ?? []) }
    private var ready: Bool {
        !running && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && question.count <= 500 && (!narrow || !previousIDs.isEmpty)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Text("שאל את הזיכרון שלך").font(.title2.bold())
                    Text("החיפוש המקומי מציג קטעים מהצילומים שנשמרו. הוא אינו כותב תשובה גנרטיבית או מאמת את תוכנם.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("החיפוש המקומי אינו שולח מידע לענן. תשובת AI היא אפשרות נפרדת, לאחר בדיקה ואישור. היסטוריית השיחה נשארת בזיכרון המסך בלבד.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(turns) { turn in
                    Section {
                        Text(turn.question).font(.headline).textSelection(.enabled)
                        Text(turn.narrowed ? "חיפוש חוזר במקורות הקודמים: \(turn.scopeCount)" :
                             "מקורות בספרייה שנבדקו לחיפוש: \(turn.scopeCount)")
                            .font(.caption).foregroundStyle(.secondary)
                        if turn.evidence.isEmpty {
                            Text("לא נמצא מקור מתאים. אין בכך הוכחה שהמידע אינו בספרייה. נסה מילות חיפוש אחרות.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("נמצאו \(turn.evidence.count) מקורות מוצגים. בדוק אותם לפני הסקת מסקנות.")
                                .font(.subheadline)
                            ForEach(turn.evidence) { evidence in
                                evidenceRow(evidence)
                            }
                            NavigationLink {
                                AIAnswerView(turn: turn, open: open)
                            } label: {
                                Label("נסח תשובה בעזרת AI (ניסיוני)", systemImage: "sparkles")
                            }
                        }
                    }.id(turn.id)
                }
                Section("שאלה חדשה") {
                    Toggle("חפש רק במקורות של התשובה האחרונה", isOn: $narrow)
                        .disabled(previousIDs.isEmpty || running)
                    TextField("למשל: איפה שמרתי מדריך לגיבוי?", text: $question, axis: .vertical)
                        .lineLimit(2...4).disabled(running)
                        .onChange(of: question) { _, value in
                            if value.count > 500 { question = String(value.prefix(500)) }
                        }
                    Button { ask() } label: {
                        Label("חפש תשובה במקורות", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).disabled(!ready)
                    if running {
                        ProgressView("מחפש במכשיר…")
                        Button("בטל חיפוש") { cancel() }
                    }
                }.id("composer")
            }
            .onChange(of: turns.count) { _, _ in proxy.scrollTo("composer", anchor: .bottom) }
        }
        .navigationTitle("שיחה עם הזיכרון")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("נקה שיחה") { cancel(); turns = []; narrow = false; question = "" }
                    .disabled(turns.isEmpty && !running)
            }
        }
        .onDisappear { cancel() }
    }

    private func evidenceRow(_ item: MemoryChatEvidence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(item.match == .semantic ? "דמיון סמנטי" : item.match == .exact ? "התאמת מילים" :
                    item.match == .related ? "התאמה קשורה" : "התאמה חלקית",
                  systemImage: "doc.text.magnifyingglass")
                .font(.caption).foregroundStyle(NativeTheme.accent)
            Text(item.title).font(.headline)
            Text(item.photoDate.map { "תאריך צילום: " + StoryDraft.date($0) } ??
                "תאריך צילום לא ידוע · ייבוא: " + StoryDraft.date(item.importDate))
                .font(.caption).foregroundStyle(.secondary)
            Text(item.excerpt.isEmpty ? "אין טקסט מזוהה; בדוק את הצילום." : item.excerpt)
                .font(.subheadline).textSelection(.enabled)
            Text("קטע מקור מזמן החיפוש; הטקסט עלול לכלול שגיאות OCR.").font(.caption).foregroundStyle(.secondary)
            if let current = library.capture(item.id), !current.isArchived {
                Button("פתח צילום מקור") { open(current) }.buttonStyle(.borderless)
            } else {
                Text("המקור כבר אינו זמין בספרייה הפעילה.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }

    private func cancel() {
        generation = UUID()
        work?.cancel()
        work = nil
        running = false
    }

    private func ask() {
        guard ready else { return }
        let input = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let narrowed = narrow
        let snapshot = MemoryChat.scope(library.active, previousIDs: narrowed ? previousIDs : nil)
        let ticket = UUID()
        generation = ticket
        running = true
        work = Task {
            let response = await MemorySearchEngine.shared.search(query: input, captures: snapshot)
            guard !Task.isCancelled, generation == ticket else { return }
            let turn = MemoryChat.makeTurn(question: input, captures: snapshot, hits: response.hits, narrowed: narrowed)
            turns.append(turn)
            if turns.count > MemoryChat.maxTurns { turns.removeFirst(turns.count - MemoryChat.maxTurns) }
            question = ""
            if turn.evidence.isEmpty { narrow = false }
            running = false
            work = nil
        }
    }
}
