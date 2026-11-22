import SwiftUI

struct AlbumCleanupView: View {
    @EnvironmentObject private var library: NativeLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var plan = CleanupPlan()
    @State private var selected: Set<String> = []
    @State private var markdown = ""
    @State private var plain = ""
    @State private var confirm = false
    @State private var error: String?
    @State private var completed = false
    @State private var alreadyGone = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(completed ? "הטקסט נשאר כאן." : "אפשר לפנות, בלי לאבד את מה שקראנו.").font(.title3.weight(.semibold))
                        Text(completed
                             ? (alreadyGone
                                ? "הצילומים האלה כבר לא היו בתמונות. ההערות נשארו ב־ScreenMind."
                                : "הצילומים שנבחרו עברו ל״נמחקו לאחרונה״ ל־30 יום. אפשר לשחזר אותם משם. ההערות נשארו ב־ScreenMind.")
                             : "מועדפים ומשימות פתוחות לא מופיעים. כלום לא נמחק לפני האישור שלך, ואפל מבקשת אישור נוסף. אם iCloud Photos פעיל, המחיקה מסתנכרנת.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        ShareLink(item: markdown) { Label("שתף כ־Markdown", systemImage: "doc.richtext") }
                            .buttonStyle(.bordered)
                        ShareLink(item: plain) { Label("שתף כטקסט", systemImage: "text.alignright") }
                            .buttonStyle(.bordered)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                category(title: "כפילויות", detail: "צילום כמעט זהה לאחר. נשמר זה עם יותר טקסט.", ids: plan.duplicates, select: "בחר את כל הכפילויות", clear: "נקה את הכפילויות")
                category(title: "בלי טקסט מועיל", detail: "אין כאן משפט שאפשר לחזור אליו.", ids: plan.junk, select: "בחר את כל מה שבלי טקסט מועיל", clear: "נקה את מה שבלי טקסט")
                category(title: "הטקסט כבר שמור", detail: "הטקסט בארכיון. אפשר להשאיר את הצילום אם הוא עדיין חשוב.", ids: plan.textSaved, select: "בחר את כל מה שהטקסט שלו שמור", clear: "נקה את מה שהטקסט שלו שמור")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NativeTheme.canvas)
            .navigationTitle("אפשר לפנות")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("סיום") { dismiss() }.disabled(library.busy) } }
            .safeAreaInset(edge: .bottom) {
                Button { confirm = true } label: {
                    Label("מחק את הבחירה מתמונות", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selected.isEmpty || library.busy || completed)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .confirmationDialog("למחוק את הצילומים שנבחרו?", isPresented: $confirm, titleVisibility: .visible) {
                Button("העבר לנמחקו לאחרונה", role: .destructive) {
                    Task {
                        do {
                            alreadyGone = try await library.deleteSuggested(ids: selected) == false
                            completed = true
                            selected = []
                            error = nil
                            plan = CleanupPlan.build(captures: library.active, fingerprints: library.albumLedger.fingerprints)
                        } catch { self.error = error.localizedDescription }
                    }
                }
                Button("להשאיר בתמונות", role: .cancel) {}
            } message: {
                Text("\(selected.count) צילומים. הטקסט וההערות נשארים ב־ScreenMind. ב״תמונות״ הם עוברים ל״נמחקו לאחרונה״ ל־30 יום.")
            }
            .onAppear {
                plan = CleanupPlan.build(captures: library.active, fingerprints: library.albumLedger.fingerprints)
                markdown = NotesExport.markdown(library.active)
                plain = NotesExport.plain(library.active)
            }
        }
    }

    private func category(title: String, detail: String, ids: [String], select: String, clear: String) -> some View {
        let chosen = ids.filter { selected.contains($0) }
        let all = !ids.isEmpty && chosen.count == ids.count
        let rows = stride(from: 0, to: ids.count, by: 3).map { start in
            Array(ids[start..<min(start + 3, ids.count)])
        }
        return Section {
            Text(title).font(.title3.weight(.semibold))
            Text(ids.isEmpty ? "אין כאן צילומים." : detail).font(.subheadline).foregroundStyle(.secondary)
            if !ids.isEmpty {
                Button(all ? clear : select) {
                    if all { selected.subtract(ids) } else { selected.formUnion(ids) }
                }
                .buttonStyle(.bordered)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { id in
                            if let capture = library.captures.first(where: { $0.id == id }) {
                                cell(capture)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ capture: Capture) -> some View {
        let on = selected.contains(capture.id)
        return Button {
            if on { selected.remove(capture.id) } else { selected.insert(capture.id) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    Group {
                        if let image = library.thumbnail(capture) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            NativeTheme.surface
                        }
                    }
                    .frame(height: 88)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(on ? NativeTheme.accent : Color.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
                Text(capture.title).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(6)
            .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(capture.title), \(on ? "נבחר" : "לא נבחר")")
    }
}
