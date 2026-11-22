import UIKit
import SwiftUI
import Photos
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareSaveView(
            save: { [weak self] in
                guard let self else { throw NativeError.message("השיתוף נסגר.") }
                return try await self.saveAttachments()
            },
            delete: { [weak self] batch in
                guard let self else { return false }
                return await self.deletePhotos(batch)
            },
            keep: { [weak self] batch in
                self?.keep(batch)
            },
            close: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        )
        let host = UIHostingController(rootView: root.environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "he")))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func saveAttachments() async throws -> ShareBatch {
        let vault = try Vault()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !providers.isEmpty, providers.count <= 5 else { throw NativeError.message("בחר בין תמונה אחת לחמש תמונות בכל שיתוף.") }
        var batch = ShareBatch()
        for provider in providers {
            guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                throw NativeError.message("סוג התמונה אינו נתמך.")
            }
            let identifier = await photoIdentifier(from: provider)
            let (bytes, name): (Data, String) = try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    do {
                        if let error { throw error }
                        guard let url, url.isFileURL else { throw NativeError.message("לא ניתן לפתוח את התמונה.") }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 24 * 1024 * 1024 else { throw NativeError.message("בחר תמונה קטנה מ־24MB.") }
                        continuation.resume(returning: (try Data(contentsOf: url), url.lastPathComponent))
                    } catch { continuation.resume(throwing: error) }
                }
            }
            let capture = try vault.save(data: bytes, name: name, photoIdentifier: identifier, source: "share")
            SpacePromptStore.enqueue(
                SpacePrompt(captureID: capture.id, photoIdentifier: identifier, estimatedBytes: bytes.count, createdAt: Date()),
                vault: vault
            )
            batch.count += 1
            batch.bytes += bytes.count
            batch.captureIDs.append(capture.id)
            if let identifier { batch.links.append(SharePhotoLink(captureID: capture.id, photoID: identifier)) }
        }
        return batch
    }

    private func photoIdentifier(from provider: NSItemProvider) async -> String? {
        let types = ["com.apple.photos.asset-identifier", "com.apple.photos.local-identifier"]
        for type in types where provider.hasItemConformingToTypeIdentifier(type) {
            let value: String? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                    if let text = item as? String { continuation.resume(returning: text) }
                    else if let data = item as? Data { continuation.resume(returning: String(data: data, encoding: .utf8)) }
                    else { continuation.resume(returning: nil) }
                }
            }
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return nil
    }

    private func deletePhotos(_ batch: ShareBatch) async -> Bool {
        guard !batch.links.isEmpty else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return false }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: batch.links.map(\.photoID), options: nil)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
        } catch { return false }
        let removedIDs = Set(assets.map(\.localIdentifier))
        let removedCaptures = batch.links.filter { removedIDs.contains($0.photoID) }.map(\.captureID)
        if let vault = try? Vault() {
            for id in removedCaptures {
                try? vault.update(id) { $0.photoDeletedAt = Date() }
            }
            SpacePromptStore.remove(Set(removedCaptures), vault: vault)
        }
        return !batch.links.isEmpty && removedCaptures.count == batch.links.count
    }

    private func keep(_ batch: ShareBatch) {
        guard let vault = try? Vault() else { return }
        SpacePromptStore.keep(Set(batch.captureIDs), vault: vault)
    }
}

struct SharePhotoLink: Equatable {
    var captureID: String
    var photoID: String
}

struct ShareBatch: Equatable {
    var count = 0
    var bytes = 0
    var links: [SharePhotoLink] = []
    var captureIDs: [String] = []
}

private struct ShareSaveView: View {
    let save: () async throws -> ShareBatch
    let delete: (ShareBatch) async -> Bool
    let keep: (ShareBatch) -> Void
    let close: () -> Void
    @State private var busy = false
    @State private var batch: ShareBatch?
    @State private var finished = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 12)
                Image(systemName: batch == nil ? "square.stack.3d.up" : "checkmark.shield")
                    .font(.system(size: 48, weight: .light)).foregroundStyle(.green).accessibilityHidden(true)
                Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if busy { ProgressView("שומר את המקור…") }
                if let error { Text(error).foregroundStyle(.red).multilineTextAlignment(.center) }
                if batch == nil {
                    Button {
                        Task {
                            busy = true
                            do { batch = try await save(); error = nil }
                            catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    } label: { Text("שמור ל־ScreenMind").frame(maxWidth: .infinity, minHeight: 36) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
                    Button("ביטול") { close() }.disabled(busy)
                } else if finished.isEmpty {
                    Button {
                        Task {
                            busy = true
                            let saved = batch ?? ShareBatch()
                            let deleted = await delete(saved)
                            if deleted && saved.links.count == saved.captureIDs.count {
                                finished = "הצילום עבר ל״נמחקו לאחרונה״. הטקסט נשאר ב־ScreenMind."
                            } else if deleted {
                                finished = "הצילומים שזוהו עברו ל״נמחקו לאחרונה״. בלי מזהה, המחיקה תחכה לפתיחת ScreenMind."
                            } else {
                                finished = "המחיקה תחכה לאישור כשתפתח את ScreenMind. הטקסט נשאר."
                            }
                            busy = false
                        }
                    } label: { Text("מחק מהתמונות").frame(maxWidth: .infinity, minHeight: 36) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
                    Button("השאר בתמונות") {
                        if let batch { keep(batch) }
                        finished = "הצילום נשאר בתמונות. הטקסט ייקרא כשתפתח את ScreenMind."
                    }.disabled(busy)
                }
                if !finished.isEmpty { Button("סיום") { close() }.buttonStyle(.borderedProminent).controlSize(.large) }
                Spacer(minLength: 12)
                Label("ללא שליחה לספק AI", systemImage: "lock").font(.footnote).foregroundStyle(.secondary)
            }.padding(28).navigationTitle("ScreenMind").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        if !finished.isEmpty { return "נשמר." }
        if batch == nil { return "מקום לחזור אליו." }
        return "המקור נשמר."
    }

    private var message: String {
        if !finished.isEmpty { return finished }
        if let batch {
            return "הזיהוי ייכנס למוח כשתפתח את ScreenMind. למחוק את הצילום כדי לפנות \(SpaceEstimate.label(batch.bytes))?"
        }
        return "שומרים את התמונה בארכיון הפרטי. מחיקה מהתמונות קורית רק אם תבקש, ואפשר גם אחר כך."
    }
}
