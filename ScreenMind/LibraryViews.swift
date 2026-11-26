import SwiftUI
struct NativeLibraryView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    let cleanup: (Set<String>) -> Void
    var onScan: (() -> Void)? = nil
    var onScanAll: (() -> Void)? = nil
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
            let collectionMatches = collection == nil || capture.effectiveCollection == collection
            let searchable = [capture.displayTitle, capture.title, capture.text, capture.effectiveCollection, capture.intent.title].joined(separator: " ").lowercased()
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
                                           description: Text(query.isEmpty ? "בחר צילומים בכפתור + או סרוק צילומי מסך. אחר כך אפשר לראות איך הם מתחברים בלשונית המוח." : "החיפוש לפי הטקסט המזוהה, הכותרת ושם המרחב. אפשר לתקן טקסט מתוך המקור."))
                    if query.isEmpty && collection == nil && filter == "all" {
                        if let onScanAll {
                            Button(action: onScanAll) {
                                Label("סרוק את כל צילומי המסך", systemImage: "photo.stack")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.borderedProminent).disabled(library.busy)
                        }
                        if let onScan {
                            Button(action: onScan) {
                                Label("סרוק צילומי מסך", systemImage: "photo.badge.magnifyingglass")
                            }.buttonStyle(.bordered).disabled(library.busy)
                        }
                    }
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
        let groups = library.topicGroups
        let projects = ProjectCluster.build(from: library.active)
        let ordered = groups.keys.sorted {
            let left = groups[$0]?.count ?? 0, right = groups[$1]?.count ?? 0
            return left == right ? $0.localizedStandardCompare($1) == .orderedAscending : left > right
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("עולם הידע שלי").font(.largeTitle.bold())
                    Text("הצילומים כבר מסודרים לנושאים. אפשר לפתוח כל נושא ולגלות מה נשמר.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !projects.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("פרויקטים שהתגלו", systemImage: "folder.badge.gearshape")
                            .font(.title2.bold())
                        Text("מקורות שנמצאה בהם אותה כתובת פרויקט, ללא שיוך ידני.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(projects) { project in
                            NavigationLink {
                                ProjectTimelineView(cluster: project, open: open)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "point.3.connected.trianglepath.dotted")
                                        .font(.title2).foregroundStyle(.indigo)
                                        .frame(width: 44, height: 44)
                                        .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(project.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text("\(project.sources.count) מקורות · ציר זמן")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.backward").foregroundStyle(.secondary).font(.caption)
                                }.padding(12).background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !ordered.isEmpty {
                    Text("נושאים").font(.title2.bold())
                }
                if ordered.isEmpty {
                    ContentUnavailableView("כל רעיון יכול לקבל מקום.", systemImage: "folder",
                                           description: Text("סרוק צילומים והנושאים יופיעו כאן אוטומטית."))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 12)], spacing: 12) {
                    ForEach(ordered, id: \.self) { collection in
                        let count = groups[collection]?.count ?? 0
                        let style = topicStyle(collection)
                        NavigationLink {
                            NativeLibraryView(open: open, cleanup: { cleanup = CaptureSelection(ids: $0) }, collection: collection)
                                .navigationTitle(collection)
                                .safeAreaInset(edge: .bottom, spacing: 8) { ScanProgressBar() }
                                .toolbar {
                                    ToolbarItem(placement: .bottomBar) {
                                        ShareLink(item: CollectionBrief.text(name: collection, captures: library.captures)) {
                                            Label("שתף סיכום מרחב", systemImage: "square.and.arrow.up")
                                        }
                                    }
                                }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: style.0)
                                    .font(.system(size: 23, weight: .semibold))
                                    .foregroundStyle(style.1)
                                    .frame(width: 46, height: 46)
                                    .background(style.1.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                                Text(count.formatted()).font(.system(.largeTitle, design: .rounded).bold()).foregroundStyle(.primary)
                                Text(collection).font(.headline).foregroundStyle(.primary)
                                    .lineLimit(2, reservesSpace: true)
                                Text("מקורות").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(15)
                                .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(style.1.opacity(0.2), lineWidth: 1) }
                        }.buttonStyle(.plain)
                    }
                }
                Text("המיון מבוסס על טקסט מזוהה או ניתוח AI שאישרת. אפשר לתקן שיוך בפרטי מקור בכל עת.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }.background(NativeTheme.canvas)
            .sheet(item: $cleanup) { selection in CleanupView(ids: selection.ids) }
    }
    private func topicStyle(_ name: String) -> (String, Color) {
        switch SmartTopic.allCases.first(where: { $0.label == name }) {
        case .technology: return ("cpu", .indigo)
        case .learning: return ("book.closed", .blue)
        case .finance: return ("creditcard", .green)
        case .shopping: return ("bag", .orange)
        case .work: return ("briefcase", .teal)
        case .media: return ("play.rectangle", .purple)
        case .travel: return ("map", .cyan)
        case .food: return ("fork.knife", .pink)
        case .documents: return ("doc.text", .brown)
        case nil: return (name == "רעיונות פתוחים" ? "sparkles" : "folder.fill", NativeTheme.accent)
        }
    }
}

struct NativeSettingsView: View {
    @EnvironmentObject private var library: NativeLibrary
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                #if SCREENMIND_PERSONAL
                Section("גרסת ניסיון אישית") {
                    Text("מייבאים צילומים מתוך האפליקציה בכפתור +. בגרסה זו אין הרחבה בתפריט השיתוף.")
                    Text("יש לרענן את ההתקנה דרך AltStore מדי שבעה ימים. לפני הסרה או החלפת גרסה, ייצא את המקורות ל־Files.")
                }
                #endif
                Section("המרחב שלך") {
                    Label("מקורות וטקסט נשמרים מקומית", systemImage: "externaldrive")
                    Label("מיון מקומי כברירת מחדל; AI חיצוני רק בהסכמה", systemImage: "lock.shield")
                    Text("עברית ואנגלית מזוהות במכשיר עם Tesseract. כשאין עברית בתמונה, הזיהוי יכול להשתמש ב־Vision. שורת המצב לא נכנסת לטקסט. אפשר לתקן הכול.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("גישה לתמונות") {
                    Text("אפשר להתחיל מבחירה מוגבלת דרך +. סריקה ופינוי דורשים גישה לאותם צילומים דרך ספריית התמונות.")
                    if let url = URL(string: UIApplication.openSettingsURLString) { Link("פתח הגדרות הרשאה", destination: url) }
                }
                Section("לפני שמפנים") {
                    NavigationLink { BackupInspectionView() } label: { Label("בדיקת קובץ גיבוי", systemImage: "checkmark.shield") }
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

