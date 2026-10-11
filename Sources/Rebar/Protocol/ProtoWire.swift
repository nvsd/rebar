import Foundation

/// Just enough protobuf to speak the Android TV Remote protocol without generated code.
struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ field: Int, _ value: UInt64) {
        tag(field, wireType: 0)
        Self.appendVarint(value, to: &data)
    }

    mutating func int(_ field: Int, _ value: Int) {
        varint(field, UInt64(bitPattern: Int64(value)))
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, wireType: 2)
        Self.appendVarint(UInt64(value.count), to: &data)
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Data(value.utf8))
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        bytes(field, nested.data)
    }

    private mutating func tag(_ field: Int, wireType: UInt64) {
        Self.appendVarint(UInt64(field) << 3 | wireType, to: &data)
    }

    static func appendVarint(_ value: UInt64, to data: inout Data) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }
}

enum ProtoError: Error {
    case truncated
    case unsupportedWireType(Int)
}

/// Decoded fields of one message. Repeated fields keep every value in order.
struct ProtoMessage {
    enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    private(set) var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        var reader = ByteReader(data)
        while !reader.isAtEnd {
            let key = try reader.varint()
            let field = Int(key >> 3)
            switch key & 7 {
            case 0: fields[field, default: []].append(.varint(try reader.varint()))
            case 1: fields[field, default: []].append(.bytes(try reader.take(8)))
            case 2: fields[field, default: []].append(.bytes(try reader.take(Int(try reader.varint()))))
            case 5: fields[field, default: []].append(.bytes(try reader.take(4)))
            case let other: throw ProtoError.unsupportedWireType(Int(other))
            }
        }
    }

    func has(_ field: Int) -> Bool { fields[field] != nil }

    func int(_ field: Int) -> Int? {
        guard case .varint(let v)? = fields[field]?.last else { return nil }
        return Int(truncatingIfNeeded: Int64(bitPattern: v))
    }

    func bytes(_ field: Int) -> Data? {
        guard case .bytes(let d)? = fields[field]?.last else { return nil }
        return d
    }

    func string(_ field: Int) -> String? {
        bytes(field).flatMap { String(data: $0, encoding: .utf8) }
    }

    func message(_ field: Int) -> ProtoMessage? {
        bytes(field).flatMap { try? ProtoMessage($0) }
    }
}

struct ByteReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var isAtEnd: Bool { offset >= data.endIndex }
    var position: Int { offset - data.startIndex }

    mutating func byte() throws -> UInt8 {
        guard offset < data.endIndex else { throw ProtoError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.endIndex else { throw ProtoError.truncated }
        defer { offset += count }
        return data.subdata(in: offset..<offset + count)
    }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let b = try byte()
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { throw ProtoError.truncated }
        }
    }
}

/// Splits a byte stream into varint-length-prefixed frames.
struct FrameBuffer {
    private var pending = Data()

    mutating func append(_ bytes: Data) { pending.append(bytes) }

    /// Returns the next complete frame, or nil if more bytes are needed.
    mutating func next() -> Data? {
        var reader = ByteReader(pending)
        guard let length = try? reader.varint() else { return nil }
        let headerSize = reader.position
        guard pending.count - headerSize >= Int(length) else { return nil }
        let start = pending.startIndex + headerSize
        let frame = pending.subdata(in: start..<start + Int(length))
        pending = pending.subdata(in: start + Int(length)..<pending.endIndex)
        return frame
    }

    static func frame(_ message: Data) -> Data {
        var out = Data()
        ProtoWriter.appendVarint(UInt64(message.count), to: &out)
        out.append(message)
        return out
    }
}
