import SwiftUI

/// Walks through choosing a TV and typing the code it shows.
struct PairingView: View {
    @Environment(RemoteController.self) private var remote
    let step: RemoteController.PairingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch step {
            case .choosing:
                ChooseTV()
            case .connecting(let name):
                ProgressView("Connecting to \(name)…").frame(maxWidth: .infinity)
                cancel
            case .enteringCode(let name, let previousWasWrong):
                EnterCode(name: name, previousWasWrong: previousWasWrong)
            case .verifying(let name):
                ProgressView("Pairing with \(name)…").frame(maxWidth: .infinity)
                cancel
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Pair", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { remote.backToList() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                cancel
            }
        }
    }

    private var cancel: some View {
        Button("Cancel") { remote.cancelPairing() }
            .keyboardShortcut(.cancelAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ChooseTV: View {
    @Environment(RemoteController.self) private var remote
    @State private var address = ""

    var body: some View {
        Text("Choose your Google TV. It needs to be on the same network as this Mac.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        List(remote.browser.tvs) { tv in
            Button { remote.pair(with: tv) } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(tv.name)
                        if let address = remote.browser.addresses[tv.name], !address.isEmpty {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if remote.pairedTV?.serviceName == tv.name {
                        Image(systemName: "checkmark").accessibilityLabel("Paired")
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 140)
        .overlay {
            if remote.browser.tvs.isEmpty {
                ProgressView("Looking for TVs…")
            }
        }

        HStack {
            TextField("Or enter an IP address", text: $address)
                .onSubmit { remote.pair(withAddress: address) }
            Button("Pair") { remote.pair(withAddress: address) }
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        Button("Cancel") { remote.cancelPairing() }
            .keyboardShortcut(.cancelAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct EnterCode: View {
    @Environment(RemoteController.self) private var remote
    let name: String
    let previousWasWrong: Bool
    @State private var code = ""

    var body: some View {
        Text("Type the 6-character code showing on \(name).")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        TextField("Code", text: $code)
            .font(.title2.monospaced())
            .multilineTextAlignment(.center)
            .onChange(of: code) { _, newValue in
                let cleaned = String(newValue.uppercased().filter(\.isHexDigit).prefix(6))
                if cleaned != newValue { code = cleaned }
            }
            .onSubmit { if code.count == 6 { remote.submitCode(code) } }

        if previousWasWrong {
            Label("That code doesn't match. Check the TV and try again.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }

        HStack {
            Button("Back") { remote.backToList() }
            Spacer()
            Button("Pair") { remote.submitCode(code) }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(code.count != 6)
        }
    }
}
