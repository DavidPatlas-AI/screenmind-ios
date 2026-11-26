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
