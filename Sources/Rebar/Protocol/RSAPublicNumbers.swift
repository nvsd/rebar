import Crypto
import Foundation

/// The modulus and public exponent of an RSA certificate, as minimal big-endian bytes.
struct RSAPublicNumbers: Equatable {
    let modulus: Data
    let exponent: Data

    enum ParseError: Error { case malformed }

    /// Reads the public key out of a DER-encoded X.509 certificate.
    init(certificateDER: some Collection<UInt8>) throws {
        var outer = DERReader(Data(certificateDER))
        var certificate = try outer.read(tag: 0x30).children()
        var tbs = try certificate.read(tag: 0x30).children()
        if tbs.peekTag == 0xA0 { _ = try tbs.read() }   // [0] version
        for _ in 0..<5 { _ = try tbs.read() }           // serial, signature, issuer, validity, subject
        var spki = try tbs.read(tag: 0x30).children()
        _ = try spki.read(tag: 0x30)                     // algorithm
        let bitString = try spki.read(tag: 0x03).content
        guard bitString.first == 0 else { throw ParseError.malformed }
        var rsaKey = DERReader(bitString.dropFirst())
        var numbers = try rsaKey.read(tag: 0x30).children()
        modulus = Self.trimmed(try numbers.read(tag: 0x02).content)
        exponent = Self.trimmed(try numbers.read(tag: 0x02).content)
    }

    private static func trimmed(_ bytes: Data) -> Data {
        let trimmed = bytes.drop(while: { $0 == 0 })
        return trimmed.isEmpty ? Data([0]) : Data(trimmed)
    }
}

/// The secret sent to the TV to finish pairing.
enum PairingSecret {
    /// Returns nil when `code` isn't six hex digits or doesn't match the two certificates,
    /// which means it was mistyped.
    static func compute(code: String, client: RSAPublicNumbers, server: RSAPublicNumbers) -> Data? {
        let code = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 6, let bytes = Data(hex: code) else { return nil }

        var hash = SHA256()
        hash.update(data: client.modulus)
        hash.update(data: client.exponent)
        hash.update(data: server.modulus)
        hash.update(data: server.exponent)
        hash.update(data: bytes.dropFirst())
        let digest = Data(hash.finalize())

        return digest.first == bytes.first ? digest : nil
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

/// Minimal DER walker: enough to find an RSA key inside a certificate.
struct DERReader {
    struct Element {
        let tag: UInt8
        let content: Data
        func children() -> DERReader { DERReader(content) }
    }

    private var bytes: ByteReader

    init(_ data: Data) { bytes = ByteReader(Data(data)) }

    var peekTag: UInt8? {
        var copy = bytes
        return try? copy.byte()
    }

    mutating func read() throws -> Element {
        let tag = try bytes.byte()
        let first = try bytes.byte()
        var length = Int(first)
        if first & 0x80 != 0 {
            let count = Int(first & 0x7F)
            guard (1...4).contains(count) else { throw RSAPublicNumbers.ParseError.malformed }
            length = 0
            for _ in 0..<count { length = length << 8 | Int(try bytes.byte()) }
        }
        return Element(tag: tag, content: try bytes.take(length))
    }

    mutating func read(tag: UInt8) throws -> Element {
        let element = try read()
        guard element.tag == tag else { throw RSAPublicNumbers.ParseError.malformed }
        return element
    }
}
