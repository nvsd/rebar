import Network
import XCTest
@testable import Rebar

final class AddressTests: XCTestCase {
    func testIPv4DropsInterfaceSuffix() throws {
        let address = try XCTUnwrap(IPv4Address("192.0.2.20%en0"))
        XCTAssertEqual(TVBrowser.address(of: .ipv4(address)), "192.0.2.20")
    }

    func testIPv6DropsInterfaceSuffix() throws {
        let address = try XCTUnwrap(IPv6Address("fe80::1%en0"))
        XCTAssertEqual(TVBrowser.address(of: .ipv6(address)), "fe80::1")
    }
}
