import Foundation
import NIOConcurrencyHelpers
import OSLog

/// Something to send to the TV.
enum RemoteCommand: Sendable {
    case key(Int32)
    case openApp(URL)
}

/// One control session with the TV on port 6466. Create a new one for every connection attempt.
/// Message layouts follow remotemessage.proto from the androidtvremote2 project.
final class RemoteConnection: Sendable {
    static let port = 6466

    /// Keys, IME, voice, power, volume and app links: the 622 that androidtvremote2 sends.
    /// The TV ignores key presses when this doesn't match what it expects.
    private static let features = 2 | 4 | 8 | 32 | 64 | 512

    // RemoteMessage fields
    private enum Field {
        static let configure = 1, setActive = 2, error = 3
        static let pingRequest = 8, pingResponse = 9
        static let keyInject = 10, start = 40, appLink = 90
    }

    private static let directionShort = 3

    private let commands: AsyncStream<RemoteCommand>
    private let continuation: AsyncStream<RemoteCommand>.Continuation
    private let log = Logger(subsystem: "com.zacknovosad.rebar", category: "connection")

    /// The TV pings every few seconds but stops while keys are arriving, so traffic either way counts as alive.
    private static let idleLimit: Duration = .seconds(16)
    private let lastActivity = NIOLockedValueBox(ContinuousClock.now)

    init() {
        (commands, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(32))
    }

    func send(_ command: RemoteCommand) {
        continuation.yield(command)
    }

    /// Connects and stays connected until the TV goes away or the task is cancelled.
    /// `onReady` runs once the TV says the remote is active.
    func run(host: String, identity: ClientIdentity, onReady: @escaping @Sendable () async -> Void) async throws {
        defer { continuation.finish() }
        try await TLSConnection.with(host: host, port: Self.port, identity: identity) { connection in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.handleIncoming(on: connection, onReady: onReady) }
                group.addTask { try await self.watchForSilence() }
                group.addTask {
                    for await command in self.commands {
                        try await connection.send(Self.encode(command))
                        self.markActive()
                        self.log.debug("Sent \(String(describing: command), privacy: .public)")
                    }
                }
                // Whichever side stops first ends the session.
                _ = try await group.next()
                group.cancelAll()
            }
        }
    }

    private func handleIncoming(on connection: TLSConnection, onReady: @escaping @Sendable () async -> Void) async throws {
        while true {
            // watchForSilence decides when the TV has gone away, so this just waits.
            let message = try await connection.receive(timeout: .seconds(86_400))
            markActive()
            log.debug("Received \(message.fields.keys.sorted(), privacy: .public)")
            var reply = ProtoWriter()

            if message.has(Field.configure) {
                log.debug("TV offered features \(message.message(Field.configure)?.int(1) ?? -1, privacy: .public)")
                reply.message(Field.configure) { configure in
                    configure.int(1, Self.features)
                    configure.message(2) { info in
                        info.int(3, 1)
                        info.string(4, "1")
                        info.string(5, "atvremote")
                        info.string(6, "1.0.0")
                    }
                }
            } else if message.has(Field.setActive) {
                reply.message(Field.setActive) { $0.int(1, Self.features) }
            } else if let ping = message.message(Field.pingRequest) {
                reply.message(Field.pingResponse) { $0.int(1, ping.int(1) ?? 0) }
            } else if message.has(Field.start) {
                log.info("Remote is active")
                await onReady()
            } else if message.has(Field.error) {
                log.error("The TV reported an error")
            } else {
                log.debug("Unhandled message: \(message.fields.keys.sorted(), privacy: .public)")
            }

            if !reply.data.isEmpty {
                try await connection.send(reply.data)
            }
        }
    }

    private func markActive() {
        lastActivity.withLockedValue { $0 = .now }
    }

    /// Ends the session once nothing has gone either way for `idleLimit`.
    private func watchForSilence() async throws {
        while true {
            let deadline = lastActivity.withLockedValue { $0 } + Self.idleLimit
            if ContinuousClock.now >= deadline { throw TLSConnection.ConnectionError.timedOut }
            try await Task.sleep(until: deadline)
        }
    }

    static func encode(_ command: RemoteCommand) -> Data {
        var message = ProtoWriter()
        switch command {
        case .key(let code):
            message.message(Field.keyInject) { key in
                key.int(1, Int(code))
                key.int(2, directionShort)
            }
        case .openApp(let url):
            message.message(Field.appLink) { $0.string(1, url.absoluteString) }
        }
        return message.data
    }
}
