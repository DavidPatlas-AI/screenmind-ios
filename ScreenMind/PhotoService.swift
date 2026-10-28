import Foundation
import Photos

enum PhotoService {
    static func permission() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
    static var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }
    static func screenshots(limit: Int = 100) throws -> [PHAsset] {
        guard hasAccess else { throw NativeError.message("אפשר לבחור תמונות בלי הרשאה מלאה, או לאפשר גישה לתמונות בהגדרות.") }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
    static func asset(id: String) -> PHAsset? {
        guard hasAccess else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }
    static func isUneditedScreenshot(_ asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        return asset.mediaType == .image && asset.mediaSubtypes.contains(.photoScreenshot) &&
            resources.count == 1 && resources.first?.type == .photo
    }
    static func original(_ asset: PHAsset) async throws -> (Data, String) {
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) else {
            throw NativeError.message("המקור אינו תמונה נתמכת.")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 24 * 1024 * 1024 else { throw NativeError.message("המקור גדול מ־24MB.") }
        return (try Data(contentsOf: url), resource.originalFilename)
    }
    static func requestDeletion(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }
}
