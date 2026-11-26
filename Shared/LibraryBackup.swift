import Foundation

// A full library backup is a folder of existing bounded ZIP files plus a
// completion index written last. No archive is loaded in its entirety.
enum LibraryBackup {
    static let maxCaptures = 10_000
    static let indexName = "screenmind-library.json"
    static let indexLimit = 4 * 1024 * 1024

    struct Part: Codable, Sendable {
        let name: String
        let sha256: String
        let count: Int
        let byteCount: Int
    }
    struct Index: Codable, Sendable {
        let version: Int
        let createdAt: Date
        let count: Int
        let parts: [Part]
    }
    struct ExportResult: Sendable {
        let folder: String
        let count: Int
        let parts: Int
    }
    private static func invalid() -> NativeError {
        .message("גיבוי הספרייה חסר, לא תקין או אינו נתמך.")
    }
    private static func partName(_ i: Int) -> String { String(format:"part-%05d.zip",i+1) }
    private static func read(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= limit else { throw invalid() }
        let handle = try FileHandle(forReadingFrom:url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            let remaining = limit+1-data.count
            guard let block = try handle.read(upToCount:min(remaining,1024*1024)), !block.isEmpty else { break }
            data.append(block)
        }
        guard data.count == size, data.count <= limit else { throw invalid() }
        return data
    }
    static func export(vault: Vault, to parent: URL) throws -> ExportResult {
        let captures = try vault.all()
        guard !captures.isEmpty, captures.count <= maxCaptures else {
            throw NativeError.message("הגיבוי תומך ב־1 עד 10,000 מקורות.")
        }
        let name = "ScreenMind-backup-"+UUID().uuidString
        let folder = parent.appendingPathComponent(name,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
        var parts: [Part] = []
        var files: [(String,Data)] = []
        var selected: [Capture] = []
        var sourceBytes = 0, metadataBytes = 0
        func flush() throws {
            guard !selected.isEmpty else { return }
            let manifest = try JSONEncoder().encode(selected)
            guard manifest.count <= VerifiedBackup.maxManifest else { throw invalid() }
            let zip = try BackupArchive.zip(files + [
                ("manifest.json",manifest),
                ("README.txt",Data("ScreenMind library part. Contains vault copies, not necessarily full-resolution PhotoKit originals.".utf8))
            ])
            let checked = try VerifiedBackup.inspect(zip)
            guard checked.captures == selected else { throw invalid() }
            let filename = partName(parts.count)
            let url = folder.appendingPathComponent(filename)
            try zip.write(to:url,options:[.atomic])
            let saved = try read(url,limit:VerifiedBackup.maxArchive)
            let digest = Vault.hash(zip)
            guard Vault.hash(saved) == digest else { throw invalid() }
            parts.append(Part(name:filename,sha256:digest,count:selected.count,byteCount:zip.count))
            files.removeAll(); selected.removeAll(); sourceBytes = 0; metadataBytes = 0
        }
        for capture in captures {
            let bytes = try vault.original(capture)
            let meta = try JSONEncoder().encode(capture).count
            guard bytes.count <= VerifiedBackup.maxSourceBytes, meta < VerifiedBackup.maxManifest-1024 else { throw invalid() }
            if selected.count >= VerifiedBackup.maxSources ||
                sourceBytes+bytes.count > VerifiedBackup.maxSourceBytes ||
                metadataBytes+meta+selected.count+2 > VerifiedBackup.maxManifest-1024 {
                try flush()
            }
            files.append(("sources/"+capture.id+"-"+capture.originalName,bytes))
            selected.append(capture)
            sourceBytes += bytes.count
            metadataBytes += meta
        }
        try flush()
        let index = Index(version:1,createdAt:Date(),count:captures.count,parts:parts)
        let indexData = try JSONEncoder().encode(index)
        guard indexData.count <= indexLimit else { throw invalid() }
        // Incomplete exports have no index and cannot be restored as a set.
        let url = folder.appendingPathComponent(indexName)
        try indexData.write(to:url,options:[.atomic])
        guard try read(url,limit:indexLimit) == indexData else { throw invalid() }
        return ExportResult(folder:name,count:captures.count,parts:parts.count)
    }
    static func loadIndex(_ folder: URL) throws -> Index {
        let index = try JSONDecoder().decode(Index.self,from:read(folder.appendingPathComponent(indexName),limit:indexLimit))
        guard index.version == 1, index.count > 0, index.count <= maxCaptures,
              !index.parts.isEmpty, index.parts.count <= index.count else { throw invalid() }
        var count = 0
        for (i,part) in index.parts.enumerated() {
            guard part.name == partName(i), part.count > 0, part.count <= VerifiedBackup.maxSources,
                  part.byteCount > 0, part.byteCount <= VerifiedBackup.maxArchive,
                  part.sha256.utf8.count == 64,
                  part.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw invalid() }
            count += part.count
        }
        guard count == index.count else { throw invalid() }
        return index
    }
    private static func verifyPart(_ part: Part, in folder: URL) throws -> VerifiedBackup {
        let bytes = try read(folder.appendingPathComponent(part.name),limit:VerifiedBackup.maxArchive)
        guard bytes.count == part.byteCount, Vault.hash(bytes) == part.sha256 else { throw invalid() }
        let backup = try VerifiedBackup.inspect(bytes)
        guard backup.captures.count == part.count else { throw invalid() }
        try backup.preflightImages()
        return backup
    }
    static func inspect(_ folder: URL) throws -> Index {
        let index = try loadIndex(folder)
        var ids = Set<String>()
        for part in index.parts {
            let backup = try verifyPart(part,in:folder)
            for capture in backup.captures {
                guard ids.insert(capture.id).inserted else { throw invalid() }
            }
        }
        guard ids.count == index.count else { throw invalid() }
        return index
    }
    struct RestoreResult: Sendable {
        var inserted = 0
        var skipped = 0
        var failed = 0
        var notProcessed = 0
    }
    static func restore(_ folder: URL, to vault: Vault) throws -> RestoreResult {
        let index = try inspect(folder) // Preflight all parts before writing any.
        var result = RestoreResult()
        var processed = 0
        for part in index.parts {
            do {
                let backup = try verifyPart(part,in:folder) // Recheck in case external files changed.
                let report = try backup.restoreNew(to:vault)
                result.inserted += report.inserted
                result.skipped += report.skipped
                result.failed += report.failed
                processed += part.count
            } catch {
                result.notProcessed = index.count-processed
                return result
            }
        }
        return result
    }
}
