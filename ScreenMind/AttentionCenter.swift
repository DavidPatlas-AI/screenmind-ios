import SwiftUI
import Foundation

struct AttentionItem: Identifiable, Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable {
        case due, opportunity, suggestedTask, timeSensitive, verify
        var title: String {
            switch self {
            case .due: return "משימות עם תאריך יעד"
            case .opportunity: return "הזדמנויות לבדיקה"
            case .suggestedTask: return "הצעות לפעולה"
            case .timeSensitive: return "מידע שעלול להשתנות"
            case .verify: return "טענות שכדאי לאמת"
            }
        }
        var symbol: String {
            switch self {
            case .due: return "calendar.badge.clock"
            case .opportunity: return "lightbulb"
            case .suggestedTask: return "checklist"
            case .timeSensitive: return "clock"
            case .verify: return "exclamationmark.shield"
            }
        }
    }
    let sourceID: String
    let kind: Kind
    let title: String
    let reason: String
    let due: Date?
    let sourceDate: Date?
    let importDate: Date
    var id: String { kind.rawValue + ":" + sourceID }
}

enum AttentionEngine {
    static let perKind = 8
    // Literal vocabulary only. A match is a reason to look, never proof that
    // an offer is current or that the user qualifies.
    private static let markers = [
        "מלגה", "מלגות", "הגשת מועמדות", "מענק", "דרושים", "הרשמה",
        "scholarship", "grant application", "job vacancy", "applications open",
        "стипендия", "грант", "вакансия", "прием заявок"
    ]

    static func build(from captures: [Capture], now: Date = Date(), calendar: Calendar = .current) -> [AttentionItem] {
        let day = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: 8, to: day) ?? day
        var groups: [AttentionItem.Kind: [AttentionItem]] = [:]
        var seen = Set<String>()
        for capture in captures where !capture.isArchived {
            if Task.isCancelled { return [] }
            guard seen.insert(capture.id).inserted else { continue }
            let rawTitle = String(capture.title.prefix(500))
            let rawText = String(capture.text.prefix(6000))
            let title = String(capture.displayTitle.prefix(140))
            let body = " " + MemoryLexicalIndex.normalize(rawTitle + " " + rawText) + " "
            func append(_ kind: AttentionItem.Kind, _ heading: String, _ reason: String, due: Date? = nil) {
                groups[kind, default: []].append(AttentionItem(sourceID: capture.id, kind: kind,
                    title: heading, reason: reason, due: due, sourceDate: capture.photoCreatedAt, importDate: capture.createdAt))
            }
            // Only explicitly approved tasks are assigned due dates.
            if capture.reviewedAt != nil, capture.hasTask, capture.taskCompletedAt == nil,
               let due = capture.taskDueAt, due < horizon {
                append(.due, String((capture.taskTitle ?? title).prefix(140)),
                       due < day ? "תאריך יעד ששמרת כבר עבר." : "תאריך יעד ששמרת מתקרב.", due: due)
                continue
            }
            if let marker = markers.first(where: { body.contains(" " + MemoryLexicalIndex.normalize($0) + " ") }) {
                append(.opportunity, title, "בטקסט מופיע הביטוי ״\(marker)״. יש לבדוק תוקף ותנאים במקור.")
                continue
            }
            if !capture.hasTask, capture.taskCompletedAt == nil,
               let suggestion = capture.currentAIAnalysis?.suggestedTask.trimmingCharacters(in: .whitespacesAndNewlines),
               !suggestion.isEmpty {
                append(.suggestedTask, String(suggestion.prefix(140)), "הצעת AI קודמת שטרם הפכה למשימה. נדרש אישור שלך.")
                continue
            }
            let hints = CaptureInsights.detect(title: rawTitle, text: rawText)
            if hints.contains(.unverifiedClaim) {
                append(.verify, title, "נמצאו סימנים לפרסום או הבטחה. אין אימות של הטענה.")
            } else if hints.contains(.timeSensitive) {
                append(.timeSensitive, title, "זוהה ביטוי הקשור לזמן, תאריך או יתרה; לא נקבע מועד יעד.")
            }
        }
        return AttentionItem.Kind.allCases.flatMap { kind in
            Array((groups[kind] ?? []).sorted {
                if kind == .due, $0.due != $1.due { return ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                // Actual photo dates first; import dates are a secondary ordering.
                if $0.sourceDate != $1.sourceDate { return ($0.sourceDate ?? .distantPast) > ($1.sourceDate ?? .distantPast) }
                if $0.importDate != $1.importDate { return $0.importDate > $1.importDate }
                return $0.sourceID < $1.sourceID
            }.prefix(perKind))
        }
    }
}

struct AttentionCenterView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var items: [AttentionItem] = []
    @State private var hidden = Set<String>()
    @State private var running = true
    @State private var revision = 0

    var body: some View {
        List {
            Section {
                Text("מה כדאי לבדוק עכשיו?").font(.title2.bold())
                Text("הצעות מקומיות מתוך המקורות שלך. אין קביעה שההזדמנות עדיין פתוחה, ואין יצירת משימות או התראות אוטומטיות.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("עד \(AttentionEngine.perKind) הצעות בכל סוג. אפשר להסתיר הצעות עד סגירת המסך.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if running {
                ProgressView("בודק את הספרייה במכשיר…")
            } else if items.filter({ !hidden.contains($0.id) }).isEmpty {
                ContentUnavailableView("אין הצעות להצגה", systemImage: "checklist",
                    description: Text("אפשר להמשיך לחפש בספרייה. ייתכן שיש מידע חשוב שלא זוהה."))
            }
            ForEach(AttentionItem.Kind.allCases, id: \.self) { kind in
                let visible = items.filter { $0.kind == kind && !hidden.contains($0.id) }
                if !visible.isEmpty {
                    Section(kind.title) {
                        ForEach(visible) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(item.title, systemImage: item.kind.symbol).font(.headline)
                                Text(item.reason).font(.subheadline).foregroundStyle(.secondary)
                                if let due = item.due {
                                    Text("יעד שהוגדר: " + StoryDraft.date(due)).font(.caption)
                                }
                                Text(item.sourceDate.map { "צילום: " + StoryDraft.date($0) } ??
                                     "תאריך צילום לא ידוע · ייבוא: " + StoryDraft.date(item.importDate))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let capture = library.capture(item.sourceID), !capture.isArchived {
                                    Button("פתח את המקור") { open(capture) }.buttonStyle(.borderless)
                                }
                                Button("לא עכשיו") { hidden.insert(item.id) }.buttonStyle(.borderless)
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
            if !hidden.isEmpty {
                Button("הצג שוב הצעות שהוסתרו") { hidden.removeAll() }
            }
        }
        .navigationTitle("מרכז תשומת הלב")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { revision += 1 } label: { Image(systemName: "arrow.clockwise") }
                .accessibilityLabel("רענן הצעות").disabled(running)
        }}
        .onChange(of: library.captures) { _, _ in revision += 1 }
        .task(id: revision) {
            running = true
            items = []
            let snapshot = library.captures
            let worker = Task.detached(priority: .utility) { AttentionEngine.build(from: snapshot) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            items = result
            running = false
        }
    }
}
