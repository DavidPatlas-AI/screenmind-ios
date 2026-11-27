import SwiftUI
import UserNotifications

enum ReminderPolicy {
    static let prefix = "screenmind.task."
    static let limit = 32
    static func eligible(_ capture: Capture) -> Bool {
        !capture.isArchived && capture.reviewedAt != nil && capture.hasTask && capture.taskCompletedAt == nil
    }
    static func identifier(_ id: String) -> String { prefix + id }
    static func validDate(_ date: Date, now: Date = Date()) -> Bool {
        let seconds = date.timeIntervalSince(now)
        return seconds >= 60 && seconds <= 365 * 86400
    }
    static func obsolete(_ identifiers: [String], captures: [Capture]) -> [String] {
        let active = Set(captures.filter(eligible).map { identifier($0.id) })
        return identifiers.filter { $0.hasPrefix(prefix) && !active.contains($0) }
    }
}

@MainActor enum LocalReminders {
    static func reconcile(library: NativeLibrary) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let obsolete = ReminderPolicy.obsolete(pending.map(\.identifier), captures: library.captures)
        if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: obsolete) }
    }

    static func schedule(id: String, date: Date, library: NativeLibrary) async throws {
        let center = UNUserNotificationCenter.current()
        guard let capture = library.capture(id), ReminderPolicy.eligible(capture), ReminderPolicy.validDate(date) else {
            throw NativeError.message("בחר משימה פתוחה ומועד עתידי תקין.")
        }
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw NativeError.message("הרשאת ההתראות לא ניתנה. ניתן לשנות אותה בהגדרות האייפון.") }
        let identifier = ReminderPolicy.identifier(id)
        let pending = await center.pendingNotificationRequests()
        guard pending.contains(where: { $0.identifier == identifier }) ||
              pending.filter({ $0.identifier.hasPrefix(ReminderPolicy.prefix) }).count < ReminderPolicy.limit else {
            throw NativeError.message("הגעת למגבלת התזכורות. בטל תזכורת קיימת תחילה.")
        }
        guard let current = library.capture(id), ReminderPolicy.eligible(current), ReminderPolicy.validDate(date) else {
            throw NativeError.message("המשימה או המועד השתנו.")
        }
        let content = UNMutableNotificationContent()
        content.title = "ScreenMind"
        content.body = "יש משימה ששמרת. פתח את האפליקציה כדי לבדוק אותה."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        guard let updated = library.capture(id), ReminderPolicy.eligible(updated) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            throw NativeError.message("המשימה אינה פתוחה עוד; התזכורת בוטלה.")
        }
    }

    static func cancel(id: String) {
        let center = UNUserNotificationCenter.current()
        let identifier = ReminderPolicy.identifier(id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

struct ReminderEditorView: View {
    @EnvironmentObject private var library: NativeLibrary
    let captureID: String
    @State private var date = Date().addingTimeInterval(3600)
    @State private var pending: Date?
    @State private var status = ""
    @State private var busy = false
    private var eligible: Bool { library.capture(captureID).map(ReminderPolicy.eligible) ?? false }

    var body: some View {
        Form {
            Section {
                Text(library.capture(captureID)?.taskTitle ?? "משימה").font(.headline)
                Text("התזכורת מקומית, חד־פעמית, ללא שם המשימה במסך הנעילה. אינה משנה את תאריך היעד של המשימה.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("מועד") {
                DatePicker("תאריך ושעה", selection: $date, displayedComponents: [.date, .hourAndMinute])
                if let pending { Text("תזכורת מתוכננת: " + pending.formatted(date: .abbreviated, time: .shortened)) }
                Button("קבע או עדכן תזכורת") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            try await LocalReminders.schedule(id: captureID, date: date, library: library)
                            await reload()
                            status = pending == nil ? "התזכורת אינה מופיעה ברשימה הממתינה." : "התזכורת נקבעה במערכת."
                        } catch { status = error.localizedDescription }
                    }
                }.disabled(busy || !eligible || !ReminderPolicy.validDate(date))
                Button("בטל תזכורת", role: .destructive) {
                    LocalReminders.cancel(id: captureID)
                    pending = nil
                    status = "בקשת הביטול נשלחה למערכת."
                }.disabled(busy)
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                Text("הצגת ההתראה תלויה בהרשאות ובהגדרות iOS. אין תזכורות חוזרות או התראות על הזדמנויות שלא אישרת.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("תזכורת מקומית")
        .task { await reload() }
    }

    private func reload() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pending = (requests.first { $0.identifier == ReminderPolicy.identifier(captureID) }?.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        if let pending { date = pending }
    }
}
