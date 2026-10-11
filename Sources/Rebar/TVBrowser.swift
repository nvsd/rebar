import Foundation
import Network
import Observation

/// A Google TV found on the local network.
struct FoundTV: Identifiable, Hashable {
    let name: String
    let endpoint: NWEndpoint
    var id: String { name }
}

/// Watches the network for Google TVs advertising the remote service.
@MainActor
@Observable
final class TVBrowser {
    static let serviceType = "_androidtvremote2._tcp"

    private(set) var tvs: [FoundTV] = [] {
        didSet { resolveNewAddresses() }
    }
    /// Each found TV's address by name, filled in as they resolve, so the list can tell TVs apart.
    private(set) var addresses: [String: String] = [:]
    private(set) var isBrowsing = false
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> FoundTV? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return FoundTV(name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in self?.tvs = found.sorted { $0.name < $1.name } }
        }
        browser.start(queue: .main)
        self.browser = browser
        isBrowsing = true
    }

    private func resolveNewAddresses() {
        for tv in tvs where addresses[tv.name] == nil {
            addresses[tv.name] = ""
            Task {
                let host = try? await Self.resolveHost(tv.endpoint)
                addresses[tv.name] = host ?? ""
            }
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    /// Looks up the IPv4 address behind a Bonjour service.
    nonisolated static func resolveHost(_ endpoint: NWEndpoint) async throws -> String {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        defer { connection.cancel() }

        return try await withTimeout(.seconds(5)) {
            try await withCheckedThrowingContinuation { continuation in
                let resumed = ResumeOnce()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint,
                           let address = Self.address(of: host) {
                            resumed.run { continuation.resume(returning: address) }
                        } else {
                            resumed.run { continuation.resume(throwing: ResolveError.noAddress) }
                        }
                    case .failed(let error), .waiting(let error):
                        resumed.run { continuation.resume(throwing: error) }
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
            }
        }
    }

    /// Formats an address the way a socket API expects it. The descriptions Network gives
    /// can carry an interface suffix such as "%en0", which plain sockets can't connect to.
    nonisolated static func address(of host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let address):
            return address.rawValue.map(String.init).joined(separator: ".")
        case .ipv6(let address):
            var bytes = [UInt8](address.rawValue)
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &bytes, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            return String(cString: buffer)
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    }

    enum ResolveError: LocalizedError {
        case noAddress
        var errorDescription: String? { "Couldn't find the TV's address." }
    }
}

/// Guards a continuation so it's resumed exactly once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
