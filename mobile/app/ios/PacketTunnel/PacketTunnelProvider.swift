import NetworkExtension
import Network
import os.log
import Vpnlib

class PacketTunnelProvider: NEPacketTunnelProvider {

    // MARK: - Logging
    private let logger = Logger(subsystem: "com.simplevpn.app.tunnel", category: "PacketTunnel")

    // MARK: - Socketpair (all access on loopQueue)
    private var socketFds: [Int32] = [-1, -1]

    // MARK: - Reconnect loop
    private let loopQueue = DispatchQueue(label: "com.simplevpn.loop", qos: .userInitiated)
    private var loopStopped = false                    // loopQueue
    private var backoffTimer: DispatchSourceTimer?     // loopQueue
    private var pendingAttempt: Int = 0                // loopQueue — set when timer armed
    private var pathSatisfied = true                   // loopQueue

    // DispatchGroup tracks the currently running RunTunnel goroutine.
    // Using DispatchGroup (not semaphore) avoids stale signals from previous iterations.
    private let runTunnelGroup = DispatchGroup()

    // MARK: - NWPathMonitor
    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "com.simplevpn.path")

    // MARK: - Config (set once in startTunnel, read-only afterwards)
    private var storedConfig: String = ""
    private var maxRetries: Int = 5
    private var autoReconnect: Bool = false

    // MARK: - App Group IPC (written here, observed by VpnManager for Task 24)
    private static let appGroupId = "group.com.simplevpn.app"
    static let statusDefaultsKey = "vpn_tunnel_status"

    // MARK: - Pure helpers (extracted for testability — mirrors Android's decideRetry pattern)

    struct RetryDecision {
        let shouldRetry: Bool
        let delaySecs: Int
        let reason: String
    }

    static func backoff(attempt: Int, maxBackoffSeconds: Int = 60) -> Int {
        guard attempt > 0 else { return 1 }
        let capped = min(attempt, 30)   // prevent overflow: 1 << 30 = ~1 billion ms, well above any cap
        let secs = 1 << capped
        return min(secs, maxBackoffSeconds)
    }

    static func retryDecision(
        autoReconnect: Bool,
        kind: String,
        attempt: Int,
        maxRetries: Int
    ) -> RetryDecision {
        if kind == "none" {
            return RetryDecision(shouldRetry: false, delaySecs: 0, reason: "clean-disconnect")
        }
        guard autoReconnect else {
            return RetryDecision(shouldRetry: false, delaySecs: 0, reason: "auto-reconnect-disabled")
        }
        switch kind {
        case "auth":  return RetryDecision(shouldRetry: false, delaySecs: 0, reason: "auth-rejected")
        case "fatal": return RetryDecision(shouldRetry: false, delaySecs: 0, reason: "fatal")
        default: break
        }
        if attempt >= maxRetries {
            return RetryDecision(shouldRetry: false, delaySecs: 0, reason: "max-retries-exceeded")
        }
        let delay = backoff(attempt: attempt)
        return RetryDecision(shouldRetry: true, delaySecs: delay, reason: "retry")
    }

    // MARK: - startTunnel
    //
    // CRITICAL: this function MUST return after the first successful Preflight +
    // setTunnelNetworkSettings call so iOS marks the tunnel as "running". The
    // reconnect loop is driven by RunTunnel's completion callback — startTunnel
    // does not block waiting for it.

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        logger.debug("startTunnel: entry")

        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let cfg = proto.providerConfiguration,
              let config = cfg["config"] as? String else {
            logger.error("startTunnel: no config in providerConfiguration")
            throw NEVPNError(.configurationInvalid)
        }

        storedConfig = config
        autoReconnect = cfg["auto_reconnect"] as? Bool ?? false
        maxRetries = (cfg["max_retries"] as? Int) ?? 5
        logger.debug("startTunnel: autoReconnect=\(self.autoReconnect) maxRetries=\(self.maxRetries)")

        // loopQueue not yet active — safe to write directly
        loopStopped = false

        // Iteration 0: Preflight + setNetworkSettings + socketpair + RunTunnel
        let bridgeFd = try await launchFirstIteration(config: config)

        startBridge(bridgeFd: bridgeFd)
        startPathMonitor()

        // Reconnect loop continues automatically via launchRunTunnelGlobal callbacks.
        logger.debug("startTunnel: done, reconnect loop active")
    }

    // MARK: - stopTunnel

    override func stopTunnel(with reason: NEProviderStopReason) async {
        logger.debug("stopTunnel: entry reason=\(String(describing: reason))")

        // Atomically: stop the loop, cancel any pending backoff timer, close bridge fds.
        loopQueue.sync {
            loopStopped = true
            backoffTimer?.cancel()
            backoffTimer = nil
            let fds = socketFds
            socketFds = [-1, -1]
            if fds[0] >= 0 { Darwin.close(fds[0]); logger.debug("stopTunnel: closed fd0=\(fds[0])") }
            // Closing fd1 makes readFromSocket return ≤0 and readFromPacketFlow stop re-arming.
            if fds[1] >= 0 { Darwin.close(fds[1]); logger.debug("stopTunnel: closed fd1=\(fds[1])") }
        }

        logger.debug("stopTunnel: calling VpnlibDisconnect")
        VpnlibDisconnect()

        // Wait for any in-flight RunTunnel goroutine to exit.
        // runTunnelGroup count = 0 when in backoff → returns immediately.
        // count = 1 when RunTunnel active → waits (should finish quickly after Disconnect).
        let waitResult = runTunnelGroup.wait(timeout: .now() + 2)
        if case .timedOut = waitResult {
            logger.warning("stopTunnel: RunTunnel wait timed out")
        } else {
            logger.debug("stopTunnel: RunTunnel goroutine confirmed exited")
        }

        pathMonitor?.cancel()
        pathMonitor = nil

        logger.debug("stopTunnel: done")
    }

    // MARK: - First iteration (inline in startTunnel; throws on failure so iOS knows to stop)

    private func launchFirstIteration(config: String) async throws -> Int32 {
        logger.debug("launchFirstIteration: Preflight")
        let preflightResult = VpnlibPreflight(config)
        logger.debug("launchFirstIteration: Preflight=\(preflightResult)")

        if preflightResult.hasPrefix("error:") {
            logger.error("launchFirstIteration: Preflight failed: \(preflightResult)")
            throw NSError(domain: "com.simplevpn", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: preflightResult])
        }

        let settings = try makeSettings(from: preflightResult)
        try await setTunnelNetworkSettings(settings)
        logger.debug("launchFirstIteration: network settings applied")

        let fds = try makeFds()
        socketFds = fds  // safe: loopQueue not yet active

        let dupFd = dup(fds[0])
        guard dupFd >= 0 else {
            let e = errno
            Darwin.close(fds[0]); Darwin.close(fds[1])
            logger.error("launchFirstIteration: dup failed errno=\(e)")
            throw NSError(domain: POSIXError.errorDomain, code: Int(e))
        }
        logger.debug("launchFirstIteration: dup fds[0]=\(fds[0]) → dupFd=\(dupFd)")

        launchRunTunnelGlobal(dupFd: dupFd, config: config, attempt: 0)
        emitStatus("connected")
        return fds[1]
    }

    // MARK: - Reconnect loop

    // Launches VpnlibRunTunnel on the global queue and drives the reconnect loop
    // via its completion callback. Uses DispatchGroup so stopTunnel can wait
    // for exactly the current goroutine (no stale "credits" from prior iterations).
    private func launchRunTunnelGlobal(dupFd: Int32, config: String, attempt: Int) {
        let group = runTunnelGroup
        let log = logger
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            log.debug("RunTunnel: starting dupFd=\(dupFd) attempt=\(attempt)")
            if let err = VpnlibRunTunnel(Int(dupFd)) {
                log.error("RunTunnel: error=\(err.localizedDescription) attempt=\(attempt)")
            } else {
                log.debug("RunTunnel: clean exit attempt=\(attempt)")
            }
            group.leave()   // unblocks stopTunnel if waiting; safe even if self is nil
            self?.loopQueue.async { self?.handleTunnelExit(config: config, attempt: attempt + 1) }
        }
    }

    // Called on loopQueue whenever RunTunnel exits or Preflight fails mid-retry.
    // Reads LastErrorKind (set by Go) and decides whether to retry or cancel.
    private func handleTunnelExit(config: String, attempt: Int) {
        guard !loopStopped else {
            logger.debug("handleTunnelExit: loopStopped attempt=\(attempt)")
            return
        }

        VpnlibDisconnect()  // idempotent — releases connectMu if still held
        let kind = VpnlibLastErrorKind() ?? "none"
        logger.debug("handleTunnelExit: kind=\(kind) attempt=\(attempt) autoReconnect=\(self.autoReconnect) maxRetries=\(self.maxRetries)")

        let d = Self.retryDecision(autoReconnect: autoReconnect, kind: kind,
                                   attempt: attempt, maxRetries: maxRetries)
        logger.debug("handleTunnelExit: shouldRetry=\(d.shouldRetry) reason=\(d.reason)")

        if !d.shouldRetry {
            switch d.reason {
            case "auth-rejected":
                logger.error("handleTunnelExit: auth rejected — stopping")
                emitStatus("error", errorKind: "auth")
                cancelTunnelWithError(NSError(domain: "com.simplevpn", code: attempt,
                    userInfo: [NSLocalizedDescriptionKey: "error: auth rejected"]))
            case "fatal":
                logger.error("handleTunnelExit: fatal — stopping")
                emitStatus("error", errorKind: "fatal")
                cancelTunnelWithError(NSError(domain: "com.simplevpn", code: attempt,
                    userInfo: [NSLocalizedDescriptionKey: "error: connection failed"]))
            case "max-retries-exceeded":
                logger.error("handleTunnelExit: max retries exceeded attempt=\(attempt)")
                emitStatus("error", errorKind: "transient")
                cancelTunnelWithError(NSError(domain: "com.simplevpn", code: attempt,
                    userInfo: [NSLocalizedDescriptionKey: "error: max retries exceeded"]))
            default:   // clean-disconnect, auto-reconnect-disabled
                logger.debug("handleTunnelExit: clean stop reason=\(d.reason)")
                emitStatus("disconnected")
            }
            return
        }

        // Arm backoff timer — doReconnect fires when it expires (or NWPathMonitor wakes early).
        pendingAttempt = attempt
        emitStatus("reconnecting", attempt: attempt, maxAttempts: maxRetries)
        logger.debug("handleTunnelExit: scheduling retry in \(d.delaySecs)s (attempt=\(attempt))")

        let timer = DispatchSource.makeTimerSource(queue: loopQueue)
        backoffTimer = timer
        timer.schedule(deadline: .now() + .seconds(d.delaySecs))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.backoffTimer = nil
            guard !self.loopStopped else {
                self.logger.debug("handleTunnelExit timer: loopStopped — not reconnecting")
                return
            }
            self.doReconnect(config: config, attempt: attempt)
        }
        timer.activate()
    }

    // Called on loopQueue when the backoff timer fires (or NWPathMonitor wakes early).
    // Dispatches Preflight to a global queue (blocking call), then resumes on loopQueue.
    private func doReconnect(config: String, attempt: Int) {
        guard !loopStopped else { return }
        logger.debug("doReconnect: entry attempt=\(attempt)")

        // Close the previous iteration's fds so the old bridge stops.
        let fds = socketFds
        socketFds = [-1, -1]
        if fds[0] >= 0 { Darwin.close(fds[0]); logger.debug("doReconnect: closed fd0=\(fds[0])") }
        if fds[1] >= 0 { Darwin.close(fds[1]); logger.debug("doReconnect: closed fd1=\(fds[1])") }

        emitStatus("connecting", attempt: attempt, maxAttempts: maxRetries)

        // Preflight is a blocking network call — run on global queue.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.logger.debug("doReconnect: Preflight start attempt=\(attempt)")
            let result = VpnlibPreflight(config)
            self.logger.debug("doReconnect: Preflight=\(result) attempt=\(attempt)")

            if result.hasPrefix("error:") {
                // Treat as a failed attempt — re-enter exit handler so retry/stop logic runs.
                self.logger.error("doReconnect: Preflight failed attempt=\(attempt)")
                self.loopQueue.async {
                    guard !self.loopStopped else { return }
                    self.handleTunnelExit(config: config, attempt: attempt + 1)
                }
                return
            }

            let settings: NEPacketTunnelNetworkSettings
            do {
                settings = try self.makeSettings(from: result)
            } catch {
                self.logger.error("doReconnect: makeSettings failed \(error) attempt=\(attempt)")
                self.loopQueue.async { if !self.loopStopped { self.cancelTunnelWithError(error) } }
                return
            }

            self.logger.debug("doReconnect: applying network settings attempt=\(attempt)")
            self.setTunnelNetworkSettings(settings) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.logger.error("doReconnect: setTunnelNetworkSettings error=\(error) attempt=\(attempt)")
                    self.loopQueue.async { if !self.loopStopped { self.cancelTunnelWithError(error) } }
                    return
                }

                let newFds: [Int32]
                do {
                    newFds = try self.makeFds()
                } catch {
                    self.logger.error("doReconnect: makeFds failed \(error) attempt=\(attempt)")
                    self.loopQueue.async { if !self.loopStopped { self.cancelTunnelWithError(error) } }
                    return
                }

                let dupFd = dup(newFds[0])
                guard dupFd >= 0 else {
                    let e = errno
                    Darwin.close(newFds[0]); Darwin.close(newFds[1])
                    self.logger.error("doReconnect: dup failed errno=\(e) attempt=\(attempt)")
                    self.loopQueue.async {
                        if !self.loopStopped {
                            self.cancelTunnelWithError(NSError(domain: POSIXError.errorDomain, code: Int(e)))
                        }
                    }
                    return
                }
                self.logger.debug("doReconnect: new fds=[\(newFds[0]),\(newFds[1])] dupFd=\(dupFd) attempt=\(attempt)")

                self.loopQueue.async {
                    guard !self.loopStopped else {
                        Darwin.close(newFds[0]); Darwin.close(newFds[1]); Darwin.close(dupFd)
                        return
                    }
                    self.socketFds = newFds
                    self.startBridge(bridgeFd: newFds[1])
                    self.launchRunTunnelGlobal(dupFd: dupFd, config: config, attempt: attempt)
                    self.emitStatus("connected")
                }
            }
        }
    }

    // MARK: - NWPathMonitor
    //
    // When the path is restored during a backoff window, cancel the timer and
    // reconnect immediately. When the path drops, just log — do not exit the loop
    // (the retry mechanism will handle it when RunTunnel eventually returns).

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let satisfied = path.status == .satisfied
            self.logger.debug("NWPathMonitor: status=\(path.status) satisfied=\(satisfied)")
            self.loopQueue.async {
                let wasUnsatisfied = !self.pathSatisfied
                self.pathSatisfied = satisfied
                if satisfied && wasUnsatisfied, let timer = self.backoffTimer {
                    self.logger.debug("NWPathMonitor: path restored — firing timer early attempt=\(self.pendingAttempt)")
                    timer.cancel()
                    self.backoffTimer = nil
                    guard !self.loopStopped else { return }
                    self.doReconnect(config: self.storedConfig, attempt: self.pendingAttempt)
                }
            }
        }
        monitor.start(queue: pathQueue)
        logger.debug("startPathMonitor: started")
    }

    // MARK: - Structured status emit (App Group UserDefaults → observed by VpnManager in Task 24)

    private func emitStatus(_ state: String, attempt: Int? = nil, maxAttempts: Int? = nil,
                             errorKind: String? = nil) {
        var status: [String: Any] = ["state": state]
        if let a = attempt    { status["attempt"] = a }
        if let m = maxAttempts { status["max"] = m }
        if let k = errorKind  { status["errorKind"] = k }
        guard let data = try? JSONSerialization.data(withJSONObject: status),
              let json = String(data: data, encoding: .utf8) else { return }
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        defaults?.set(json, forKey: Self.statusDefaultsKey)
        defaults?.synchronize()
        logger.debug("emitStatus: \(json)")
    }

    // MARK: - Bridge

    private func startBridge(bridgeFd: Int32) {
        readFromPacketFlow(bridgeFd: bridgeFd)
        readFromSocket(bridgeFd: bridgeFd)
    }

    // packetFlow → bridgeFd (fds[1]).
    // Stops re-arming when write fails (bridgeFd closed by stopTunnel or doReconnect).
    private func readFromPacketFlow(bridgeFd: Int32) {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self = self else { return }
            for packet in packets {
                let written = packet.withUnsafeBytes { buf in
                    Darwin.write(bridgeFd, buf.baseAddress!, buf.count)
                }
                if written < 0 {
                    self.logger.error("bridge: write to socket failed errno=\(errno) fd=\(bridgeFd)")
                    return  // fd was closed; stop re-arming
                }
            }
            self.readFromPacketFlow(bridgeFd: bridgeFd)
        }
    }

    // bridgeFd (fds[1]) → packetFlow.
    // Exits when read returns ≤0 (fd closed by stopTunnel or doReconnect).
    private func readFromSocket(bridgeFd: Int32) {
        let mtu = 1500
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var buf = [UInt8](repeating: 0, count: mtu)
            while true {
                let n = Darwin.read(bridgeFd, &buf, mtu)
                if n <= 0 {
                    self.logger.debug("bridge: socket read returned \(n), stopping fd=\(bridgeFd)")
                    break
                }
                let data = Data(buf[0..<n])
                self.packetFlow.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
            }
        }
    }

    // MARK: - IPC

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let request = String(data: messageData, encoding: .utf8) else {
            logger.error("IPC: cannot decode request as UTF-8")
            completionHandler?(nil)
            return
        }
        logger.debug("IPC: request=\(request)")

        let response: String
        switch request {
        case "getLogs":
            response = VpnlibLogs() ?? ""
            logger.debug("IPC: getLogs response size=\(response.count)")
        case "getStatus":
            response = VpnlibStatus() ?? "unknown"
            logger.debug("IPC: getStatus response=\(response)")
        default:
            logger.error("IPC: unknown request=\(request)")
            completionHandler?(nil)
            return
        }

        completionHandler?(response.data(using: .utf8))
    }

    // MARK: - Helpers

    private func makeSettings(from preflightResult: String) throws -> NEPacketTunnelNetworkSettings {
        let parts = preflightResult.split(separator: "/")
        guard parts.count == 2, let prefixLen = Int(parts[1]) else {
            throw NSError(domain: "com.simplevpn", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "bad prefix: \(preflightResult)"])
        }
        let assignedIP = String(parts[0])
        let subnetMask = prefixLenToMask(prefixLen)
        let gatewayIP = gatewayFromPrefix(assignedIP, prefixLen: prefixLen)
        logger.debug("makeSettings: addr=\(assignedIP)/\(prefixLen) gw=\(gatewayIP)")

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: gatewayIP)
        let ipv4 = NEIPv4Settings(addresses: [assignedIP], subnetMasks: [subnetMask])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        settings.mtu = 1380
        return settings
    }

    private func makeFds() throws -> [Int32] {
        var fds: [Int32] = [-1, -1]
        let spErr = socketpair(AF_UNIX, SOCK_DGRAM, 0, &fds)
        guard spErr == 0 else {
            let e = errno
            logger.error("makeFds: socketpair failed errno=\(e)")
            throw NSError(domain: POSIXError.errorDomain, code: Int(e))
        }
        let bufSize: Int32 = 262144
        for fd in fds {
            var bs = bufSize
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bs, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bs, socklen_t(MemoryLayout<Int32>.size))
        }
        logger.debug("makeFds: fds=[\(fds[0]), \(fds[1])]")
        return fds
    }

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
