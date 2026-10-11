import ServiceManagement
import SwiftUI

/// The menu bar panel, built from stock controls only.
struct RemoteView: View {
    @Environment(RemoteController.self) private var remote

    var body: some View {
        Group {
            if let step = remote.pairing {
                PairingView(step: step)
            } else if remote.pairedTV == nil {
                ContentUnavailableView {
                    Label("No TV Paired", systemImage: "tv")
                } description: {
                    Text("Pair Rebar with your Google TV to control it from the menu bar.")
                } actions: {
                    Button("Pair with TV…") { remote.showPairing() }
                        .buttonStyle(.glassProminent)
                }
                .overlay(alignment: .topTrailing) { MoreMenu() }
            } else {
                Controls()
            }
        }
        .padding()
        .frame(width: 280)
    }
}

/// Laid out like the Google TV and Roku phone remotes: the D-pad first, then back/home/input,
/// one volume control, and app shortcuts.
private struct Controls: View {
    @Environment(RemoteController.self) private var remote

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(remote.pairedTV?.displayName ?? "")
                        .font(.headline)
                        .lineLimit(1)
                    Label {
                        Text(remote.connectionLabel)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(remote.isConnected ? .green : .secondary)
                            .imageScale(.small)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                MoreMenu()
                key(.power)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }

            GlassEffectContainer {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); key(.up); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                    GridRow {
                        key(.left)
                        key(.select).buttonStyle(.glassProminent)
                        key(.right)
                    }
                    GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); key(.down); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
            }

            HStack(spacing: 28) {
                ForEach([RemoteButton.back, .home, .input]) { button in
                    VStack(spacing: 4) {
                        key(button)
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                        Text(button.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 8) {
                HStack {
                    key(.mute, fill: true)
                    key(.volumeDown, fill: true)
                    key(.volumeUp, fill: true)
                }
                HStack {
                    key(.youtube)
                    key(.netflix)
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    /// Icon keys are a fixed square so circular ones stay round; `fill` stretches them instead.
    private func key(_ button: RemoteButton, fill: Bool = false) -> some View {
        Button { remote.press(button) } label: {
            if button == .select {
                Text("OK").frame(width: 24, height: 24)
            } else if let symbol = button.symbol {
                Label(button.title, systemImage: symbol)
                    .labelStyle(.iconOnly)
                    .frame(width: fill ? nil : 24, height: 24)
                    .frame(maxWidth: fill ? .infinity : nil)
            } else {
                Text(button.title).frame(maxWidth: .infinity)
            }
        }
        .buttonRepeatBehavior(button.repeats ? .enabled : .disabled)
        .keyboardShortcut(button.shortcut)
        .help(button.title)
    }
}

private extension RemoteButton {
    /// Arrows and volume keep firing while held, like a real remote.
    var repeats: Bool {
        [.up, .down, .left, .right, .volumeUp, .volumeDown].contains(self)
    }

    var shortcut: KeyboardShortcut? {
        switch self {
        case .up: KeyboardShortcut(.upArrow, modifiers: [])
        case .down: KeyboardShortcut(.downArrow, modifiers: [])
        case .left: KeyboardShortcut(.leftArrow, modifiers: [])
        case .right: KeyboardShortcut(.rightArrow, modifiers: [])
        case .select: KeyboardShortcut(.return, modifiers: [])
        case .back: KeyboardShortcut(.delete, modifiers: [])
        case .home: KeyboardShortcut("h", modifiers: [])
        case .volumeDown: KeyboardShortcut("-", modifiers: [])
        case .volumeUp: KeyboardShortcut("=", modifiers: [])
        case .mute: KeyboardShortcut("m", modifiers: [])
        default: nil
        }
    }
}

// MARK: - More menu

private struct MoreMenu: View {
    @Environment(RemoteController.self) private var remote
    /// Mirrors the real login item status, re-read whenever the panel opens.
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Toggle("Open at Login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
            Divider()
            Button(remote.pairedTV == nil ? "Pair with TV…" : "Pair with a Different TV…") {
                remote.showPairing()
            }
            if let tv = remote.pairedTV {
                Button("Forget \(tv.displayName)") { remote.forgetTV() }
            }
            Divider()
            Button("Quit Rebar") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .onAppear { opensAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Usually means the user has to allow it in System Settings, so take them there.
            SMAppService.openSystemSettingsLoginItems()
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
