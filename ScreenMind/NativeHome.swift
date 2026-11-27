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
    private enum ScanPrompt { case short, album }
    @State private var scanPrompt: ScanPrompt?
    @State private var albumCleanup = false
    @State private var showCleanupOptions = false
    var body: some View {
        TabView(selection: $tab) {
            tabPage { home.navigationTitle("ScreenMind").toolbar { toolbar } }
                .tabItem { Label("בית", systemImage: "house") }.tag(0)
            tabPage {
                NativeLibraryView(open: { selected = $0 }, cleanup: { cleanup = CaptureSelection(ids: $0) }, onScan: { scanPrompt = .short }, onScanAll: { scanPrompt = .album })
                    .navigationTitle("הספרייה").toolbar { toolbar }
            }.tabItem { Label("ספרייה", systemImage: "square.stack") }.tag(1)
            tabPage {
                IdeasBrainView(open: { selected = $0 }, onScan: { scanPrompt = .short }, onScanAll: { scanPrompt = .album })
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
        .sheet(isPresented: $albumCleanup) { AlbumCleanupView() }
        .onChange(of: library.albumScan.finishedToken) { _, token in
            if token > 0 { tab = 3 }
        }
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
                    Text("הצילומים זמינים בספרייה ובנושאים האוטומטיים. אין צורך לאשר כל צילום. שום צילום לא נמחק מהתמונות.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !report.reviewIDs.isEmpty {
                        Button("סקירה ידנית (רשות)") {
                            reviewIDs = report.reviewIDs
                            reviewAfterImport = true
                            library.report = nil
                        }.buttonStyle(.bordered).controlSize(.large)
                    }
                    Button("סיום") { library.report = nil }.buttonStyle(.borderedProminent).controlSize(.large)
                }.padding(28).navigationTitle("נשמר, לא נמחק").navigationBarTitleDisplayMode(.inline)
            }.presentationDetents([.medium, .large])
        }
        .alert("לא הצלחנו להשלים את הפעולה", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("הבנתי", role: .cancel) { library.error = nil }
        } message: { Text(library.error ?? "") }
        .sheet(isPresented: Binding(get: { library.reviewSpaceCaptures }, set: { library.reviewSpaceCaptures = $0 })) {
            NavigationStack {
                List(library.captures.filter { library.spaceOffer?.captureIDs.contains($0.id) == true }) { capture in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(capture.title)
                        Text(capture.text).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .navigationTitle("צילומים חדשים")
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("סיום") { library.reviewSpaceCaptures = false } } }
            }
        }
        .confirmationDialog(
            scanPrompt == .album ? "לסרוק את כל האלבום?" : "סריקה רק של הצילומים שתאפשר",
            isPresented: Binding(get: { scanPrompt != nil }, set: { if !$0 { scanPrompt = nil } }),
            titleVisibility: .visible
        ) {
            if scanPrompt == .album {
                Button("סרוק הכול") { Task { await library.scanAllScreenshots() } }
            } else {
                Button("אפשר גישה וסרוק") { Task { await library.scanScreenshots() } }
            }
            Button("ביטול") { scanPrompt = nil }
        } message: {
            Text(scanPrompt == .album
                 ? "כל צילומי המסך שהגישה מאפשרת. הסריקה רצה בסבבים קטנים, ואפשר להשהות. סגירה באמצע ממשיכה בפתיחה הבאה. הטקסט נשמר במכשיר עם עותק מוקטן. שום צילום לא נמחק בשלב הזה."
                 : "אפשר לאשר גישה מוגבלת. בסבב נשמרים עד 20 צילומים חדשים מתוך 100 האחרונים הנגישים. מקור מ־iCloud עשוי לדרוש הורדה. לא תתבצע מחיקה.")
        }
    }

    /// The bars sit on each screen inside the stack, so a push keeps them and the
    /// content can scroll clear. On the `TabView` they would cover the tab bar.
    private func tabPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content().screenMindBars() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            PhotosPicker(selection: $picker, maxSelectionCount: 20, matching: .images, preferredItemEncoding: .current) {
                Label("שמור צילומים", systemImage: "plus").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }.disabled(library.busy || library.albumScan.status == .running)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { settings = true } label: {
                Label("הגדרות ופרטיות", systemImage: "slider.horizontal.3").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
        }
    }
    private var albumButtonTitle: String {
        switch library.albumScan.status {
        case .paused, .interrupted, .cancelled: return "המשך סריקה"
        case .finished: return "סרוק צילומים חדשים"
        default: return "סרוק את כל צילומי המסך"
        }
    }
    private var albumCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if library.albumScan.status == .running {
                Text("סורק את כל צילומי המסך").font(.headline)
                ProgressView(value: library.albumScan.fraction)
                if !library.albumScan.progressLine.isEmpty {
                    Text(library.albumScan.progressLine).font(.subheadline).foregroundStyle(.secondary)
                }
                if library.albumScan.pausing {
                    Text("מסיים את הצילום הנוכחי…").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button {
                    if library.albumScan.status == .paused || library.albumScan.status == .interrupted || library.albumScan.status == .cancelled {
                        Task { await library.scanAllScreenshots() }
                    } else { scanPrompt = .album }
                } label: {
                    Label(albumButtonTitle, systemImage: "photo.stack")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(library.busy)
                if !library.albumScan.progressLine.isEmpty {
                    Text(library.albumScan.progressLine).font(.subheadline).foregroundStyle(.secondary)
                }
                if library.albumScan.failures > 0 {
                    Button("נסה שוב את מה שלא נקרא") { Task { await library.retryFailedAlbumScan() } }
                        .font(.subheadline)
                }
            }
            if !library.cleanupSummary.isEmpty {
                Button { albumCleanup = true } label: {
                    Label("בדוק מה אפשר לפנות", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private var libraryOverview: some View {
        let openTasks = library.active.filter { $0.hasTask && $0.reviewedAt != nil && $0.taskCompletedAt == nil }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("הספרייה שלי").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(library.captures.count, format: .number)
                .font(.system(.largeTitle, design: .rounded).bold())
                .monospacedDigit()
                .accessibilityLabel("\(library.captures.count) מקורות בארכיון")
            Text("מקורות בארכיון").font(.subheadline).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text("\(library.collections.count) נושאים")
                    Text("·").accessibilityHidden(true)
                    Text("\(openTasks) משימות פתוחות")
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(library.collections.count) נושאים")
                    Text("\(openTasks) משימות פתוחות")
                }
            }.font(.subheadline.weight(.medium)).foregroundStyle(NativeTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
    private var homeSearch: some View {
        NavigationLink {
            MemorySearchView(open: { selected = $0 })
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(NativeTheme.accent)
                    .accessibilityHidden(true)
                Text("מה אני רוצה למצוא?").font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.backward").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain)
    }
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("הידע שלך, במקום אחד").font(.largeTitle.weight(.semibold))
                    Text("הצילומים מתארגנים לנושאים. אין צורך למיין אחד־אחד.").foregroundStyle(.secondary)
                }.padding(.top, 12)
                if !library.captures.isEmpty {
                    homeSearch
                    libraryOverview
                }
                albumCard
                if library.captures.isEmpty {
                    ContentUnavailableView {
                        Label("מתחילים בכמה צילומים.", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("בחר צילומים בכפתור +, או שתף תמונה מכל אפליקציה אל ScreenMind. המקור נשמר לפני זיהוי הטקסט.")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("הידע שלך", systemImage: "sparkles").font(.title2.bold())
                        Text("\(library.recognizedCount) צילומים עם טקסט · \(library.collections.count) נושאים")
                            .font(.subheadline).foregroundStyle(.secondary)
                        NavigationLink {
                            MemoryDiscoveryView(open: { selected = $0 })
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath").font(.title2)
                                    .foregroundStyle(NativeTheme.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("גלה מחדש").font(.headline)
                                    Text("קשרים ישנים וחדשים, עם המקורות").font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.backward").font(.caption)
                            }.padding(14)
                                .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 15))
                        }.buttonStyle(.plain)
                        NavigationLink {
                            AIEnrichmentView()
                        } label: {
                            Label("ניתוח תוכן מתקדם ב־AI (רשות)", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                        }.buttonStyle(.bordered)
                        Button { tab = 3 } label: {
                            Label("פתח את הנושאים שלך", systemImage: "folder.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.borderedProminent)
                        if library.textAttentionCount > 0 {
                            Text("\(library.textAttentionCount) צילומים ללא טקסט או עם שגיאת זיהוי. אפשר לחזור אליהם לפי הצורך.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !library.pending.isEmpty {
                            Button("סקירה ידנית (רשות)") { reviewIDs = nil; review = true }
                                .font(.footnote).accessibilityLabel("לסקירה")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        .background(NativeTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                    Button { tab = 2 } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "brain.head.profile").font(.title2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("המוח של הרעיונות").font(.headline)
                                Text("פתח את מפת הנושאים והקשרים").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
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
                Button { scanPrompt = .short } label: {
                    Label("סרוק צילומי מסך באישור גישה", systemImage: "photo.badge.magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.bordered).disabled(library.busy)
                if library.spaceOffer != nil {
                    DisclosureGroup("פינוי תמונות (רשות)", isExpanded: $showCleanupOptions) {
                        Text("לפני מחיקת צילום חשוב, שמור עותק מלא מחוץ לאפליקציה. סריקת אלבום שומרת תמונה מוקטנת.")
                            .font(.caption).foregroundStyle(.secondary)
                        SpaceOfferBar()
                    }.padding(16)
                        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                Label("הזיהוי והמיון הבסיסי במכשיר. ניתוח AI חיצוני רק לאחר אישור מפורש.", systemImage: "lock.shield")
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
                    Text(capture.displayTitle).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text(capture.effectiveCollection).lineLimit(1)
                        Spacer(minLength: 3)
                        if capture.isFavorite { Image(systemName: "star.fill").foregroundStyle(.orange) }
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(13)
            }.background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityLabel(capture.displayTitle)
            .accessibilityValue(selected ? "נבחר" : capture.effectiveCollection)
    }
}

extension View {
    /// Bars live on the screen itself, inside the navigation stack. That keeps them
    /// after a push, lets lists scroll clear, and leaves a bottom toolbar above the scan bar.
    func screenMindBars() -> some View {
        safeAreaInset(edge: .bottom, spacing: 8) { ScanProgressBar() }
    }
}

struct SpaceOfferBar: View {
    @EnvironmentObject private var library: NativeLibrary
    var body: some View {
        if let offer = library.spaceOffer {
            VStack(alignment: .leading, spacing: 8) {
                Text(offer.headline).font(.headline)
                Text(offer.needsAccess ? offer.question : "המקור נשאר בתמונות. אפשר לעיין בצילומים בלי למחוק אותם.").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    if offer.needsAccess {
                        Button("אפשר גישה") { Task { await library.allowScreenshotAccess() } }
                    } else {
                        Button("בדוק") { library.reviewSpaceCaptures = true }.disabled(offer.captureIDs.isEmpty)
                    }
                    Button("השאר") { library.declineSpaceOffer() }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .accessibilityElement(children: .contain)
        }
    }
}

struct ScanProgressBar: View {
    @EnvironmentObject private var library: NativeLibrary
    var body: some View {
        Group {
            if library.albumScan.status == .running {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: library.albumScan.fraction)
                    Text(library.albumScan.progressLine).font(.subheadline).lineLimit(2)
                        .accessibilityLabel(library.albumScan.progressLine)
                    if library.albumScan.pausing { Text("מסיים את הצילום הנוכחי…").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button("השהה") { library.pauseAlbumScan() }.disabled(library.albumScan.pausing)
                        Button("בטל", role: .destructive) { library.cancelAlbumScan() }.disabled(library.albumScan.pausing)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            } else if library.busy && !library.progress.isEmpty {
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
        .animation(.snappy, value: library.albumScan.status)
    }
}
