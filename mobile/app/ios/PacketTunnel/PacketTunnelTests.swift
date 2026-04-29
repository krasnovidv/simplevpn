import XCTest

// Unit tests for PacketTunnelProvider helper logic.
// Run via: Product → Test (⌘U) in Xcode with the PacketTunnel scheme selected.
//
// These tests exercise prefix parsing, IPC encoding, backoff calculation, and
// the pure retry-decision logic without requiring a live VPN or Vpnlib stubs.

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
        XCTAssertEqual(prefixLenToMask(32), "255.255.255.255")
        XCTAssertEqual(prefixLenToMask(0),  "0.0.0.0")
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

    // MARK: - backoff(attempt:)

    func testBackoffFollowsExponential() {
        // attempt → expected seconds (formula: 1 << attempt, capped at 60)
        let cases: [(Int, Int)] = [
            (0, 1),   // floor: attempt ≤ 0 → 1 s
            (1, 2),
            (2, 4),
            (3, 8),
            (4, 16),
            (5, 32),
            (6, 60),  // 64 capped to 60
            (7, 60),
            (8, 60),
            (9, 60),
            (10, 60),
        ]
        for (attempt, want) in cases {
            let got = PacketTunnelProvider.backoff(attempt: attempt)
            XCTAssertEqual(got, want, "backoff(attempt: \(attempt))")
        }
    }

    func testBackoffCustomCap() {
        XCTAssertEqual(PacketTunnelProvider.backoff(attempt: 1, maxBackoffSeconds: 10), 2)
        XCTAssertEqual(PacketTunnelProvider.backoff(attempt: 2, maxBackoffSeconds: 10), 4)
        XCTAssertEqual(PacketTunnelProvider.backoff(attempt: 3, maxBackoffSeconds: 10), 8)
        XCTAssertEqual(PacketTunnelProvider.backoff(attempt: 4, maxBackoffSeconds: 10), 10)  // 16 → 10
        XCTAssertEqual(PacketTunnelProvider.backoff(attempt: 20, maxBackoffSeconds: 10), 10)
    }

    func testBackoffNegativeAttemptReturnsFloor() {
        XCTAssertEqual(PacketTunnelProvider.backoff(attempt: -1), 1)
        XCTAssertEqual(PacketTunnelProvider.backoff(attempt: Int.min), 1)
    }

    func testBackoffDoesNotOverflow() {
        XCTAssertEqual(PacketTunnelProvider.backoff(attempt: 1000), 60)
        XCTAssertEqual(PacketTunnelProvider.backoff(attempt: Int.max), 60)
    }

    // MARK: - retryDecision: short-circuits

    func testRetryDecision_authDoesNotRetry() {
        let d = PacketTunnelProvider.retryDecision(autoReconnect: true, kind: "auth", attempt: 0, maxRetries: 5)
        XCTAssertFalse(d.shouldRetry, "auth must not retry")
        XCTAssertEqual(d.reason, "auth-rejected")
    }

    func testRetryDecision_authNeverAdvancesAttempt() {
        // Even deep in retry range, auth must always stop.
        for attempt in [0, 1, 3, 100] {
            let d = PacketTunnelProvider.retryDecision(autoReconnect: true, kind: "auth", attempt: attempt, maxRetries: 5)
            XCTAssertFalse(d.shouldRetry, "auth must not retry at attempt=\(attempt)")
        }
    }

    func testRetryDecision_fatalDoesNotRetry() {
        let d = PacketTunnelProvider.retryDecision(autoReconnect: true, kind: "fatal", attempt: 0, maxRetries: 5)
        XCTAssertFalse(d.shouldRetry)
        XCTAssertEqual(d.reason, "fatal")
    }

    func testRetryDecision_noneIsCleanDisconnect() {
        let d = PacketTunnelProvider.retryDecision(autoReconnect: true, kind: "none", attempt: 2, maxRetries: 5)
        XCTAssertFalse(d.shouldRetry)
        XCTAssertEqual(d.reason, "clean-disconnect")
    }

    func testRetryDecision_autoReconnectDisabledNeverRetries() {
        let d = PacketTunnelProvider.retryDecision(autoReconnect: false, kind: "transient", attempt: 0, maxRetries: 5)
        XCTAssertFalse(d.shouldRetry)
        XCTAssertEqual(d.reason, "auto-reconnect-disabled")
    }

    // MARK: - retryDecision: transient retries

    func testRetryDecision_transientRetriesUpToMax() {
        // attempts 0..4 with maxRetries=5 should all retry
        for attempt in 0...4 {
            let d = PacketTunnelProvider.retryDecision(autoReconnect: true, kind: "transient",
                                                       attempt: attempt, maxRetries: 5)
            XCTAssertTrue(d.shouldRetry, "should retry at attempt=\(attempt)")
            XCTAssertEqual(d.reason, "retry")
        }
    }

    func testRetryDecision_transientStopsAtMax() {
        let d = PacketTunnelProvider.retryDecision(autoReconnect: true, kind: "transient",
                                                   attempt: 5, maxRetries: 5)
        XCTAssertFalse(d.shouldRetry)
        XCTAssertEqual(d.reason, "max-retries-exceeded")
    }

    func testRetryDecision_delayMatchesBackoff() {
        // When retrying, the delay should equal backoff(attempt:).
        let attempt = 3
        let d = PacketTunnelProvider.retryDecision(autoReconnect: true, kind: "transient",
                                                   attempt: attempt, maxRetries: 10)
        XCTAssertTrue(d.shouldRetry)
        XCTAssertEqual(d.delaySecs, PacketTunnelProvider.backoff(attempt: attempt))
    }

    func testRetryDecision_unknownKindTreatedAsTransient() {
        let d = PacketTunnelProvider.retryDecision(autoReconnect: true, kind: "unrecognized",
                                                   attempt: 0, maxRetries: 5)
        XCTAssertTrue(d.shouldRetry)
    }

    func testRetryDecision_unlimitedRetriesNeverHitMax() {
        let d = PacketTunnelProvider.retryDecision(autoReconnect: true, kind: "transient",
                                                   attempt: 1_000_000, maxRetries: Int.max)
        XCTAssertTrue(d.shouldRetry)
        XCTAssertEqual(d.delaySecs, 60)  // backoff capped
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
