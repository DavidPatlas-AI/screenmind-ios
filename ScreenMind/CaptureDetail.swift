import SwiftUI

struct CaptureDetail: View {
    @EnvironmentObject private var library: NativeLibrary
    @Environment(\.dismiss) private var dismiss
    let id: String
    var onApproved: (() -> Void)? = nil
    var onArchived: (() -> Void)? = nil
    @State private var title = ""
    @State private var text = ""
    @State private var collection = ""
    @State private var intent: SaveIntent = .remember
    @State private var original = false
    @State private var cleanup = false
    @State private var saved = false
    @State private var taskTitle = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var saveError: String?
    private var capture: Capture? { library.capture(id) }

    var body: some View {
        Group {
            if let capture {
                Form {
                    Section {
                        Button { original = true } label: {
                            VStack(spacing: 10) {
                                if let image = library.thumbnail(capture) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 210)
                                }
                                Label("פתח את המקור בגודל מלא", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.subheadline).frame(minHeight: 44)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain)
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recognitionNote(capture))
                            if library.hebrewRecognitionSupported == false {
                                Text("קובצי העברית לזיהוי לא נמצאו באפליקציה, והטקסט עלול להיות חסר.")
                            }
                        }
                    }
                    if let analysis = capture.currentAIAnalysis {
                        Section("ניתוח AI — הצעה") {
                            Text(analysis.title).font(.headline)
                            Text(analysis.summary)
                            if !analysis.suggestedTask.isEmpty {
                                Label(analysis.suggestedTask, systemImage: "checklist")
                                    .font(.subheadline)
                            }
                            Text("נוצר באמצעות AI, ייתכנו טעויות. המקור נשאר ללא שינוי.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("הסר את ניתוח ה־AI", role: .destructive) {
                                library.update(capture.id) { $0.aiAnalysis = nil }
                            }.disabled(library.busy)
                        }
                    }
                    Section {
                        TextField("כותרת קצרה", text: $title, axis: .vertical).lineLimit(1...3)
                        TextEditor(text: $text).frame(minHeight: 120).accessibilityLabel("הטקסט והתיאור")
                        Button("זהה טקסט מחדש") {
                            Task {
                                await library.rerecognize(id)
                                if let updated = library.capture(id) {
                                    title = updated.title
                                    text = updated.text
                                }
                            }
                        }
                        .disabled(library.busy)
                        if library.busy && !library.progress.isEmpty {
                            HStack(spacing: 8) { ProgressView(); Text(library.progress).font(.subheadline) }
                        }
                        Button("זיהוי מדויק") {}
                            .disabled(!AccurateRecognition.isEnabled || library.busy)
                    } header: {
                        Text("מה חשוב לזכור")
                    } footer: {
                        Text(AccurateRecognition.unavailableMessage)
                    }
                    let insights = CaptureInsights.detect(title: capture.title, text: capture.text)
                    let sequence = CaptureSequences.sequence(containing: capture.id, in: library.captures)
                    if !insights.isEmpty || !sequence.isEmpty {
                        Section("שים לב") {
                            ForEach(insights, id: \.self) { insight in
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(insight.title, systemImage: insight.symbol).font(.subheadline.weight(.semibold))
                                    Text(insight.detail).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            if !sequence.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("חלק מרצף של \(sequence.count) צילומים", systemImage: "square.stack.3d.down.right")
                                        .font(.subheadline.weight(.semibold))
                                    Text("כנראה מאותו סרטון או שרשור. לפי סדר הצילום:").font(.footnote).foregroundStyle(.secondary)
                                    ForEach(Array(sequence.enumerated()), id: \.element.id) { index, item in
                                        Text("\(index + 1). \(item.title.isEmpty ? "צילום" : item.title)")
                                            .font(.footnote)
                                            .fontWeight(item.id == capture.id ? .bold : .regular)
                                    }
                                }
                            }
                        }
                    }
                    Section("מה רצית לעשות עם זה?") {
                        Picker("כוונה", selection: $intent) { ForEach(SaveIntent.allCases) { value in Text(value.title).tag(value) } }
                        TextField("שם מרחב, למשל הטיול הבא", text: $collection)
                        Button {
                            library.update(id) { $0.isFavorite.toggle() }
                        } label: {
                            Label(capture.isFavorite ? "הסר ממועדפים" : "הוסף למועדפים", systemImage: capture.isFavorite ? "star.fill" : "star")
                        }
                    }
                    if intent == .act {
                        Section {
                            TextField("למשל: להשוות בין שני הדגמים", text: $taskTitle, axis: .vertical)
                                .lineLimit(1...3)
                            Toggle("לקבוע תאריך יעד", isOn: $hasDueDate)
                            if hasDueDate { DatePicker("מתי לחזור לזה?", selection: $dueDate, displayedComponents: .date) }
                            if capture.hasTask {
                                Button(capture.taskCompletedAt == nil ? "סמן שבוצע" : "החזר לפעולות פתוחות") {
                                    library.update(id) { $0.taskCompletedAt = $0.taskCompletedAt == nil ? Date() : nil }
                                }.disabled(library.busy)
                            }
                        } header: {
                            Text("צעד קטן שאפשר לבצע")
                        } footer: {
                            Text("הפעולה תופיע בלשונית ״הצעד הבא״ אחרי השמירה. תאריך יעד אינו מפעיל התראה.")
                        }
                    }
                    Section {
                        Button { save(approve: true) } label: {
                            Label(onApproved != nil ? "אשר והמשך לצילום הבא" : capture.reviewedAt == nil ? "בדקתי. שמור את זה." : "שמור את העדכון", systemImage: "checkmark")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library.busy)
                        if onApproved == nil && (saved || capture.reviewedAt != nil) {
                            Label("הפרטים נשמרו. המקור נשאר בארכיון.", systemImage: "checkmark.shield")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button { cleanup = true } label: { Label("ייצוא עותק ובדיקת פינוי", systemImage: "photo.badge.checkmark") }
                        }
                        Button(capture.isArchived ? "החזר לספרייה" : "העבר לארכיון") {
                            if library.update(id, change: { $0.isArchived.toggle() }) {
                                if let onArchived { onArchived() } else { dismiss() }
                            } else { saveError = library.error ?? "השינוי לא נשמר. נסה שוב." }
                        }.disabled(library.busy)
                        if let saveError { Text(saveError).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) }
                    } footer: {
                        Text("ארכוב הוא הפיך ואינו מוחק מהתמונות. פינוי דורש עותק נוסף, בדיקות ואישור של אפל.")
                    }
                }.navigationTitle("המקור והכוונה").navigationBarTitleDisplayMode(.inline)
                    .onAppear {
                        if title.isEmpty {
                            title = capture.title; text = capture.text
                            collection = capture.collection; intent = capture.intent
                            taskTitle = capture.taskTitle ?? ""
                            hasDueDate = capture.taskDueAt != nil
                            dueDate = capture.taskDueAt ?? Date()
                        }
                    }
                    .fullScreenCover(isPresented: $original) { OriginalPreview(capture: capture) }
                    .sheet(isPresented: $cleanup) { CleanupView(ids: [id]) }
            } else {
                ContentUnavailableView("המקור אינו זמין.", systemImage: "photo")
            }
        }
    }
    private func recognitionNote(_ capture: Capture) -> String {
        switch capture.textStatus {
        case "pending": return "מזהים את הטקסט במכשיר… המקור כבר שמור, ואפשר להמשיך לערוך."
        case "failed": return "הזיהוי לא הושלם. המקור שמור, ואפשר לזהות מחדש או להוסיף תיאור ידנית."
        case "noText": return "לא נמצא טקסט בתמונה. אפשר להוסיף תיאור ידנית."
        case "complete": return "הטקסט זוהה במכשיר. כדאי לבדוק שמות, סכומים ותאריכים מול המקור."
        case "reread": return "הטקסט זוהה שוב במכשיר. כדאי לבדוק שמות, סכומים ותאריכים מול המקור."
        default: return "המקור נשמר. אפשר להוסיף תיאור ידנית."
        }
    }
    private func save(approve: Bool) {
        let didSave = library.update(id) { capture in
            capture.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
            capture.text = text
            let value = collection.trimmingCharacters(in: .whitespacesAndNewlines)
            capture.collection = value.isEmpty ? "כללי" : String(value.prefix(80))
            capture.intent = intent
            let task = String(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            capture.taskTitle = task.isEmpty ? nil : task
            capture.taskDueAt = hasDueDate ? dueDate : nil
            if approve { capture.reviewedAt = Date() }
        }
        saved = didSave
        if didSave {
            saveError = nil
            if approve { onApproved?() }
        } else { saveError = library.error ?? "הפרטים לא נשמרו. נסה שוב לפני שתמשיך." }
    }
}
struct OriginalPreview: View {
    @EnvironmentObject private var library: NativeLibrary
    @Environment(\.dismiss) private var dismiss
    let capture: Capture
    var body: some View {
        NavigationStack {
            Group {
                if let image = library.image(capture) {
                    ZoomableImage(image: image).accessibilityLabel("המקור: " + capture.title)
                        .onAppear { library.update(capture.id) { $0.viewedAt = Date() } }
                } else {
                    ContentUnavailableView("לא ניתן לפתוח את המקור.", systemImage: "exclamationmark.triangle")
                }
            }.background(Color(uiColor: .systemBackground)).navigationTitle("המקור השמור")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("סיום") { dismiss() } } }
        }
    }
}
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> ImageScrollView { ImageScrollView(image: image) }
    func updateUIView(_ uiView: ImageScrollView, context: Context) {}
}
final class ImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private var lastBounds = CGSize.zero
    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        delegate = self; minimumZoomScale = 1; maximumZoomScale = 5
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBounds && bounds.width > 0 && bounds.height > 0 {
            lastBounds = bounds.size
            setZoomScale(1, animated: false)
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}

