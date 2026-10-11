import XCTest
@testable import Rebar

final class RemoteConnectionTests: XCTestCase {
    func testEncodesKeyPress() {
        // remote_key_inject { key_code: KEYCODE_DPAD_UP, direction: SHORT }
        XCTAssertEqual(RemoteConnection.encode(.key(19)), Data([0x52, 0x04, 0x08, 0x13, 0x10, 0x03]))
    }

    func testEncodesAppLink() throws {
        let data = RemoteConnection.encode(.openApp(URL(string: "https://www.youtube.com")!))
        XCTAssertEqual(Array(data.prefix(2)), [0xD2, 0x05])
        let message = try ProtoMessage(data)
        XCTAssertEqual(message.message(90)?.string(1), "https://www.youtube.com")
    }
}
