import Foundation

// Strict reader for the exact stored ZIP format emitted by BackupArchive.
// Never extracts files, follows paths, or writes to the vault.
struct VerifiedBackup: Sendable {
    let captures: [Capture]
    let sourceBytes: Int
    private let sources: [String: Data]

    static let maxArchive = 40 * 1024 * 1024
    static let maxSources = 20
    static let maxSourceBytes = 32 * 1024 * 1024
    static let maxManifest = 4 * 1024 * 1024

    private static func invalid() -> NativeError {
        .message("קובץ הגיבוי אינו תקין או אינו נתמך. לא בוצע שינוי בספרייה.")
    }

    static func inspect(_ data: Data) throws -> VerifiedBackup {
        guard data.count <= maxArchive, data.count >= 22 else { throw invalid() }
        // Normalize indices in case a Data slice was supplied.
        let data = Data(data)
        func u16(_ i: Int) throws -> Int {
            guard i >= 0, i <= data.count - 2 else { throw invalid() }
            return Int(data[i]) | Int(data[i+1]) << 8
        }
        func u32(_ i: Int) throws -> UInt32 {
            guard i >= 0, i <= data.count - 4 else { throw invalid() }
            return UInt32(data[i]) | UInt32(data[i+1]) << 8 |
                   UInt32(data[i+2]) << 16 | UInt32(data[i+3]) << 24
        }
        let eocd = data.count - 22
        guard try u32(eocd) == 0x06054b50,
              try u16(eocd+4) == 0, try u16(eocd+6) == 0,
              try u16(eocd+20) == 0 else { throw invalid() }
        let count = try u16(eocd+10)
        let central = Int(try u32(eocd+16))
        let centralSize = Int(try u32(eocd+12))
        guard count >= 3, count <= maxSources+2,
              try u16(eocd+8) == count,
              central <= eocd, centralSize == eocd-central else { throw invalid() }
        var cursor = 0
        var entries: [(String, Data)] = []
        var names = Set<String>()
        var total = 0
        for _ in 0..<count {
            guard cursor <= central-30, try u32(cursor) == 0x04034b50,
                  try u16(cursor+6) == 0x800, try u16(cursor+8) == 0,
                  try u16(cursor+28) == 0 else { throw invalid() }
            let size = Int(try u32(cursor+18))
            let nameLength = try u16(cursor+26)
            let start = cursor+30
            guard nameLength > 0, nameLength <= 2048, nameLength <= central-start,
                  Int(try u32(cursor+22)) == size else { throw invalid() }
            let bodyStart = start+nameLength
            guard size <= central-bodyStart,
                  let name = String(data: data.subdata(in:start..<bodyStart),encoding:.utf8),
                  !name.contains("\0"), names.insert(name).inserted else { throw invalid() }
            if name == "manifest.json" {
                guard size <= maxManifest else { throw invalid() }
            } else if name == "README.txt" {
                guard size <= 8192 else { throw invalid() }
            } else {
                guard name.hasPrefix("sources/"), size > 0,
                      size <= 24*1024*1024 else { throw invalid() }
                total += size
                guard total <= maxSourceBytes else { throw invalid() }
            }
            let bytes = data.subdata(in:bodyStart..<(bodyStart+size))
            guard BackupArchive.crc32(bytes) == (try u32(cursor+14)) else { throw invalid() }
            entries.append((name,bytes))
            cursor = bodyStart+size
        }
        // Canonical byte-for-byte match checks the entire central directory,
        // headers, offsets, sizes and flags; rejects alternate ZIP variants.
        guard cursor == central, try BackupArchive.zip(entries) == data else { throw invalid() }
        let files = Dictionary(uniqueKeysWithValues: entries)
        guard let manifest = files["manifest.json"], files["README.txt"] != nil,
              let captures = try? JSONDecoder().decode([Capture].self,from:manifest),
              !captures.isEmpty, captures.count <= maxSources,
              captures.count+2 == entries.count else { throw invalid() }
        var ids = Set<String>()
        var sources: [String: Data] = [:]
        for capture in captures {
            guard capture.id.utf8.count == 64,
                  capture.id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  ids.insert(capture.id).inserted,
                  !capture.originalName.isEmpty,
                  !capture.originalName.contains("/"), !capture.originalName.contains("\\"),
                  !capture.originalName.contains("\0"),
                  let bytes = files["sources/"+capture.id+"-"+capture.originalName],
                  Vault.hash(bytes) == capture.id else { throw invalid() }
            sources[capture.id] = bytes
        }
        return VerifiedBackup(captures:captures,sourceBytes:total,sources:sources)
    }

    struct RestoreReport: Sendable {
        var inserted = 0
        var skipped = 0
        var failed = 0
    }
    func preflightImages() throws {
        // Preflight every source before making any changes.
        for capture in captures {
            guard let bytes = sources[capture.id] else { throw Self.invalid() }
            try Vault.validateSourceImage(bytes)
        }
    }
    func restoreNew(to vault: Vault) throws -> RestoreReport {
        try preflightImages()
        var report = RestoreReport()
        for capture in captures {
            guard let bytes = sources[capture.id] else { throw Self.invalid() }
            do {
                if try vault.restoreNewCapture(capture, data: bytes) { report.inserted += 1 }
                else { report.skipped += 1 }
            } catch { report.failed += 1 }
        }
        return report
    }

    struct Comparison: Sendable {
        let newCount: Int
        let identicalCount: Int
        let conflictCount: Int
    }
    func compare(with existing: [Capture]) -> Comparison {
        var byID: [String:Capture] = [:]
        for capture in existing { byID[capture.id] = capture }
        var newCount=0, identicalCount=0, conflictCount=0
        for capture in captures {
            if let current=byID[capture.id] {
                if current == capture { identicalCount += 1 } else { conflictCount += 1 }
            } else { newCount += 1 }
        }
        return Comparison(newCount:newCount,identicalCount:identicalCount,conflictCount:conflictCount)
    }
}
