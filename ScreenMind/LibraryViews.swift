import SwiftUI
struct NativeLibraryView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    let cleanup: (Set<String>) -> Void
    var collection: String? = nil
    @State private var query = ""
    @State private var filter = "all"
    @State private var choosing = false
    @State private var selected: Set<String> = []
    private var visible: [Capture] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return library.captures.filter { capture in
            let stateMatches = filter == "archive" ? capture.isArchived : !capture.isArchived
            let favoriteMatches = filter != "favorite" || capture.isFavorite
            let collectionMatches = collection == nil || capture.collection == collection
            let searchable = [capture.title, capture.text, capture.collection, capture.intent.title].joined(separator: " ").lowercased()
            return stateMatches && favoriteMatches && collectionMatches && tokens.allSatisfy { searchable.contains($0) }
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("תצוגת ספרייה", selection: $filter) {
                    Text("הכול").tag("all")
                    Text("מועדפים").tag("favorite")
                    Text("ארכיון").tag("archive")
                }.pickerStyle(.segmented).onChange(of: filter) { _, _ in selected = [] }
                if visible.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "יש מקום למשהו טוב." : "נסה מילה אחרת.", systemImage: "square.stack",
                                           description: Text(query.isEmpty ? "בחר צילומים בכפתור + או שנה מסנן." : "החיפוש לפי הטקסט המזוהה, הכותרת ושם המרחב. אפשר לתקן טקסט מתוך המקור."))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 16) {
                    ForEach(visible) { capture in
                        CaptureTile(capture: capture, selected: selected.contains(capture.id)) {
                            if choosing {
                                if selected.contains(capture.id) { selected.remove(capture.id) }
                                else if selected.count < 20 { selected.insert(capture.id) }
                            } else { open(capture) }
                        }
                    }
                }
                if choosing && !selected.isEmpty {
                    VStack(spacing: 12) {
                        Text("\(selected.count) נבחרו · עד 20 בכל סבב").font(.subheadline)
                        Button { cleanup(selected) } label: { Label("ייצוא ובדיקת פינוי", systemImage: "checkmark.shield") }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        Button(filter == "archive" ? "החזר לספרייה" : "העבר לארכיון") {
                            for id in selected { library.update(id) { $0.isArchived = filter != "archive" } }
                            selected = []
                        }.buttonStyle(.bordered).disabled(library.busy)
                        Text("ארכוב רק מסתיר מהספרייה, ואפשר לבטל אותו. הוא אינו מוחק מהתמונות.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding().frame(maxWidth: .infinity)
                        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding(18)
        }
        .background(NativeTheme.canvas)
        .searchable(text: $query, prompt: "מה רצית לזכור?")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(choosing ? "סיום בחירה" : "בחר") { choosing.toggle(); selected = [] }.disabled(library.busy)
            }
        }
    }
}
struct NativeCollectionsView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    @State private var cleanup: CaptureSelection?
    var body: some View {
        List {
            if library.collections.isEmpty {
                ContentUnavailableView("כל רעיון יכול לקבל מקום.", systemImage: "folder",
                                       description: Text("פתח צילום, ערוך את שם המרחב ושמור. כל המקורות עם אותו שם יופיעו יחד."))
            }
            ForEach(library.collections, id: \.self) { collection in
                NavigationLink {
                    NativeLibraryView(open: open, cleanup: { cleanup = CaptureSelection(ids: $0) }, collection: collection)
                        .navigationTitle(collection)
                        .toolbar {
                            ToolbarItem(placement: .bottomBar) {
                                ShareLink(item: CollectionBrief.text(name: collection, captures: library.captures)) {
                                    Label("שתף סיכום מרחב", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "folder").font(.title2).foregroundStyle(NativeTheme.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(collection).font(.headline)
                            Text("\(library.active.filter { $0.collection == collection }.count) מקורות")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
            }
            Section {
                Text("מרחב מחבר מקורות שבחרת לשייך יחד. אין כאן עדיין שיוך AI או הסקת מסקנות אוטומטית.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.sheet(item: $cleanup) { selection in CleanupView(ids: selection.ids) }
    }
}
struct NativeSettingsView: View {
    @EnvironmentObject private var library: NativeLibrary
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("המרחב שלך") {
                    Label("מקורות וטקסט נשמרים מקומית", systemImage: "externaldrive")
                    Label("ללא חשבון וללא ספק AI חיצוני", systemImage: "lock.shield")
                    Text("Vision של אפל מזהה טקסט במכשיר. תמיכה בשפות ובאיכות הצילום משתנה לפי המכשיר ומערכת ההפעלה. אפשר לתקן הכול.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("גישה לתמונות") {
                    Text("אפשר להתחיל מבחירה מוגבלת דרך +. סריקה ופינוי דורשים גישה לאותם צילומים דרך ספריית התמונות.")
                    if let url = URL(string: UIApplication.openSettingsURLString) { Link("פתח הגדרות הרשאה", destination: url) }
                }
                Section("לפני שמפנים") {
                    Text("הארכיון המקומי עלול להימחק בהסרת האפליקציה. ייצא עותק נוסף ל־Files, ובדוק שאתה יכול לפתוח את המקורות.")
                    Text("מחיקה מתמונות עשויה להסתנכרן לכל המכשירים עם iCloud Photos. היא אינה מבטיחה פינוי נפח מיידי.")
                        .foregroundStyle(.secondary)
                }
                Section("מה עדיין לא מחובר") {
                    Text("גרסת האייפון עצמאית. אין סנכרון עם גרסת המחשב, ניתוח Gemini, זיהוי סתירות או סוכן שמבצע פעולות בשירותים אחרים.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section { Text("\(library.captures.count) מקורות בארכיון המקומי").foregroundStyle(.secondary) }
            }.navigationTitle("פרטיות והגדרות")
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("סיום") { dismiss() } } }
        }
    }
}
