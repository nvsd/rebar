import Foundation

/// Pairs with a Google TV using the "polo" protocol on port 6467.
/// Message layouts follow polo.proto from Google's google-tv-pairing-protocol.
enum PairingSession {
    static let port = 6467

    enum PairingError: LocalizedError {
        case rejected(status: Int)
        case unexpectedReply
        case missingServerCertificate
        case cancelled

        var errorDescription: String? {
            switch self {
            case .rejected(402): "The TV didn't accept that code."
            case .rejected(let status): "The TV refused to pair (status \(status))."
            case .unexpectedReply: "The TV replied with something Rebar didn't expect."
            case .missingServerCertificate: "The TV didn't send its certificate."
            case .cancelled: "Pairing was cancelled."
            }
        }
    }

    // OuterMessage fields
    private enum Field {
        static let protocolVersion = 1, status = 2
        static let pairingRequest = 10, pairingRequestAck = 11
        static let options = 20, configuration = 30, configurationAck = 31
        static let secret = 40, secretAck = 41
    }

    private static let statusOK = 200
    private static let encodingHexadecimal = 3
    private static let roleInput = 1
    private static let codeLength = 6

    /// Runs the whole exchange. The TV shows a code once `askForCode` is called;
    /// `askForCode` gets `true` when the previous code didn't match, and returns nil to cancel.
    /// Returns the name the TV gives itself.
    static func pair(
        host: String,
        identity: ClientIdentity,
        clientName: String,
        askForCode: @escaping (_ previousWasWrong: Bool) async -> String?
    ) async throws -> String? {
        try await TLSConnection.with(host: host, port: port, identity: identity) { connection in
            try await connection.send(outer { message in
                message.message(Field.pairingRequest) { request in
                    request.string(1, "atvremote")
                    request.string(2, clientName)
                }
            })
            let ack = try await receive(from: connection, expecting: Field.pairingRequestAck)
            let serverName = ack.message(Field.pairingRequestAck)?.string(1)

            try await connection.send(outer { message in
                message.message(Field.options) { options in
                    options.message(1) { encoding in
                        encoding.int(1, encodingHexadecimal)
                        encoding.int(2, codeLength)
                    }
                    options.int(3, roleInput)
                }
            })
            _ = try await receive(from: connection, expecting: Field.options)

            try await connection.send(outer { message in
                message.message(Field.configuration) { configuration in
                    configuration.message(1) { encoding in
                        encoding.int(1, encodingHexadecimal)
                        encoding.int(2, codeLength)
                    }
                    configuration.int(2, roleInput)
                }
            })
            _ = try await receive(from: connection, expecting: Field.configurationAck)

            // The TV is now showing the code.
            let client = try RSAPublicNumbers(certificateDER: try identity.certificateDER)
            guard let serverDER = connection.peerCertificateDER else { throw PairingError.missingServerCertificate }
            let server = try RSAPublicNumbers(certificateDER: serverDER)

            var previousWasWrong = false
            while true {
                guard let code = await askForCode(previousWasWrong) else { throw PairingError.cancelled }
                guard let secret = PairingSecret.compute(code: code, client: client, server: server) else {
                    previousWasWrong = true
                    continue
                }
                try await connection.send(outer { message in
                    message.message(Field.secret) { $0.bytes(1, secret) }
                })
                _ = try await receive(from: connection, expecting: Field.secretAck)
                return serverName
            }
        }
    }

    private static func outer(_ build: (inout ProtoWriter) -> Void) -> Data {
        var writer = ProtoWriter()
        writer.int(Field.protocolVersion, 2)
        writer.int(Field.status, statusOK)
        build(&writer)
        return writer.data
    }

    private static func receive(from connection: TLSConnection, expecting field: Int) async throws -> ProtoMessage {
        let message = try await connection.receive()
        let status = message.int(Field.status) ?? 0
        guard status == statusOK else { throw PairingError.rejected(status: status) }
        guard message.has(field) else { throw PairingError.unexpectedReply }
        return message
    }
}
