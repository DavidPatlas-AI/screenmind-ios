import SwiftUI
import PhotosUI
struct NativeHome: View {
    @EnvironmentObject private var library: NativeLibrary
    @State private var tab = 0
    @State private var picker: [PhotosPickerItem] = []
    @State private var selected: Capture?
    @State private var review = false
    @State private var reviewIDs: [String]?
    @State private var reviewAfterImport = false
    @State private var cleanup: CaptureSelection?
    @State private var settings = false
    @State private var explainScan = false
    var body: some View {
        TabView(selection: $tab) {
            tabPage { home.navigationTitle("ScreenMind").toolbar { toolbar } }
                .tabItem { Label("בית", systemImage: "house") }.tag(0)
            tabPage {
                NativeLibraryView(open: { selected = $0 }, cleanup: { cleanup = CaptureSelection(ids: $0) }, onScan: { explainScan = true })
                    .navigationTitle("הספרייה").toolbar { toolbar }
            }.tabItem { Label("ספרייה", systemImage: "square.stack") }.tag(1)
            tabPage {
                IdeasBrainView(open: { selected = $0 }, onScan: { explainScan = true })
                    .navigationTitle("המוח").toolbar { toolbar }
            }.tabItem { Label("המוח", systemImage: "brain.head.profile") }.tag(2)
            tabPage {
                NativeCollectionsView(open: { selected = $0 }).navigationTitle("מרחבים").toolbar { toolbar }
            }.tabItem { Label("מרחבים", systemImage: "folder") }.tag(3)
            tabPage {
                NativeActionsView(open: { selected = $0 }).toolbar { toolbar }
            }.tabItem { Label("הצעד הבא", systemImage: "checklist") }.tag(4)
        }
        .onChange(of: picker) { _, items in
            guard !items.isEmpty else { return }
            Task { await library.importPicker(items); picker = [] }
        }
        .sheet(item: $selected) { capture in NavigationStack { CaptureDetail(id: capture.id) } }
        .sheet(isPresented: $review) { NavigationStack { NativeReviewView(requestedIDs: reviewIDs) } }
        .sheet(item: $cleanup) { selection in CleanupView(ids: selection.ids) }
        .sheet(isPresented: $settings) { NativeSettingsView() }
        .sheet(item: $library.report, onDismiss: {
            if reviewAfterImport { reviewAfterImport = false; review = true }
        }) { report in
            NavigationStack {
                VStack(spacing: 22) {
                    Image(systemName: report.saved > 0 ? "checkmark.seal" : "tray")
                        .font(.system(size: 52, weight: .light)).foregroundStyle(NativeTheme.accent).accessibilityHidden(true)
                    Text(report.saved > 0 ? "המקורות נשמרו." : "הסריקה הסתיימה.").font(.title2.bold())
                    Text("\(report.saved) צילומים חדשים · \(report.duplicates) כבר היו בארכיון")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if report.failures > 0 { Text("\(report.failures) קבצים לא נקלטו. אפשר לבחור אותם ולנסות שוב.").foregroundStyle(.orange) }
                    Text("עכשיו רק מבט קטן על הטקסט והכוונה. שום צילום לא נמחק מהתמונות.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !report.reviewIDs.isEmpty {
                        Button("לסקירת \(report.reviewIDs.count) צילומים") {
                            reviewIDs = report.reviewIDs
                            reviewAfterImport = true
                            library.report = nil
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Button("להשאיר להמשך") { library.report = nil }.controlSize(.large)
                }.padding(28).navigationTitle("נשמר, לא נמחק").navigationBarTitleDisplayMode(.inline)
            }.presentationDetents([.medium, .large])
        }
        .alert("לא הצלחנו להשלים את הפעולה", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("הבנתי", role: .cancel) { library.error = nil }
        } message: { Text(library.error ?? "") }
        .confirmationDialog("סריקה רק של הצילומים שתאפשר", isPresented: $explainScan, titleVisibility: .visible) {
            Button("אפשר גישה וסרוק") { Task { await library.scanScreenshots() } }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("אפשר לאשר גישה מוגבלת. בסבב נשמרים עד 20 צילומים חדשים מתוך 100 האחרונים הנגישים. מקור מ־iCloud עשוי לדרוש הורדה. לא תתבצע מחיקה.")
        }
    }

    /// The inset sits inside the tab. On the TabView it covers the tab bar.
    private func tabPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content().safeAreaInset(edge: .bottom, spacing: 8) { scanProgress }
        }
    }

    private var scanProgress: some View {
        Group {
            if library.busy && !library.progress.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(library.progress).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(library.progress)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: library.busy)
        .animation(.snappy, value: library.progress)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            PhotosPicker(selection: $picker, maxSelectionCount: 20, matching: .images, preferredItemEncoding: .current) {
                Label("שמור צילומים", systemImage: "plus").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }.disabled(library.busy)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { settings = true } label: {
                Label("הגדרות ופרטיות", systemImage: "slider.horizontal.3").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
        }
    }
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("פחות לשמור בראש.").font(.largeTitle.weight(.semibold))
                    Text("הדברים שצילמת, והרעיונות שחיכו. עכשיו יש להם מקום.").foregroundStyle(.secondary)
                }.padding(.top, 12)
                if library.captures.isEmpty {
                    ContentUnavailableView {
                        Label("מתחילים בכמה צילומים.", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("בחר צילומים בכפתור +, או שתף תמונה מכל אפליקציה אל ScreenMind. המקור נשמר לפני זיהוי הטקסט.")
                    }
                } else {
                    Button { reviewIDs = nil; review = true } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            Label(library.pending.isEmpty ? "אפשר לנשום." : "רק מבט קטן ממך.", systemImage: "viewfinder")
                                .font(.title3.weight(.medium))
                            Text(library.pending.isEmpty ? "אין כרגע צילומים שמחכים לסקירה." : "\(library.pending.count) צילומים מוכנים לבדיקה. תקן, אשר והמשך.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if !library.pending.isEmpty { Label("לסקירה", systemImage: "arrow.up.left").font(.subheadline.weight(.medium)) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                            .background(NativeTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(library.pending.isEmpty ? "אין צילומים לסקירה" : "לסקירה")
                    Button { tab = 2 } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "brain.head.profile").font(.title2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("המוח של הרעיונות").font(.headline)
                                Text("נושאים וקשרים ממה שזיהינו ומהכוונה שלך").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.backward")
                        }.padding(18).background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain).accessibilityLabel("המוח של הרעיונות")
                    let actions = library.active.filter { $0.hasTask && $0.reviewedAt != nil && $0.taskCompletedAt == nil }
                    if !actions.isEmpty {
                        Button { tab = 4 } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "checklist").font(.title2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(actions.count) רעיונות מחכים לצעד הבא").font(.headline)
                                    Text(actions.first?.taskTitle ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.backward")
                            }.padding(18).background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                    HStack {
                        Text("נשמרו לאחרונה").font(.title3.weight(.medium))
                        Spacer()
                        Button("לכל הספרייה") { tab = 1 }.font(.subheadline)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 16) {
                        ForEach(Array(library.active.prefix(4))) { capture in
                            CaptureTile(capture: capture, selected: false) { selected = capture }
                        }
                    }
                    if !library.active.filter({ $0.reviewedAt != nil && $0.photoDeletedAt == nil }).isEmpty {
                        Button {
                            cleanup = CaptureSelection(ids: Set(library.active.filter { $0.reviewedAt != nil && $0.photoDeletedAt == nil }.prefix(20).map(\.id)))
                        } label: { Label("עותק נוסף, ואז בדיקת פינוי", systemImage: "checkmark.shield") }
                            .buttonStyle(.bordered).controlSize(.large)
                    }
                }
                Button { explainScan = true } label: {
                    Label("סרוק צילומי מסך באישור גישה", systemImage: "photo.badge.magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.bordered).disabled(library.busy)
                Label("הזיהוי מתבצע במכשיר. אין חשבון ואין שליחה לספק AI.", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
            }.padding(20)
        }.background(NativeTheme.canvas)
    }
}
struct CaptureTile: View {
    @EnvironmentObject private var library: NativeLibrary
    let capture: Capture
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = library.thumbnail(capture) { Image(uiImage: image).resizable().scaledToFill() }
                        else { Rectangle().fill(Color.secondary.opacity(0.12)).overlay { Image(systemName: "photo").foregroundStyle(.secondary) } }
                    }.frame(height: 165).clipped()
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.title2).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, NativeTheme.accent).padding(10)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(capture.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text(capture.needsReview ? "לסקירה" : capture.collection).lineLimit(1)
                        Spacer(minLength: 3)
                        if capture.isFavorite { Image(systemName: "star.fill").foregroundStyle(.orange) }
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(13)
            }.background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityLabel(capture.title)
            .accessibilityValue(selected ? "נבחר" : capture.needsReview ? "ממתין לסקירה" : capture.collection)
    }
}
