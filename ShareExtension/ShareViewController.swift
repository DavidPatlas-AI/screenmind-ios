import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareSaveView(save: { [weak self] in
            guard let self else { throw NativeError.message("השיתוף נסגר.") }
            return try await self.saveAttachments()
        }, close: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) })
        let host = UIHostingController(rootView: root.environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "he")))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
    private func saveAttachments() async throws -> Int {
        let vault = try Vault()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !providers.isEmpty, providers.count <= 5 else { throw NativeError.message("בחר בין תמונה אחת לחמש תמונות בכל שיתוף.") }
        var saved = 0
        for provider in providers {
            guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                throw NativeError.message("סוג התמונה אינו נתמך.")
            }
            let (bytes, name): (Data, String) = try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    do {
                        if let error { throw error }
                        guard let url, url.isFileURL else { throw NativeError.message("לא ניתן לפתוח את התמונה.") }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 24 * 1024 * 1024 else { throw NativeError.message("בחר תמונה קטנה מ־24MB.") }
                        // Provider URLs expire after this callback. Read while access is valid.
                        continuation.resume(returning: (try Data(contentsOf: url), url.lastPathComponent))
                    } catch { continuation.resume(throwing: error) }
                }
            }
            try vault.save(data: bytes, name: name, photoIdentifier: nil, source: "share")
            saved += 1
        }
        return saved
    }
}
private struct ShareSaveView: View {
    let save: () async throws -> Int
    let close: () -> Void
    @State private var busy = false
    @State private var completed = false
    @State private var count = 0
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 20)
                Image(systemName: completed ? "checkmark.shield" : "square.stack.3d.up")
                    .font(.system(size: 48, weight: .light)).foregroundStyle(.green).accessibilityHidden(true)
                Text(completed ? "המקור נשמר." : "מקום לחזור אליו.").font(.title.weight(.semibold))
                Text(completed ? "\(count) מקורות נשמרו בארכיון המקומי. פתח את ScreenMind לזיהוי טקסט ולסקירה. שום דבר לא נמחק מהתמונות." : "שומרים את התמונה עצמה בארכיון הפרטי. זיהוי הטקסט יתבצע במכשיר כשתפתח את האפליקציה.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                if busy { ProgressView("שומר את המקורות…") }
                if let error {
                    Text(error).foregroundStyle(.red)
                    Text("אם שותפו כמה תמונות, חלקן עשויות כבר להיות שמורות. ניסיון חוזר מזהה כפילויות.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    if completed { close() }
                    else {
                        Task {
                            busy = true
                            do { count = try await save(); completed = true; error = nil }
                            catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }
                } label: { Text(completed ? "סיום" : "שמור ל־ScreenMind").frame(maxWidth: .infinity, minHeight: 32) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
                if !completed { Button("ביטול") { close() }.disabled(busy).controlSize(.large) }
                Spacer(minLength: 20)
                Label("ללא שליחה לספק AI", systemImage: "lock").font(.footnote).foregroundStyle(.secondary)
            }.padding(28).navigationTitle("ScreenMind").navigationBarTitleDisplayMode(.inline)
        }
    }
}
