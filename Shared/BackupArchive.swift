import Foundation

enum BackupArchive {
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return crc ^ 0xffffffff
    }
    static func zip(_ files: [(String, Data)]) throws -> Data {
        guard files.count < 100 else { throw NativeError.message("בחר פחות מקורות.") }
        var local = Data(), central = Data()
        for (name, bytes) in files {
            let filename = Data(name.utf8)
            guard filename.count < 65536, bytes.count < 32 * 1024 * 1024 else {
                throw NativeError.message("הייצוא גדול מדי. בחר פחות צילומים.")
            }
            let offset = UInt32(local.count), crc = crc32(bytes), size = UInt32(bytes.count)
            local.le32(0x04034b50); local.le16(20); local.le16(0x800); local.le16(0)
            local.le16(0); local.le16(33); local.le32(crc); local.le32(size); local.le32(size)
            local.le16(UInt16(filename.count)); local.le16(0); local.append(filename); local.append(bytes)
            central.le32(0x02014b50); central.le16(20); central.le16(20); central.le16(0x800)
            central.le16(0); central.le16(0); central.le16(33); central.le32(crc); central.le32(size)
            central.le32(size); central.le16(UInt16(filename.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(0); central.le32(offset); central.append(filename)
        }
        let offset = UInt32(local.count)
        local.append(central)
        local.le32(0x06054b50); local.le16(0); local.le16(0)
        local.le16(UInt16(files.count)); local.le16(UInt16(files.count))
        local.le32(UInt32(central.count)); local.le32(offset); local.le16(0)
        return local
    }
}
private extension Data {
    mutating func le16(_ value: UInt16) { var n = value.littleEndian; Swift.withUnsafeBytes(of: &n) { append(contentsOf: $0) } }
    mutating func le32(_ value: UInt32) { var n = value.littleEndian; Swift.withUnsafeBytes(of: &n) { append(contentsOf: $0) } }
}
