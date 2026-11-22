import SwiftUI

// Freeze the batch so refreshes, newly imported images and approvals cannot reorder it.
struct ReviewSession {
    enum Outcome: Equatable { case approved, deferred, archived }
    let ids: [String]
    private(set) var outcomes: [String: Outcome] = [:]
    init(ids: [String]) {
        var seen: Set<String> = []
        self.ids = Array(ids.filter { seen.insert($0).inserted }.prefix(20))
    }
    var currentID: String? { ids.first { outcomes[$0] == nil } }
    var resolvedCount: Int { outcomes.count }
    var approvedIDs: Set<String> { Set(outcomes.filter { $0.value == .approved }.map(\.key)) }
    var deferredCount: Int { outcomes.values.filter { $0 == .deferred }.count }
    var archivedCount: Int { outcomes.values.filter { $0 == .archived }.count }
    mutating func finish(_ id: String, as outcome: Outcome) {
        guard id == currentID else { return }
        outcomes[id] = outcome
    }
}

struct NativeReviewView: View {
    @EnvironmentObject private var library: NativeLibrary
    @Environment(\.dismiss) private var dismiss
    var requestedIDs: [String]? = nil
    @State private var session = ReviewSession(ids: [])
    @State private var initialized = false
    @State private var leaving = false
    @State private var skipping = false
    @State private var cleanup: CaptureSelection?
    private var exportIDs: Set<String> {
        Set(library.active.filter { session.approvedIDs.contains($0.id) && $0.reviewedAt != nil }.map(\.id))
    }
    var body: some View {
        VStack(spacing: 0) {
            if !initialized {
                ProgressView("מכין סבב קצר…")
            } else if let id = session.currentID {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("צילום \(session.resolvedCount + 1) מתוך \(session.ids.count)")
                            .font(.subheadline.weight(.semibold)).contentTransition(.numericText())
                        Spacer()
                        Text("\(session.approvedIDs.count) אושרו").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(session.resolvedCount), total: Double(max(1, session.ids.count)))
                        .tint(NativeTheme.accent)
                    Text("מה חשוב לזכור? תקן אם צריך, ובחר למה שמרת את זה לפני שממשיכים.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(18).background(NativeTheme.surface).animation(.snappy, value: session.resolvedCount)
                if library.capture(id) != nil {
                    CaptureDetail(id: id,
                        onApproved: { session.finish(id, as: .approved) },
                        onArchived: { session.finish(id, as: .archived) })
                        .id(id)
                } else {
                    ContentUnavailableView("המקור אינו זמין כרגע.", systemImage: "photo",
                        description: Text("הוא לא יסומן כאושר. אפשר להשאיר אותו לבדיקה מאוחר יותר."))
                }
                Button("להשאיר את הצילום להמשך") { skipping = true }
                    .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 18).padding(.bottom, 8)
                    .disabled(library.busy)
            } else {
                summary
            }
        }
        .background(NativeTheme.canvas)
        .navigationTitle("מבט קטן, סדר גדול").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("סיום") {
                    if session.currentID == nil { dismiss() } else { leaving = true }
                }.disabled(library.busy)
            }
        }
        .interactiveDismissDisabled(session.currentID != nil || library.busy)
        .onAppear {
            guard !initialized else { return }
            let allowed = requestedIDs.map { Set($0) }
            session = ReviewSession(ids: library.pending.filter { allowed?.contains($0.id) ?? true }.map(\.id))
            initialized = true
        }
        .confirmationDialog("להשאיר את הצילום לבדיקה בהמשך?", isPresented: $skipping, titleVisibility: .visible) {
            Button("השאר להמשך") { if let id = session.currentID { session.finish(id, as: .deferred) } }
            Button("חזור לעריכה") { skipping = false }
        } message: { Text("המקור נשמר. שינויים שלא אישרת במסך הזה לא יישמרו, והצילום יישאר בתיבת הסקירה.") }
        .confirmationDialog("לסיים את הסבב כאן?", isPresented: $leaving, titleVisibility: .visible) {
            Button("סיים לעכשיו") { dismiss() }
            Button("המשך בסקירה") { leaving = false }
        } message: { Text("הצילומים שכבר אישרת נשמרו. שינויים שלא אישרת בצילום הנוכחי לא יישמרו; אפשר לחזור אליו בהמשך.") }
        .sheet(item: $cleanup) { selection in CleanupView(ids: selection.ids) }
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: session.approvedIDs.isEmpty ? "tray" : "checkmark.seal")
                    .font(.system(size: 54, weight: .light)).foregroundStyle(NativeTheme.accent).accessibilityHidden(true)
                Text(session.ids.isEmpty ? "אין כרגע צילומים לסקירה." : "סבב קטן. קצת יותר סדר.")
                    .font(.title2.bold()).multilineTextAlignment(.center)
                if !session.ids.isEmpty {
                    Text("\(session.approvedIDs.count) אושרו · \(session.deferredCount) להמשך · \(session.archivedCount) אורכבו")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if !exportIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("רוצה לפנות את הצילומים מהגלריה?", systemImage: "leaf").font(.headline)
                        Text("נמשיך עם \(exportIDs.count) המקורות שאישרת בסבב הזה: ייצוא עותק, בדיקת המקור ואז אישור מחיקה. אפשר גם להשאיר אותם בתמונות.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { cleanup = CaptureSelection(ids: exportIDs) } label: {
                            Label("שמור עותק ובדוק פינוי", systemImage: "checkmark.shield")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }.padding(22).background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                }
                if library.pending.count > 0 {
                    Text("\(library.pending.count) צילומים עדיין מחכים בתיבת הסקירה. אפשר לחזור כשנוח.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button("חזרה למרחב שלי") { dismiss() }.controlSize(.large)
            }.padding(24).padding(.top, 22)
        }
    }
}
