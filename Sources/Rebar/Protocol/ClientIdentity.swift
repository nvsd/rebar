import _CryptoExtras
import Foundation
import NIOSSL
import Security
import SwiftASN1
import X509

/// Rebar's own certificate and key. The TV remembers this certificate when you pair,
/// so it's created once and kept in the Keychain.
struct ClientIdentity: Codable, Sendable {
    let certificatePEM: String
    let privateKeyPEM: String

    var certificateDER: [UInt8] {
        get throws {
            try NIOSSLCertificate(bytes: Array(certificatePEM.utf8), format: .pem).toDERBytes()
        }
    }

    /// `loadOrCreate` off the main actor. A Keychain access prompt blocks the calling thread
    /// until it's answered, and on the main thread that would freeze the panel.
    static func load() async throws -> ClientIdentity {
        try await Task.detached { try loadOrCreate() }.value
    }

    /// Loads the saved identity, creating and saving one the first time.
    static func loadOrCreate() throws -> ClientIdentity {
        if let saved = try Keychain.load() { return saved }
        let identity = try generate()
        try Keychain.save(identity)
        return identity
    }

    static func generate() throws -> ClientIdentity {
        let rsa = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let key = Certificate.PrivateKey(rsa)
        let name = try DistinguishedName { CommonName("Rebar") }
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: key.publicKey,
            notValidBefore: now.addingTimeInterval(-24 * 60 * 60),
            notValidAfter: now.addingTimeInterval(10 * 365 * 24 * 60 * 60),
            issuer: name,
            subject: name,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: Certificate.Extensions(),
            issuerPrivateKey: key
        )
        return ClientIdentity(
            certificatePEM: try certificate.serializeAsPEM().pemString,
            privateKeyPEM: rsa.pemRepresentation
        )
    }

    /// Forgets the identity, so the next pairing starts fresh.
    static func reset() { Keychain.delete() }

    private enum Keychain {
        static let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.zacknovosad.rebar",
            kSecAttrAccount as String: "client-identity",
        ]

        static func load() throws -> ClientIdentity? {
            var item: CFTypeRef?
            var search = query
            search[kSecReturnData as String] = true
            let status = SecItemCopyMatching(search as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = item as? Data else {
                throw KeychainError(status: status)
            }
            return try JSONDecoder().decode(ClientIdentity.self, from: data)
        }

        static func save(_ identity: ClientIdentity) throws {
            delete()
            var item = query
            item[kSecValueData as String] = try JSONEncoder().encode(identity)
            item[kSecAttrLabel as String] = "Rebar pairing certificate"
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        }

        static func delete() {
            SecItemDelete(query as CFDictionary)
        }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain error: \(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)")"
        }
    }
}
