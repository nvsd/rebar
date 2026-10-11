import XCTest
@testable import Rebar

/// Expected values come from the reference Python implementation (androidtvremote2)
/// run against the same two certificates.
final class PairingTests: XCTestCase {
    private let clientDER = Data(base64Encoded: "MIIDAzCCAeugAwIBAgIURrIj98cjKyrtunzkNtjtGRr8uY0wDQYJKoZIhvcNAQELBQAwETEPMA0GA1UEAwwGY2xpZW50MB4XDTI2MTAwOTExMjcxNVoXDTM2MTAwNjExMjcxNVowETEPMA0GA1UEAwwGY2xpZW50MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2RS/5S9oD+pDNqTtZWzVET3MHlUEXeCfDdigHlsGcORp5zAixHqBNHy9cd5iSf4TqCmI+F8QVhz7mdbQ9KWsnotg6f7G+C2USTMjwPr3TcCsAzsWwwbq3tgatR+B8Q2HZhz2L6d0vHz5joL/jRAlm9Isca+DnwjHfD7/Txpv22Utl2oOy1jblfPKvickL8sv4RU+zhD9WxrXfyLJYFdj5p8Vwez9OjcXJYMesOG9RV8x3e5YqOiAOBkNa/glJw6gchSNnptvRWmskm3J3rtM+JnUR9bS8AUYxpbrE1HrO5LhIphE0RWkluCF8t0rKWNWF8qbqsDfFSkEqhTdWqtyKQIDAQABo1MwUTAdBgNVHQ4EFgQUY8qBcEB2mqldH6g0nfObWjzWtK4wHwYDVR0jBBgwFoAUY8qBcEB2mqldH6g0nfObWjzWtK4wDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAvfY3RotacSvAT2W2QgO58LSRifRiJbFgf7hH8q0f3YVS6TtkRzVjdq9M0jAkWTi6EY7xb5nQnx7zrhDG1jIL/SDybhPhnNirxZbAiaqR3WjHNmOwGzVNcpvjYO0VJE7Bv7uBIYfUoYXi2B+6azT6L9cqsRHBwKw8bQA1921mi5P+xfy7VCDuJlmcUQql/JeJCvjTnf4JnOdfJ8hs+FnOP6Tpf0hoAjDRM4IaROUOJnl98U+ohgTrt6kN74BXqEmPksmY4N+2Vd3DrMD0TTkjoAG1lEzLVJAUeezTImNegUkPpUG+0qfohe89xtSnfZ7v5Tp7NywTIuesGmjDO1oMng==")!
    private let serverDER = Data(base64Encoded: "MIIDAzCCAeugAwIBAgIUPFUYjN234gNQV9tXtk+3GCGoXlowDQYJKoZIhvcNAQELBQAwETEPMA0GA1UEAwwGc2VydmVyMB4XDTI2MTAwOTExMjcxNloXDTM2MTAwNjExMjcxNlowETEPMA0GA1UEAwwGc2VydmVyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5v/Jp7phv7oAribhDo3PPHRoIlYhT0xCaKFmPixTlwbSS1Mtp+71e4wgC8FwKVm76zcy3i9TM2BT/k0uRrsKXMawaR7oV9+u158OHXB5Z3JkqYu0qERF2SQtffmjnXFqch3B5DlWCM23vldux99K0RdBglzQQNl9Y/5XaMUitxQ+y9ZJuxb5lSVKKYshbNr/RbWMsBsjucwCO7j88hbi3+a6EuadcO9R+d20s3Z5E0qZusJo7S8vOsITkg78f5BjipP7aiBZLCGn5+LQos8pVwt7oemx0gZZk2OAIwyHB642d82NNal/Fy7f7v0/mWC66qMNQPV27g2sFKTVf9nnGwIDAQABo1MwUTAdBgNVHQ4EFgQU6mDoM30hOSJ0jGkLG6EW1MbesbMwHwYDVR0jBBgwFoAU6mDoM30hOSJ0jGkLG6EW1MbesbMwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAjqoRn0cqNyp2OhYUiWu2t0kH5mcb6JN7v2zoUWR1/tD3lsrCaKeWQ1wiUCJJxeidlERmFHiwR9eKhkDPVdMX0o1ZnlXjrVQkxfgnE/a3+Y+Wivn5zLza6ReiXjG6AguNtp1Kkbwq51F4KH/V4QHC06C9JdFKvhF4XDcFIQS/r6yjpA+/U5nkA3IxrodndF3iyV65HrK/hxiEH0PzHD83EScTLadlTH5m5Xqx4vP67bL0WVxx98MITK1g3XXdlAltFbfLzzhfpDOtb78ZML5x855UWDR9DYQRswo2AAAIafXKH/7MkGS+h1VfvA7jNMQZrjX9pF8zqdD9mxzhj7VEUQ==")!

    func testReadsRSANumbersFromCertificate() throws {
        let numbers = try RSAPublicNumbers(certificateDER: clientDER)
        XCTAssertEqual(numbers.modulus.count, 256)
        XCTAssertEqual(numbers.exponent, Data([0x01, 0x00, 0x01]))
    }

    func testSecretMatchesReference() throws {
        let client = try RSAPublicNumbers(certificateDER: clientDER)
        let server = try RSAPublicNumbers(certificateDER: serverDER)
        let secret = PairingSecret.compute(code: "E61234", client: client, server: server)
        XCTAssertEqual(secret, Data(hex: "e6103145a7faec6360220edb270687d8ef084c4c6022d1cc7e9523cad8d5a440"))
        XCTAssertEqual(PairingSecret.compute(code: "e61234", client: client, server: server), secret)
    }

    func testRejectsMistypedCode() throws {
        let client = try RSAPublicNumbers(certificateDER: clientDER)
        let server = try RSAPublicNumbers(certificateDER: serverDER)
        XCTAssertNil(PairingSecret.compute(code: "001234", client: client, server: server))
        XCTAssertNil(PairingSecret.compute(code: "12345", client: client, server: server))
        XCTAssertNil(PairingSecret.compute(code: "GGGGGG", client: client, server: server))
    }

    func testGeneratedIdentityIsReadable() throws {
        let identity = try ClientIdentity.generate()
        let numbers = try RSAPublicNumbers(certificateDER: try identity.certificateDER)
        XCTAssertEqual(numbers.modulus.count, 256)
    }

    func testFramesRoundTrip() throws {
        var writer = ProtoWriter()
        writer.int(1, 2)
        writer.int(2, 200)
        writer.message(10) { $0.string(1, "atvremote") }
        var buffer = FrameBuffer()
        let framed = FrameBuffer.frame(writer.data)
        buffer.append(framed.prefix(3))
        XCTAssertNil(buffer.next())
        buffer.append(framed.dropFirst(3) + framed)
        let first = try ProtoMessage(XCTUnwrap(buffer.next()))
        XCTAssertEqual(first.int(2), 200)
        XCTAssertEqual(first.message(10)?.string(1), "atvremote")
        XCTAssertNotNil(buffer.next())
        XCTAssertNil(buffer.next())
    }
}
