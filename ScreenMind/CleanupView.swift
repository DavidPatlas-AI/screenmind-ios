import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct CleanupView: View {
    @EnvironmentObject private var library: NativeLibrary
    @Environment(\.dismiss) private var dismiss
    let ids: Set<String>
    @State private var prepared: PreparedBackup?
    @State private var document: BackupDocument?
    @State private var exporting = false
    @State private var confirmedExternalCopy = false
    @State private var confirmDeletion = false
    @State private var completed = false
    @State private var error: String?
    private var captures: [Capture] { library.captures.filter { ids.contains($0.id) } }
    private var canRequestDeletion: Bool {
        !captures.isEmpty && captures.count == ids.count && captures.allSatisfy({ library.deletionBlockReason($0) == nil })
            && confirmedExternalCopy && !library.busy && !completed
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: completed ? "checkmark.shield" : "leaf").font(.largeTitle).foregroundStyle(NativeTheme.accent)
                        Text(completed ? "הבקשה הושלמה." : "אפשר קצת לשחרר.").font(.title2.weight(.semibold))
                        Text(completed ? "הארכיון המקומי והעותק שייצאת נשארו. לשחזור מתמונות, בדוק את ״נמחקו לאחרונה״ באפליקציית תמונות." : "קודם עותק נוסף שנבדק, ורק אחר כך בקשת מחיקה. שום דבר לא יימחק בלי האישור שלך והאישור של אפל.")
                            .foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }
                if !completed {
                    Section("1 · עותק נוסף מחוץ לאפליקציה") {
                        Button { Task { await prepare() } } label: {
                            Label(library.backupReceipt?.captureIDs.isSuperset(of: ids) == true ? "ייצא עותק נוסף מחדש" : "ייצא את המקורות ל־Files", systemImage: "square.and.arrow.up")
                        }.disabled(library.busy || captures.isEmpty)
                        Text("ZIP עם הקבצים המקוריים, הטקסט ובדיקות SHA-256. עד 20 מקורות ו־32MB בסבב. לאחר השמירה, האפליקציה תנסה לפתוח ולאמת את העותק שנכתב בפועל.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if library.backupReceipt?.captureIDs.isSuperset(of: ids) == true {
                            Label("קובץ הייצוא נפתח ותאם לבדיקת התקינות.", systemImage: "checkmark.circle")
                                .foregroundStyle(NativeTheme.accent)
                            Toggle("פתחתי את ה־ZIP ובדקתי את המקורות מחוץ לאפליקציה", isOn: $confirmedExternalCopy)
                        }
                    }
                    Section("2 · בדיקת המקורות") {
                        ForEach(captures) { capture in
                            NavigationLink {
                                CaptureDetail(id: capture.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(capture.title)
                                    Text(library.deletionBlockReason(capture) ?? "מוכן לבדיקה סופית מול ספריית התמונות")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }
                        }
                    }
                    Section("3 · באישור שלך") {
                        Text("מחיקה מ־iCloud Photos מסתנכרנת למכשירים אחרים עם אותו חשבון. הארכיון הזה מקומי ועלול להימחק בהסרת האפליקציה. המחיקה אינה מבטיחה פינוי נפח מיידי.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(role: .destructive) { confirmDeletion = true } label: {
                            Label("בקש מחיקה של \(captures.count) צילומים מתמונות", systemImage: "trash")
                        }.disabled(!canRequestDeletion)
                        Text("לפני הבקשה נבדקים מחדש העותק החיצוני, המקור בארכיון והצילום בספריית התמונות. תמונות שעברו עריכה או שאינן צילומי מסך לא יימחקו דרך הזרימה הזו.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if library.busy { Section { HStack { ProgressView(); Text(library.progress).font(.subheadline) } } }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) } }
            }.navigationTitle("שמירה ופינוי").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("סיום") { dismiss() }.disabled(library.busy) } }
                .interactiveDismissDisabled(library.busy)
                .fileExporter(isPresented: $exporting, document: document, contentType: .zip,
                              defaultFilename: "ScreenMind-Originals") { result in
                    switch result {
                    case .success(let url):
                        guard let prepared else { return }
                        do { try library.verifyExport(url: url, prepared: prepared); error = nil; confirmedExternalCopy = false }
                        catch { self.error = error.localizedDescription }
                        self.prepared = nil; document = nil
                    case .failure(let error):
                        self.error = "הייצוא לא הושלם: " + error.localizedDescription
                        prepared = nil; document = nil
                    }
                }
                .confirmationDialog("להמשיך לאישור המחיקה של אפל?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                    Button("המשך לבקשת מחיקה", role: .destructive) {
                        Task {
                            do { try await library.deleteFromPhotos(ids: ids); completed = true; error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    Button("להשאיר בתמונות", role: .cancel) {}
                } message: { Text("רק הצילומים שברשימה ייכללו. אם iCloud Photos פעיל, המחיקה מסתנכרנת. העותקים השמורים אינם נמחקים.") }
        }
    }
    private func prepare() async {
        do {
            confirmedExternalCopy = false; error = nil
            let result = try await library.prepareBackup(ids: ids)
            prepared = result; document = BackupDocument(data: result.data); exporting = true
        } catch { self.error = error.localizedDescription }
    }
}
