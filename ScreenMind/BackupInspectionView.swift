import SwiftUI
import UniformTypeIdentifiers

struct BackupInspectionView: View {
    @EnvironmentObject private var library: NativeLibrary
    private enum ImportMode { case zip, encryptedExport, encryptedRestore, legacyRestore }
    @State private var mode: ImportMode = .zip
    @State private var choosing = false
    @State private var recoveryCode = ""
    @State private var confirmationCode = ""
    @State private var restoreCode = ""
    @State private var encryption: BackupEncryption?
    @State private var confirmedStorage = false
    @State private var confirmFolderRestore = false
    @State private var checking = false
    @State private var confirming = false
    @State private var verified: VerifiedBackup?
    @State private var message: String?

    var body: some View {
        Form {
            Section("גיבוי ספרייה מלאה") {
                Text("גיבוי חדש מוצפן במפתח שחזור אקראי. הוא כולל רק מקורות שכבר נמצאים בארכיון המקומי. שמור את התיקייה מחוץ לאפליקציה ואת המפתח בנפרד. בלי המפתח אין אפשרות לשחזר.")
                Button("צור מפתח לגיבוי מוצפן", systemImage: "lock.shield") {
                    let key = BackupEncryption.generate()
                    encryption = key
                    recoveryCode = key.recoveryCode
                    confirmationCode = ""
                    confirmedStorage = false
                }.disabled(checking || library.busy || library.captures.isEmpty)
                if !recoveryCode.isEmpty {
                    Text(recoveryCode).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .environment(\.layoutDirection, .leftToRight)
                    SecureField("הזן שוב את המפתח ששמרת", text: $confirmationCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("שמרתי את המפתח בנפרד מהגיבוי", isOn: $confirmedStorage)
                    Button("בחר תיקייה לגיבוי מוצפן") {
                        mode = .encryptedExport
                        choosing = true
                    }.disabled(checking || library.busy || !confirmedStorage || confirmationCode != recoveryCode || encryption == nil)
                    Button("נקה את המפתח מהמסך", role: .destructive) { clearKey() }
                        .disabled(checking)
                }
                SecureField("מפתח שחזור של גיבוי קיים", text: $restoreCode)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("שחזר גיבוי מוצפן", systemImage: "lock.open") {
                    do {
                        clearKey()
                        encryption = try BackupEncryption(recoveryCode: restoreCode.trimmingCharacters(in: .whitespacesAndNewlines))
                        restoreCode = ""
                        mode = .encryptedRestore
                        confirmFolderRestore = true
                    } catch { message = "מפתח שחזור אינו תקין." }
                }.disabled(checking || library.busy || restoreCode.isEmpty)
                Button("שחזר תיקיית גיבוי ישנה ולא מוצפנת") {
                    clearKey()
                    mode = .legacyRestore
                    confirmFolderRestore = true
                }.disabled(checking || library.busy)
            }
            Section("בדיקת גיבוי") {
                Text("בחר קובץ ZIP שנוצר במסך השמירה והפינוי. נבדוק את שלמות הקובץ, המטא־דאטה והמזהים, בלי לשנות את הספרייה.")
                Button("בחר גיבוי מתוך Files", systemImage: "folder") { clearKey(); mode = .zip; choosing = true }
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
                    Text("בדיקת שלמות אינה אימות מול התמונות או חתימה דיגיטלית. השחזור מוסיף רק מקורות חסרים ולא מחליף רשומות קיימות. קישורים לתמונות ומצב אימות מחיקה לא ישוחזרו.")
                        .font(.footnote)
                    Button("שחזר מקורות חסרים") { confirming = true }
                        .disabled(checking || library.busy || comparison.newCount == 0)
                }
            }
            Section {
                Text("הבדיקה מקומית בלבד. נתמכים גיבויים מהפורמט הקיים של ScreenMind, עד 20 מקורות ועד 40MB לקובץ כולל מטא־דאטה. לקובץ ZIP יחיד יש מגבלה זו; לגיבוי ספרייה מלאה השתמש בתיקייה המחולקת לחלקים.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("אימות ושחזור גיבוי")
        .confirmationDialog("להוסיף לספרייה רק מקורות שאינם קיימים?", isPresented: $confirming, titleVisibility: .visible) {
            Button("שחזר מקורות חסרים") {
                guard let verified else { return }
                checking = true
                Task {
                    defer { checking = false }
                    do {
                        let result = try await library.restoreBackup(verified)
                        message = "נוספו \(result.inserted) · דולגו \(result.skipped) · נכשלו \(result.failed). רשומות קיימות לא הוחלפו."
                    } catch {
                        message = "השחזור לא התחיל: \(error.localizedDescription)"
                    }
                }
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("רק מקורות מגיבוי שאתה סומך עליו. הפעולה אינה מוחקת תמונות או רשומות. תקלה עלולה להשאיר שחזור חלקי.")
        }
        .confirmationDialog("לשחזר מקורות חסרים מתיקיית גיבוי?", isPresented: $confirmFolderRestore, titleVisibility: .visible) {
            Button("בחר תיקיית גיבוי") {
                choosing = true
            }
            Button("ביטול", role: .cancel) { clearKey() }
        } message: {
            Text("כל החלקים ייבדקו לפני השחזור. רשומות קיימות לא יוחלפו. בחר רק גיבוי מהימן; תקלה באמצע עלולה להותיר שחזור חלקי.")
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: mode == .zip ? [.zip] : [.folder], allowsMultipleSelection: false) { result in
            if mode != .zip {
                let operation = mode
                let key = encryption
                clearKey()
                restoreCode = ""
                verified = nil
                message = nil
                switch result {
                case .success(let urls):
                    guard let folder = urls.first else { return }
                    guard operation == .legacyRestore || key != nil else {
                        message = "מפתח חסר. לא בוצעה פעולה."
                        return
                    }
                    checking = true
                    Task {
                        defer { checking = false }
                        do {
                            if operation == .encryptedExport {
                                let report = try await library.exportLibraryBackup(to: folder, encryption: key)
                                message = "נשמרו \(report.count) מקורות מוצפנים ב־\(report.parts) חלקים בתיקייה \(report.folder). שמור את התיקייה ואת המפתח בנפרד."
                            } else {
                                let report = try await library.restoreLibraryBackup(from: folder, encryption: key)
                                message = "נוספו \(report.inserted) · דולגו \(report.skipped) · נכשלו \(report.failed) · לא עובדו \(report.notProcessed)."
                            }
                        } catch { message = "הפעולה לא הושלמה: \(error.localizedDescription)" }
                    }
                case .failure: message = "לא ניתן לפתוח את התיקייה."
                }
                return
            }
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

    private func clearKey() {
        encryption = nil
        recoveryCode = ""
        confirmationCode = ""
        confirmedStorage = false
    }
}
