import Foundation
import SwiftUI

// Compare visible OCR lines, never infer that a real-world event occurred.
struct MemoryEvolutionItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let olderID: String
    let newerID: String
    let olderDate: Date
    let newerDate: Date
    let earlierOnly: [String]
    let laterOnly: [String]
    let sharedCount: Int
    let limited: Bool
}
struct MemoryEvolutionReport: Sendable {
    let totalProjects: Int
    let examinedProjects: Int
    let comparableProjects: Int
    let items: [MemoryEvolutionItem]
}
enum MemoryEvolution {
    static let projectLimit = 80
    static let displayLimit = 20
    private static let textLimit = 6000
    private static let lineLimit = 80
    private static let excerptLimit = 6
    private struct Lines {
        let ordered: [(key: String, original: String)]
        let limited: Bool
    }
    private static func lines(_ raw: String) -> Lines {
        let prefix = String(raw.prefix(textLimit + 1))
        let text = String(prefix.prefix(textLimit))
        // Drop a possibly clipped last line, rather than report a fake change.
        var parts = text.components(separatedBy: .newlines)
        if prefix.count > textLimit && !text.hasSuffix("\n") { _ = parts.popLast() }
        var seen = Set<String>()
        var ordered: [(key: String, original: String)] = []
        var limited = prefix.count > textLimit
        for part in parts {
            let original = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = original.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            // Preserve digits, punctuation and case. Avoid URL-only lines.
            guard key.count >= 3, !key.hasPrefix("https://"), !key.hasPrefix("http://"),
                  !key.hasPrefix("github.com/"), !key.hasSuffix(".netlify.app"),
                  seen.insert(key).inserted else { continue }
            if ordered.count == lineLimit { limited = true; break }
            ordered.append((key, original))
        }
        return Lines(ordered: ordered, limited: limited)
    }
    static func build(from captures: [Capture], now: Date = Date()) -> MemoryEvolutionReport {
        var seen = Set<String>()
        let projects = ProjectCluster.build(from: captures.filter { !$0.isArchived && seen.insert($0.id).inserted })
        let selected = Array(projects.prefix(projectLimit))
        var comparable = 0
        var result: [MemoryEvolutionItem] = []
        for project in selected {
            if Task.isCancelled { break }
            // Import dates and identical capture timestamps are not evidence of sequence.
            let dated = project.sources.filter { c in
                c.photoCreatedAt.map { $0 <= now } ?? false
            }
            guard let newer = dated.last, let newDate = newer.photoCreatedAt,
                  let older = dated.last(where: { c in
                      c.photoCreatedAt.map { $0 < newDate } ?? false
                  }), let oldDate = older.photoCreatedAt else { continue }
            let earlier = lines(older.text), later = lines(newer.text)
            guard !earlier.ordered.isEmpty, !later.ordered.isEmpty else { continue }
            comparable += 1
            let oldKeys = Set(earlier.ordered.map { $0.key })
            let newKeys = Set(later.ordered.map { $0.key })
            let removed = earlier.ordered.filter { !newKeys.contains($0.key) }
            let added = later.ordered.filter { !oldKeys.contains($0.key) }
            // Unchanged bounded excerpts are not evidence that all content is identical.
            guard !removed.isEmpty || !added.isEmpty else { continue }
            result.append(.init(id: project.id, title: project.title, olderID: older.id, newerID: newer.id,
                olderDate: oldDate, newerDate: newDate,
                earlierOnly: removed.prefix(excerptLimit).map { String($0.original.prefix(240)) },
                laterOnly: added.prefix(excerptLimit).map { String($0.original.prefix(240)) },
                sharedCount: oldKeys.intersection(newKeys).count,
                limited: earlier.limited || later.limited || removed.count > excerptLimit || added.count > excerptLimit ||
                    removed.prefix(excerptLimit).contains { $0.original.count > 240 } ||
                    added.prefix(excerptLimit).contains { $0.original.count > 240 }))
        }
        let ordered = result.sorted {
            $0.newerDate == $1.newerDate ? $0.id < $1.id : $0.newerDate > $1.newerDate
        }
        return .init(totalProjects: projects.count, examinedProjects: selected.count,
                     comparableProjects: comparable, items: Array(ordered.prefix(displayLimit)))
    }
}

struct MemoryEvolutionView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var report: MemoryEvolutionReport?
    @State private var revision = 0
    var body: some View {
        List {
            Section {
                Text("מה השתנה בתיעוד?").font(.title2.bold())
                Text("השוואת שני צילומים אחרונים מתאריכים שונים עם אותה כתובת פרויקט. השורות הן מהטקסט המזוהה או המתוקן, לא הוכחה שמשהו השתנה במציאות.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("עד 80 פרויקטים, עד 6,000 תווים ו־80 שורות מכל צילום. מקורות ללא תאריך צילום אינם מושווים. אין שינוי בספרייה או שליחה לענן.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let report {
                Section {
                    Text("נבדקו \(report.examinedProjects) מתוך \(report.totalProjects) פרויקטים · \(report.comparableProjects) ניתנים להשוואה · עד 20 הצעות")
                        .font(.caption).foregroundStyle(.secondary)
                    if report.items.isEmpty {
                        Text("לא נמצאו הבדלי שורות בחלק שנבדק. ייתכן שיש מידע שלא זוהה.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(report.items) { item in
                    Section {
                        Text(item.title).font(.headline)
                        Text("\(StoryDraft.date(item.olderDate)) → \(StoryDraft.date(item.newerDate))")
                            .font(.caption).foregroundStyle(.secondary)
                        if !item.earlierOnly.isEmpty {
                            Text("שורות שנמצאו רק בקטע המוקדם").font(.subheadline.bold())
                            ForEach(Array(item.earlierOnly.enumerated()), id: \.offset) { entry in
                                Text(entry.element).font(.subheadline)
                            }
                        }
                        if !item.laterOnly.isEmpty {
                            Text("שורות שנמצאו רק בקטע המאוחר").font(.subheadline.bold())
                            ForEach(Array(item.laterOnly.enumerated()), id: \.offset) { entry in
                                Text(entry.element).font(.subheadline)
                            }
                        }
                        Text("\(item.sharedCount) שורות תואמות בקטעים שנבדקו").font(.caption).foregroundStyle(.secondary)
                        if item.limited { Text("חלק מהטקסט או מההבדלים לא מוצג.").font(.caption).foregroundStyle(.secondary) }
                        source(item.olderID, title: "פתח צילום מוקדם")
                        source(item.newerID, title: "פתח צילום מאוחר")
                    }
                }
            } else { ProgressView("משווה מקורות במכשיר…") }
        }
        .navigationTitle("התפתחות הידע")
        .onChange(of: library.captures) { _, _ in revision += 1 }
        .task(id: revision) {
            report = nil
            let snapshot = library.captures
            let worker = Task.detached(priority: .utility) { MemoryEvolution.build(from: snapshot) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            report = result
        }
    }
    @ViewBuilder private func source(_ id: String, title: String) -> some View {
        if let capture = library.capture(id), !capture.isArchived {
            Button { open(capture) } label: { Label(title + ": " + capture.displayTitle, systemImage: "doc.text").lineLimit(2) }
                .buttonStyle(.borderless)
        } else {
            Text("המקור אינו זמין עוד.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
