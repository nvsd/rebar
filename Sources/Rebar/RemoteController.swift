import AppKit
import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import Network
import Observation
import OSLog

/// The TV Rebar is paired with, remembered between launches.
struct PairedTV: Codable, Equatable {
    /// The Bonjour service name, used to find the TV again if its address changes.
    var serviceName: String
    var displayName: String
    var host: String
}

/// Owns pairing and the connection that carries button presses.
@MainActor
@Observable
final class RemoteController {
    /// The state of the control connection to the paired TV.
    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected
        case unreachable
        case needsPairing
    }

    enum PairingStep: Equatable {
        case choosing
        case connecting(String)
        case enteringCode(String, previousWasWrong: Bool)
        case verifying(String)
        case failed(String)
    }

    let browser = TVBrowser()

    private(set) var pairedTV: PairedTV? {
        didSet { Self.savePairedTV(pairedTV) }
    }
    /// Non-nil while the pairing screen is showing.
    private(set) var pairing: PairingStep?
    private(set) var lastPressed: RemoteButton?
    private(set) var connection: Connection = .disconnected

    var isConnected: Bool { connection == .connected }

    /// A short line for the header under the TV's name.
    var connectionLabel: String {
        switch connection {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .unreachable: "Can't reach TV"
        case .needsPairing: "Pair again to reconnect"
        }
    }

    private var pairingTask: Task<Void, Never>?
    private var codeContinuation: CheckedContinuation<String?, Never>?
    private var connectionTask: Task<Void, Never>?
    private var session: RemoteConnection?
    private var failedAttempts = 0
    private var observers: [NSObjectProtocol] = []
    private let pathMonitor = NWPathMonitor()
    private let log = Logger(subsystem: "com.zacknovosad.rebar", category: "remote")

    init() {
        pairedTV = Self.loadPairedTV()
        watchForWakeAndNetworkChanges()
        connect()
    }

    func press(_ button: RemoteButton) {
        lastPressed = button
        log.debug("Pressed \(button.rawValue, privacy: .public) while \(String(describing: self.connection), privacy: .public)")
        guard let session, connection == .connected else {
            if connection != .connecting { reconnectNow() }
            return
        }
        switch button.action {
        case .key(let code): session.send(.key(code))
        case .openApp(let url): session.send(.openApp(url))
        }
    }

    // MARK: Connection

    /// Starts the connection loop if there's a paired TV and it isn't already running.
    func connect() {
        guard pairedTV != nil, connectionTask == nil else { return }
        connectionTask = Task { await connectionLoop() }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        session = nil
        connection = .disconnected
    }

    /// Drops any current attempt and tries again straight away.
    func reconnectNow() {
        guard pairedTV != nil, connection != .needsPairing else { return }
        disconnect()
        failedAttempts = 0
        connect()
    }

    private func connectionLoop() async {
        while !Task.isCancelled, let tv = pairedTV {
            connection = failedAttempts >= 2 ? .unreachable : .connecting
            do {
                let host = try await hostForNextAttempt(tv)
                let identity = try await ClientIdentity.load()
                let session = RemoteConnection()
                self.session = session
                log.info("Connecting to \(tv.displayName, privacy: .public) at \(host, privacy: .public)")
                try await session.run(host: host, identity: identity) { [weak self] in
                    await self?.didBecomeReady()
                }
            } catch is CancellationError {
                break
            } catch is NIOSSLError where failedAttempts >= 1 && !Task.isCancelled {
                // The TV keeps refusing Rebar's certificate, which happens when it forgets the pairing.
                log.error("TLS refused while connecting; the TV may have forgotten this Mac")
                session = nil
                connection = .needsPairing
                connectionTask = nil
                return
            } catch {
                log.error("Connection to \(tv.displayName, privacy: .public) ended: \(String(reflecting: error), privacy: .public)")
            }
            // A cancelled loop has been replaced by a newer one, so it must not touch shared state.
            if Task.isCancelled { break }
            session = nil
            failedAttempts += 1
            connection = failedAttempts >= 2 ? .unreachable : .connecting
            let delay = min(pow(2, Double(failedAttempts - 1)), 30)
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func didBecomeReady() {
        failedAttempts = 0
        connection = .connected
    }

    /// Uses the saved address first, then asks Bonjour in case the TV's address changed.
    private func hostForNextAttempt(_ tv: PairedTV) async throws -> String {
        guard failedAttempts > 0 else { return tv.host }
        let service = NWEndpoint.service(name: tv.serviceName, type: TVBrowser.serviceType, domain: "local.", interface: nil)
        guard let host = try? await TVBrowser.resolveHost(service) else { return tv.host }
        if host != tv.host {
            log.info("\(tv.displayName, privacy: .public) moved to \(host, privacy: .public)")
            pairedTV?.host = host
        }
        return host
    }

    private func watchForWakeAndNetworkChanges() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconnectNow() }
        })
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self, self.connection == .unreachable else { return }
                self.reconnectNow()
            }
        }
        pathMonitor.start(queue: .main)
    }

    // MARK: Pairing

    func showPairing() {
        pairing = .choosing
        browser.start()
    }

    func pair(with tv: FoundTV) {
        pairingTask?.cancel()
        pairing = .connecting(tv.name)
        pairingTask = Task { await runPairing(serviceName: tv.name) { try await TVBrowser.resolveHost(tv.endpoint) } }
    }

    /// For when the TV doesn't show up in the list.
    func pair(withAddress address: String) {
        let host = address.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        pairingTask?.cancel()
        pairing = .connecting(host)
        pairingTask = Task { await runPairing(serviceName: host) { host } }
    }

    func submitCode(_ code: String) {
        guard case .enteringCode(let name, _) = pairing else { return }
        pairing = .verifying(name)
        codeContinuation?.resume(returning: code)
        codeContinuation = nil
    }

    func cancelPairing() {
        codeContinuation?.resume(returning: nil)
        codeContinuation = nil
        pairingTask?.cancel()
        pairingTask = nil
        browser.stop()
        pairing = nil
    }

    func backToList() {
        codeContinuation?.resume(returning: nil)
        codeContinuation = nil
        pairingTask?.cancel()
        pairing = .choosing
    }

    func forgetTV() {
        disconnect()
        pairedTV = nil
        ClientIdentity.reset()
    }

    private func runPairing(serviceName: String, resolve: () async throws -> String) async {
        var host = "?"
        do {
            host = try await resolve()
            log.info("Pairing with \(serviceName, privacy: .public) at \(host, privacy: .public)")
            let identity = try await ClientIdentity.load()
            let clientName = Host.current().localizedName ?? "Mac"
            let tvName = try await PairingSession.pair(host: host, identity: identity, clientName: clientName) { [weak self] previousWasWrong in
                await self?.waitForCode(name: serviceName, previousWasWrong: previousWasWrong)
            }
            disconnect()
            pairedTV = PairedTV(serviceName: serviceName, displayName: tvName ?? serviceName, host: host)
            failedAttempts = 0
            connect()
            log.info("Paired with \(serviceName, privacy: .public) at \(host, privacy: .public)")
            pairing = nil
            browser.stop()
        } catch PairingSession.PairingError.cancelled {
            return
        } catch is CancellationError {
            return
        } catch {
            log.error("Pairing with \(serviceName, privacy: .public) at \(host, privacy: .public) failed: \(String(reflecting: error), privacy: .public)")
            if pairing != nil { pairing = .failed(Self.describe(error, tvName: serviceName)) }
        }
    }

    /// Turns low-level network errors into something a person can act on.
    private static func describe(_ error: Error, tvName: String) -> String {
        switch error {
        case is NIOConnectionError, is ChannelError, is IOError, is NWError, is TVBrowser.ResolveError, is TLSConnection.ConnectionError:
            "Couldn't reach \(tvName). Make sure it's turned on and connected to the same network as this Mac."
        case is NIOSSLError:
            "\(tvName) refused the secure connection. Try again, and if it keeps happening, restart the TV."
        default:
            error.localizedDescription
        }
    }

    private func waitForCode(name: String, previousWasWrong: Bool) async -> String? {
        await withCheckedContinuation { continuation in
            codeContinuation = continuation
            pairing = .enteringCode(name, previousWasWrong: previousWasWrong)
        }
    }

    // MARK: Persistence

    private static let pairedTVKey = "pairedTV"

    private static func loadPairedTV() -> PairedTV? {
        UserDefaults.standard.data(forKey: pairedTVKey).flatMap { try? JSONDecoder().decode(PairedTV.self, from: $0) }
    }

    private static func savePairedTV(_ tv: PairedTV?) {
        if let tv, let data = try? JSONEncoder().encode(tv) {
            UserDefaults.standard.set(data, forKey: pairedTVKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pairedTVKey)
        }
    }
}
