import XCTest

// Unit tests for PacketTunnelProvider helper logic.
// Run via: Product → Test (⌘U) in Xcode with the PacketTunnel scheme selected.
//
// These tests exercise prefix parsing and IPC encoding without requiring a live VPN.

final class PacketTunnelTests: XCTestCase {

    // MARK: - Prefix parsing

    func testPrefixParsingValid() {
        let cases: [(String, String, String)] = [
            ("10.0.0.2/24",   "10.0.0.2",   "255.255.255.0"),
            ("192.168.1.100/16", "192.168.1.100", "255.255.0.0"),
            ("172.16.0.5/12",   "172.16.0.5",  "255.240.0.0"),
            ("10.0.0.1/30",     "10.0.0.1",    "255.255.255.252"),
        ]
        for (prefix, expectedIP, expectedMask) in cases {
            let parts = prefix.split(separator: "/")
            XCTAssertEqual(parts.count, 2, "parts count for \(prefix)")
            let ip = String(parts[0])
            let len = Int(parts[1])!
            let mask = prefixLenToMask(len)
            XCTAssertEqual(ip, expectedIP, "IP for \(prefix)")
            XCTAssertEqual(mask, expectedMask, "mask for \(prefix)")
        }
    }

    func testPrefixParsingEdgeCases() {
        // /32 — single host
        let mask32 = prefixLenToMask(32)
        XCTAssertEqual(mask32, "255.255.255.255")

        // /0 — full route
        let mask0 = prefixLenToMask(0)
        XCTAssertEqual(mask0, "0.0.0.0")
    }

    func testErrorPrefixDetected() {
        let errorCases = [
            "error: already connected",
            "error: auth rejected: DENY",
            "error: connect: dial tcp timeout",
        ]
        for s in errorCases {
            XCTAssertTrue(s.hasPrefix("error:"), "\(s) should be detected as error")
        }
        XCTAssertFalse("10.0.0.2/24".hasPrefix("error:"), "valid prefix should not be error")
    }

    func testGatewayDerivation() {
        XCTAssertEqual(gatewayFromPrefix("10.0.0.2", prefixLen: 24), "10.0.0.1")
        XCTAssertEqual(gatewayFromPrefix("192.168.1.100", prefixLen: 16), "192.168.0.1")
        XCTAssertEqual(gatewayFromPrefix("10.0.0.1", prefixLen: 30), "10.0.0.1")
    }

    // MARK: - IPC encoding

    func testIPCRequestEncoding() {
        let requests = ["getLogs", "getStatus"]
        for req in requests {
            let data = req.data(using: .utf8)
            XCTAssertNotNil(data, "encoding \(req)")
            let decoded = String(data: data!, encoding: .utf8)
            XCTAssertEqual(decoded, req)
        }
    }

    func testIPCResponseDecoding() {
        let logLine = "[vpnlib] Tunnel active\n"
        let data = logLine.data(using: .utf8)!
        let decoded = String(data: data, encoding: .utf8)
        XCTAssertEqual(decoded, logLine)
    }

    // MARK: - Helpers (duplicated from PacketTunnelProvider for testability)

    private func prefixLenToMask(_ len: Int) -> String {
        let mask: UInt32 = len == 0 ? 0 : ~UInt32(0) << (32 - len)
        return "\((mask >> 24) & 0xFF).\((mask >> 16) & 0xFF).\((mask >> 8) & 0xFF).\(mask & 0xFF)"
    }

    private func gatewayFromPrefix(_ ip: String, prefixLen: Int) -> String {
        let octets = ip.split(separator: ".").compactMap { UInt32($0) }
        guard octets.count == 4 else { return "10.0.0.1" }
        let addr: UInt32 = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
        let netMask: UInt32 = prefixLen == 0 ? 0 : ~UInt32(0) << (32 - prefixLen)
        let network = addr & netMask
        let gw = network | 1
        return "\((gw >> 24) & 0xFF).\((gw >> 16) & 0xFF).\((gw >> 8) & 0xFF).\(gw & 0xFF)"
    }
}
