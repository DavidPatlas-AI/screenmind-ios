import SwiftUI
import Foundation

struct ProjectBridge: Identifiable, Equatable, Sendable {
    struct Evidence: Identifiable, Equatable, Sendable {
        let term: String
        let leftSourceID: String
        let rightSourceID: String
        var id: String { term }
    }
    let leftKey: String
    let rightKey: String
    let leftTitle: String
    let rightTitle: String
    let evidence: [Evidence]
    var id: String { leftKey + "|" + rightKey }
}
struct ProjectBridgeReport: Sendable {
    let totalProjects: Int
    let examinedProjects: Int
    let sampledSources: Int
    let bridges: [ProjectBridge]
}

enum ProjectBridgeEngine {
    static let projectLimit = 80
    static let sourceLimit = 30
    static let resultLimit = 20
    private static let generic: Set<String> = [
        "github","netlify","project","repository","app","application","code","source","main","master","readme",
        "https","http","www","com","org","net","dev","login","settings","screen","screenshot","update",
        "פרויקט","פרויקטים","אפליקציה","קוד","צילום","מסך","עדכון","מדריך","מידע","חדש","הגדרות",
        "проект","приложение","код","скриншот","обновление","настройки"
    ]

    private struct Profile {
        let key: String
        let title: String
        let terms: [String: String]
    }
    static func build(from captures: [Capture]) -> ProjectBridgeReport {
        let projects = ProjectCluster.build(from: captures.filter { !$0.isArchived })
        let selected = Array(projects.prefix(projectLimit))
        let empty = ProjectBridgeReport(totalProjects: projects.count, examinedProjects: 0, sampledSources: 0, bridges: [])
        var profiles: [Profile] = []
        var frequency: [String: Int] = [:]
        var sampled = 0
        // Project identifiers and generic vocabulary are not evidence of a
        // topical bridge. Remove visible project URLs and identifier words.
        let identityWords = Set(selected.flatMap { MemoryLexicalIndex.terms($0.title) })
        for project in selected {
            if Task.isCancelled { return empty }
            let sources = project.sources
            let sample = sources.count <= sourceLimit ? sources :
                Array(sources.prefix(sourceLimit/2)) + Array(sources.suffix(sourceLimit/2))
            var terms: [String: String] = [:]
            for capture in sample {
                if Task.isCancelled { return empty }
                sampled += 1
                let text = String((capture.title + " " + String(capture.text.prefix(2000))).prefix(2500))
                    .replacingOccurrences(of: #"(?i)(?:https?://|www\.)\S+|(?:github\.com|[a-z0-9-]+\.netlify\.app)\S*"#,
                                          with: " ", options: .regularExpression)
                for term in BrainText.tokens(title: "", text: text)
                    where term.count >= 4 && !generic.contains(term) && !identityWords.contains(term) {
                    if terms[term] == nil { terms[term] = capture.id }
                }
            }
            for term in terms.keys { frequency[term, default: 0] += 1 }
            profiles.append(Profile(key: project.id, title: project.title, terms: terms))
        }
        var results: [ProjectBridge] = []
        // Compare only explicit projects, not every screenshot pair.
        let maxFrequency = max(2, profiles.count / 3)
        for (index, left) in profiles.enumerated() {
            if Task.isCancelled { return empty }
            for right in profiles.dropFirst(index + 1) {
                let shared = left.terms.keys.filter { right.terms[$0] != nil && (frequency[$0] ?? 0) <= maxFrequency }
                    .sorted {
                        let a = frequency[$0] ?? 0, b = frequency[$1] ?? 0
                        return a == b ? $0 < $1 : a < b
                    }
                guard shared.count >= 2 else { continue }
                let evidence = shared.prefix(4).compactMap { term -> ProjectBridge.Evidence? in
                    guard let a = left.terms[term], let b = right.terms[term], a != b else { return nil }
                    return .init(term: term, leftSourceID: a, rightSourceID: b)
                }
                guard evidence.count >= 2 else { continue }
                results.append(.init(leftKey: left.key, rightKey: right.key, leftTitle: left.title,
                                     rightTitle: right.title, evidence: evidence))
            }
        }
        let ranked = results.sorted {
            $0.evidence.count == $1.evidence.count ? $0.id < $1.id : $0.evidence.count > $1.evidence.count
        }
        return ProjectBridgeReport(totalProjects: projects.count, examinedProjects: profiles.count,
                                   sampledSources: sampled, bridges: Array(ranked.prefix(resultLimit)))
    }
}

struct ProjectBridgesView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var report: ProjectBridgeReport?
    @State private var hidden = Set<String>()
    @State private var revision = 0
    var body: some View {
        List {
            Section {
                Text("גשרים בין פרויקטים").font(.title2.bold())
                Text("מונחים משותפים עשויים להצביע על רעיון שימושי בפרויקט אחר. זו הצעת קשר, לא הוכחה ששני פרויקטים קשורים.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("נבדקים פרויקטים שזוהו לפי כתובת מפורשת, עד 80 פרויקטים ועד 30 מקורות מכל פרויקט (תחילת וסוף התיעוד). לא מתבצע איחוד או שינוי בספרייה.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let report {
                Section {
                    Text("נבדקו \(report.examinedProjects) מתוך \(report.totalProjects) פרויקטים · \(report.sampledSources) מקורות")
                        .font(.caption).foregroundStyle(.secondary)
                    if report.bridges.filter({ !hidden.contains($0.id) }).isEmpty {
                        Text("לא נמצאו כרגע קשרים נוספים לפי הכללים. ייתכן שיש קשרים שלא זוהו.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(report.bridges.filter { !hidden.contains($0.id) }) { bridge in
                    Section {
                        Label(bridge.leftTitle, systemImage: "folder").font(.headline)
                        Label(bridge.rightTitle, systemImage: "folder").font(.headline)
                        Text("מילים משותפות: " + bridge.evidence.map(\.term).joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(NativeTheme.accent)
                        ForEach(bridge.evidence) { evidence in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(evidence.term).font(.subheadline.bold())
                                source(evidence.leftSourceID)
                                source(evidence.rightSourceID)
                            }.padding(.vertical, 4)
                        }
                        Button("לא עכשיו") { hidden.insert(bridge.id) }
                    }
                }
                if !hidden.isEmpty { Button("הצג שוב קשרים שהוסתרו") { hidden.removeAll() } }
            } else { ProgressView("מחפש קשרים במכשיר…") }
        }
        .navigationTitle("קשרים בין פרויקטים")
        .onChange(of: library.captures) { _, _ in revision += 1 }
        .task(id: revision) {
            report = nil
            let snapshot = library.captures
            let worker = Task.detached(priority: .utility) { ProjectBridgeEngine.build(from: snapshot) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            report = result
        }
    }

    @ViewBuilder private func source(_ id: String) -> some View {
        if let capture = library.capture(id), !capture.isArchived {
            Button { open(capture) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(capture.displayTitle, systemImage: "doc.text").lineLimit(2)
                    Text(capture.photoCreatedAt.map { "צילום: " + StoryDraft.date($0) } ??
                         "תאריך צילום לא ידוע · ייבוא: " + StoryDraft.date(capture.createdAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.borderless)
        } else { Text("המקור אינו זמין עוד.").font(.caption).foregroundStyle(.secondary) }
    }
}
