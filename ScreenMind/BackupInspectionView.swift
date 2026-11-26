import SwiftUI
import UniformTypeIdentifiers

struct BackupInspectionView: View {
    @EnvironmentObject private var library: NativeLibrary
    @State private var choosing = false
    @State private var checking = false
    @State private var verified: VerifiedBackup?
    @State private var message: String?

    var body: some View {
        Form {
            Section("בדיקת גיבוי") {
                Text("בחר קובץ ZIP שנוצר במסך השמירה והפינוי. נבדוק את שלמות הקובץ, המטא־דאטה והמזהים, בלי לשנות את הספרייה.")
                Button("בחר גיבוי מתוך Files", systemImage: "folder") { choosing = true }
                    .disabled(checking)
                if checking { ProgressView("בודק את הקובץ במכשיר…") }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            if let verified {
                let comparison = verified.compare(with: library.captures)
                Section("תוצאות הבדיקה") {
                    LabeledContent("מקורות בקובץ", value: "\(verified.captures.count)")
                    LabeledContent("חדשים לספרייה", value: "\(comparison.newCount)")
                    LabeledContent("רשומות זהות", value: "\(comparison.identicalCount)")
                    LabeledContent("רשומות עם הבדלים", value: "\(comparison.conflictCount)")
                    LabeledContent("נפח המקורות", value: ByteCountFormatter.string(fromByteCount: Int64(verified.sourceBytes), countStyle: .file))
                    Text("בדיקת שלמות אינה אימות מקור מול התמונות או חתימה דיגיטלית. בגרסה זו עדיין לא משחזרים את הקובץ ולא מחליפים רשומות.")
                        .font(.footnote)
                }
            }
            Section {
                Text("הבדיקה מקומית בלבד. נתמכים גיבויים מהפורמט הקיים של ScreenMind, עד 20 מקורות ועד 40MB לקובץ כולל מטא־דאטה. אין להסתמך על קובץ זה כגיבוי מלא של הספרייה.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("אימות גיבוי")
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            verified = nil
            message = nil
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                checking = true
                Task {
                    defer { checking = false }
                    do {
                        verified = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let handle = try FileHandle(forReadingFrom: url)
                            defer { try? handle.close() }
                            let bytes = try handle.read(upToCount: VerifiedBackup.maxArchive+1) ?? Data()
                            return try VerifiedBackup.inspect(bytes)
                        }.value
                        message = "בדיקת השלמות עברה. לא שונה דבר."
                    } catch {
                        message = "לא ניתן לאמת את הגיבוי. הספרייה לא שונתה."
                    }
                }
            case .failure:
                message = "לא ניתן לפתוח את הקובץ."
            }
        }
    }
}
