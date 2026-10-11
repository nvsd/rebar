import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import NIOSSL

/// A TLS connection to the TV that sends and receives length-prefixed protobuf messages.
/// The TV uses a self-signed certificate, so any certificate is accepted and kept for pairing.
final class TLSConnection {
    enum ConnectionError: LocalizedError {
        case closed
        case timedOut

        var errorDescription: String? {
            switch self {
            case .closed: "The TV closed the connection."
            case .timedOut: "The TV stopped responding."
            }
        }
    }

    /// The TV's certificate, in DER form, once the handshake is done.
    var peerCertificateDER: [UInt8]? { peerCertificate.withLockedValue { $0 } }

    private let peerCertificate: NIOLockedValueBox<[UInt8]?>
    private var inbound: NIOAsyncChannelInboundStream<ByteBuffer>.AsyncIterator
    private let outbound: NIOAsyncChannelOutboundWriter<ByteBuffer>
    private var frames = FrameBuffer()

    private init(
        inbound: NIOAsyncChannelInboundStream<ByteBuffer>,
        outbound: NIOAsyncChannelOutboundWriter<ByteBuffer>,
        peerCertificate: NIOLockedValueBox<[UInt8]?>
    ) {
        self.inbound = inbound.makeAsyncIterator()
        self.outbound = outbound
        self.peerCertificate = peerCertificate
    }

    /// Opens a connection, runs `body`, and closes the connection when `body` returns or throws.
    static func with<Result>(
        host: String,
        port: Int,
        identity: ClientIdentity,
        _ body: (TLSConnection) async throws -> Result
    ) async throws -> Result {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = .noHostnameVerification
        tls.certificateChain = [.certificate(try NIOSSLCertificate(bytes: Array(identity.certificatePEM.utf8), format: .pem))]
        tls.privateKey = .privateKey(try NIOSSLPrivateKey(bytes: Array(identity.privateKeyPEM.utf8), format: .pem))
        let context = try NIOSSLContext(configuration: tls)
        let peerCertificate = NIOLockedValueBox<[UInt8]?>(nil)

        let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connectTimeout(.seconds(5))
            .connect(host: host, port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    let handler = try NIOSSLClientHandler(
                        context: context,
                        serverHostname: nil,
                        customVerificationCallback: { certificates, promise in
                            peerCertificate.withLockedValue { $0 = try? certificates.first?.toDERBytes() }
                            promise.succeed(.certificateVerified)
                        }
                    )
                    try channel.pipeline.syncOperations.addHandler(handler)
                    return try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
                }
            }

        return try await channel.executeThenClose { inbound, outbound in
            let connection = TLSConnection(inbound: inbound, outbound: outbound, peerCertificate: peerCertificate)
            return try await body(connection)
        }
    }

    func send(_ message: Data) async throws {
        try await outbound.write(ByteBuffer(bytes: FrameBuffer.frame(message)))
    }

    /// Waits for the next whole message.
    func receive(timeout: Duration = .seconds(10)) async throws -> ProtoMessage {
        while true {
            if let frame = frames.next() { return try ProtoMessage(frame) }
            let chunk = try await withTimeout(timeout) { [self] in try await self.nextChunk() }
            frames.append(chunk)
        }
    }

    private func nextChunk() async throws -> Data {
        guard let buffer = try await inbound.next() else { throw ConnectionError.closed }
        return Data(buffer.readableBytesView)
    }
}

/// Runs `operation`, throwing `TLSConnection.ConnectionError.timedOut` if it takes longer than `timeout`.
func withTimeout<T>(_ timeout: Duration, _ operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TLSConnection.ConnectionError.timedOut
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
