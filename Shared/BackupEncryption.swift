import Foundation
import CryptoKit

// A random 256-bit recovery key, not a user password. No network or key escrow.
// Callers must present and confirm safe storage of the recovery key before export.
struct BackupEncryption: Sendable {
    private let key: SymmetricKey
    private static let magic = Data("SMENC001".utf8)
    static let overhead = 8 + 12 + 16

    private init(key: SymmetricKey) { self.key = key }

    static func generate() -> BackupEncryption {
        BackupEncryption(key: SymmetricKey(size: .bits256))
    }

    var recoveryCode: String {
        key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    init(recoveryCode: String) throws {
        guard recoveryCode.utf8.count == 44,
              let bytes = Data(base64Encoded: recoveryCode), bytes.count == 32,
              bytes.base64EncodedString() == recoveryCode else {
            throw NativeError.message("מפתח השחזור אינו תקין.")
        }
        key = SymmetricKey(data: bytes)
    }

    private func aad(_ name: String) -> Data {
        Self.magic + Data(("ScreenMind backup v1:" + name).utf8)
    }

    func seal(_ plaintext: Data, name: String) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: aad(name))
        guard let combined = box.combined else {
            throw NativeError.message("הצפנת הגיבוי נכשלה.")
        }
        return Self.magic + combined
    }

    func open(_ encrypted: Data, name: String) throws -> Data {
        guard encrypted.count >= Self.overhead,
              encrypted.prefix(Self.magic.count) == Self.magic else {
            throw NativeError.message("פורמט גיבוי מוצפן אינו תקין.")
        }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(encrypted.dropFirst(Self.magic.count)))
            return try AES.GCM.open(box, using: key, authenticating: aad(name))
        } catch {
            throw NativeError.message("לא ניתן לפתוח את הגיבוי: מפתח שגוי או קובץ פגום.")
        }
    }
}
