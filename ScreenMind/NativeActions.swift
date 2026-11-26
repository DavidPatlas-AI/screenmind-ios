import SwiftUI

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
