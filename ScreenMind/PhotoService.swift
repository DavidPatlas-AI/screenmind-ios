import Foundation
import Photos
import UIKit

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
    struct ScreenshotStamp: Equatable {
        var identifier: String
        var created: Date
        var pixelWidth: Int
        var pixelHeight: Int
    }
    static func recentScreenshots(after: Date, limit: Int) throws -> [ScreenshotStamp] {
        guard hasAccess else { throw NativeError.message("אפשר לבחור תמונות בלי הרשאה מלאה, או לאפשר גישה לתמונות בהגדרות.") }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0 AND creationDate > %@",
            Int(PHAssetMediaSubtype.photoScreenshot.rawValue), after as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = limit
        var stamps: [ScreenshotStamp] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            stamps.append(ScreenshotStamp(
                identifier: asset.localIdentifier,
                created: asset.creationDate ?? .distantPast,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight
            ))
        }
        return stamps
    }
    static func estimatedPhotoBytes(_ asset: PHAsset) -> Int {
        let resources = PHAssetResource.assetResources(for: asset)
        var fileSize = 0
        for resource in resources {
            if let number = resource.value(forKey: "fileSize") as? NSNumber { fileSize += number.intValue }
            else if let intSize = resource.value(forKey: "fileSize") as? Int { fileSize += intSize }
        }
        return SpaceEstimate.bytes(
            fileBytes: fileSize > 0 ? fileSize : nil,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }
    static func screenshotIdentifiers() throws -> [String] {
        guard hasAccess else { throw NativeError.message("אפשר לבחור תמונות בלי הרשאה מלאה, או לאפשר גישה לתמונות בהגדרות.") }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var identifiers: [String] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            identifiers.append(asset.localIdentifier)
        }
        return identifiers
    }
    /// An `.exact` request is sized in pixels. Dividing by the screen scale would ask for about a third of `maxPixel` on a 3x phone.
    static func downscaled(_ asset: PHAsset, maxPixel: Int) async throws -> UIImage {
        let longest = max(asset.pixelWidth, asset.pixelHeight)
        let pixels = longest > 0 ? min(maxPixel, longest) : maxPixel
        let edge = CGFloat(pixels)
        let aspect = longest > 0 ? CGFloat(max(asset.pixelWidth, 1)) / CGFloat(max(asset.pixelHeight, 1)) : 1
        let target = asset.pixelWidth >= asset.pixelHeight
            ? CGSize(width: edge, height: max(edge / max(aspect, 0.01), 1))
            : CGSize(width: max(edge * aspect, 1), height: edge)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        return try await withCheckedThrowingContinuation { continuation in
            let gate = NSLock()
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                gate.lock()
                let first = !resumed
                resumed = true
                gate.unlock()
                guard first else { return }
                if (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image else {
                    continuation.resume(throwing: NativeError.message("לא הצלחתי לקרוא צילום מסך."))
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
    static func presentAndMissing(_ captures: [Capture]) -> (present: [(String, PHAsset)], missing: [String]) {
        var present: [(String, PHAsset)] = []
        var missing: [String] = []
        for capture in captures {
            if let identifier = capture.photoIdentifier, let asset = asset(id: identifier) {
                present.append((capture.id, asset))
            } else {
                missing.append(capture.id)
            }
        }
        return (present, missing)
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

enum ScreenshotPixels {
    static func jpeg(_ image: UIImage, quality: CGFloat = 0.72) -> Data? {
        image.jpegData(compressionQuality: quality)
    }

    static func grayscale(_ image: UIImage, width: Int = 9, height: Int = 8) -> [UInt8]? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let small = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cgImage = small.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var gray: [UInt8] = []
        gray.reserveCapacity(width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            let value = (UInt16(bytes[base]) * 3 + UInt16(bytes[base + 1]) * 6 + UInt16(bytes[base + 2])) / 10
            gray.append(UInt8(min(value, 255)))
        }
        return gray
    }
}
