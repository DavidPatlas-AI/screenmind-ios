import SwiftUI

// Rediscovery is evidence-based and explicitly opened by the user. No
// notifications, network, invented project state or automatic task creation.
struct MemoryDiscovery: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable { case project, favorite, dueTask }
    let id: String
    let kind: Kind
    let title: String
    let reason: String
    let sourceIDs: [String]

    static func build(from captures: [Capture], now: Date = Date(), calendar: Calendar = .current) -> [MemoryDiscovery] {
        let active = captures.filter { !$0.isArchived }
        let day = calendar.startOfDay(for: now)
        guard let recent = calendar.date(byAdding: .day, value: -21, to: day),
              let old = calendar.date(byAdding: .day, value: -30, to: day),
              let revisit = calendar.date(byAdding: .day, value: -14, to: day) else { return [] }
        var results: [MemoryDiscovery] = []
        // Only a real user-approved, unfinished task with a due date.
        let due = active.filter {
            $0.reviewedAt != nil && $0.hasTask && $0.taskCompletedAt == nil &&
            ($0.taskDueAt.map { calendar.startOfDay(for: $0) <= day } ?? false)
        }.sorted {
            let a = $0.taskDueAt ?? .distantFuture, b = $1.taskDueAt ?? .distantFuture
            return a == b ? $0.id < $1.id : a < b
        }
        for capture in due.prefix(2) {
            results.append(MemoryDiscovery(id: "task:" + capture.id, kind: .dueTask,
                title: capture.taskTitle ?? capture.displayTitle,
                reason: "משימה ששמרת עם תאריך יעד שהגיע. ייתכן שכבר טיפלת בה.",
                sourceIDs: [capture.id]))
        }
        // Only explicit shared project URLs, real photo dates, and separate
        // periods. Import dates are not evidence of renewed activity.
        let projects = ProjectCluster.build(from: active).compactMap { cluster -> (ProjectCluster, Capture, Capture)? in
            guard let newest = cluster.sources.last(where: {
                ($0.photoCreatedAt.map { $0 >= recent && $0 <= now } ?? false)
            }), let earlier = cluster.sources.first(where: {
                ($0.photoCreatedAt.map { $0 <= old } ?? false)
            }), earlier.id != newest.id else { return nil }
            return (cluster, earlier, newest)
        }.sorted {
            $0.2.sourceDate == $1.2.sourceDate ? $0.0.id < $1.0.id : $0.2.sourceDate > $1.2.sourceDate
        }
        for (cluster, earlier, newest) in projects.prefix(3) {
            results.append(MemoryDiscovery(id: "project:" + cluster.id, kind: .project,
                title: cluster.title,
                reason: "אותה כתובת פרויקט נמצאה בצילום ישן ובצילום מהשבועות האחרונים. אולי כדאי להשוות ביניהם.",
                sourceIDs: [earlier.id, newest.id]))
        }
        let used = Set(results.flatMap(\.sourceIDs))
        let favorites = active.filter {
            $0.isFavorite && !used.contains($0.id) &&
            ($0.photoCreatedAt.map { $0 <= old } ?? false) &&
            ($0.viewedAt.map { $0 <= revisit } ?? true)
        }.sorted {
            $0.sourceDate == $1.sourceDate ? $0.id < $1.id : $0.sourceDate < $1.sourceDate
        }
        for capture in favorites.prefix(2) {
            results.append(MemoryDiscovery(id: "favorite:" + capture.id, kind: .favorite,
                title: capture.displayTitle,
                reason: "צילום ישן שסימנת כמועדף ולא פתחת לאחרונה.",
                sourceIDs: [capture.id]))
        }
        return Array(results.prefix(6))
    }
}

struct MemoryDiscoveryView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var suggestions: [MemoryDiscovery] = []
    @State private var hidden: Set<String> = []
    @State private var running = true
    @State private var revision = 0
    var body: some View {
        List {
            Section {
                Text("רעיונות לחזור אליהם").font(.title2.bold())
                Text("הצעות מתוך מקורות שכבר שמרת. המערכת מציגה את הסיבה והצילומים שעליהם היא מסתמכת, ואינה קובעת מה באמת חשוב לך.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("הכול במכשיר. אין שליחה, משימות אוטומטיות או התראות.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if running {
                ProgressView("מחפש קשרים במכשיר…")
            } else if suggestions.filter({ !hidden.contains($0.id) }).isEmpty {
                ContentUnavailableView("אין כרגע הצעות נוספות", systemImage: "sparkles",
                    description: Text("אין צורך למיין דבר. הצעות יופיעו כשיימצאו מקורות מתאימים."))
            }
            ForEach(suggestions.filter { !hidden.contains($0.id) }) { suggestion in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(suggestion.title, systemImage: icon(suggestion.kind))
                            .font(.headline)
                        Text(suggestion.reason).font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(suggestion.sourceIDs, id: \.self) { id in
                        if let capture = library.capture(id), !capture.isArchived {
                            Button { open(capture) } label: {
                                HStack(spacing: 12) {
                                    if let image = library.thumbnail(capture) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(width: 48, height: 58).clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(capture.displayTitle).lineLimit(2).foregroundStyle(.primary)
                                        if let date = capture.photoCreatedAt {
                                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.backward").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    Button("לא עכשיו") { hidden.insert(suggestion.id) }
                        .font(.caption)
                }
            }
            if !hidden.isEmpty {
                Button("הצג שוב את ההצעות שהסתרתי") { hidden.removeAll() }
                    .font(.subheadline)
            }
        }
        .navigationTitle("גלה מחדש")
        .onChange(of: library.captures) { _, _ in revision += 1 }
        .task(id: revision) {
            running = true
            suggestions = []
            let snapshot = library.captures
            let worker = Task.detached(priority: .utility) {
                MemoryDiscovery.build(from: snapshot)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            suggestions = result
            running = false
        }
    }
    private func icon(_ kind: MemoryDiscovery.Kind) -> String {
        switch kind {
        case .project: return "link"
        case .favorite: return "star"
        case .dueTask: return "checklist"
        }
    }
}
