import Foundation

/// What a button asks the TV to do.
enum RemoteAction: Equatable {
    /// An Android key code, as defined in android.view.KeyEvent.
    case key(Int32)
    /// A deep link the TV opens in the matching app.
    case openApp(URL)
}

/// Every button on the Google TV Streamer remote, except the Assistant mic.
enum RemoteButton: String, CaseIterable, Identifiable {
    case power, input
    case up, down, left, right, select
    case back, home, star
    case youtube, netflix
    case volumeUp, volumeDown, mute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power: "Power"
        case .input: "Input"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .star: "Star"
        case .youtube: "YouTube"
        case .netflix: "Netflix"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        }
    }

    /// SF Symbol for the button. App buttons use text instead.
    var symbol: String? {
        switch self {
        case .power: "power"
        case .input: "rectangle.on.rectangle"
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .select: "circle.fill"
        case .back: "arrow.uturn.backward"
        case .home: "house"
        case .star: "star"
        case .youtube, .netflix: nil
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .mute: "speaker.slash"
        }
    }

    var action: RemoteAction {
        switch self {
        case .power: .key(26)       // KEYCODE_POWER
        case .input: .key(178)      // KEYCODE_TV_INPUT
        case .up: .key(19)          // KEYCODE_DPAD_UP
        case .down: .key(20)        // KEYCODE_DPAD_DOWN
        case .left: .key(21)        // KEYCODE_DPAD_LEFT
        case .right: .key(22)       // KEYCODE_DPAD_RIGHT
        case .select: .key(23)      // KEYCODE_DPAD_CENTER
        case .back: .key(4)         // KEYCODE_BACK
        case .home: .key(3)         // KEYCODE_HOME
        case .star: .key(174)       // KEYCODE_BOOKMARK, to be confirmed against the Streamer in step 4
        case .youtube: .openApp(URL(string: "https://www.youtube.com")!)
        case .netflix: .openApp(URL(string: "https://www.netflix.com/title")!)
        case .volumeUp: .key(24)    // KEYCODE_VOLUME_UP
        case .volumeDown: .key(25)  // KEYCODE_VOLUME_DOWN
        case .mute: .key(164)       // KEYCODE_VOLUME_MUTE
        }
    }
}
