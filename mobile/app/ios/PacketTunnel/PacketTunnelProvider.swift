import NetworkExtension
import os.log
import Vpnlib

class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "com.simplevpn.app.tunnel", category: "PacketTunnel")

    // Socketpair fds: fds[0] passed to Go (dup'd), fds[1] used for packetFlow bridge.
    private var socketFds: [Int32] = [-1, -1]
    // Semaphore to wait for RunTunnel to return before closing fds.
    private let tunnelDoneSem = DispatchSemaphore(value: 0)

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        logger.debug("startTunnel: entry")

        guard let config = (protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["config"] as? String else {
            logger.error("startTunnel: no config in providerConfiguration")
            throw NEVPNError(.configurationInvalid)
        }
        logger.debug("startTunnel: config len=\(config.count)")

        // --- Preflight: authenticate + get assigned IP ---
        logger.debug("startTunnel: calling VpnlibPreflight")
        let preflightResult = VpnlibPreflight(config)
        logger.debug("startTunnel: VpnlibPreflight returned: \(preflightResult)")

        if preflightResult.hasPrefix("error:") {
            logger.error("startTunnel: Preflight failed: \(preflightResult)")
            throw NSError(domain: "com.simplevpn", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: preflightResult])
        }

        // Parse assigned prefix, e.g. "10.0.0.2/24"
        let parts = preflightResult.split(separator: "/")
        guard parts.count == 2,
              let prefixLen = Int(parts[1]) else {
            logger.error("startTunnel: cannot parse assigned prefix: \(preflightResult)")
            throw NSError(domain: "com.simplevpn", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "bad prefix: \(preflightResult)"])
        }
        let assignedIP = String(parts[0])
        let subnetMask = prefixLenToMask(prefixLen)
        let gatewayIP = gatewayFromPrefix(assignedIP, prefixLen: prefixLen)
        logger.debug("startTunnel: assignedIP=\(assignedIP) mask=\(subnetMask) gw=\(gatewayIP)")

        // --- Configure TUN network settings with dynamic IP ---
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: gatewayIP)
        let ipv4 = NEIPv4Settings(addresses: [assignedIP], subnetMasks: [subnetMask])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        settings.mtu = 1380
        logger.debug("startTunnel: applying TUN settings addr=\(assignedIP)/\(prefixLen)")

        try await setTunnelNetworkSettings(settings)
        logger.debug("startTunnel: TUN network settings applied")

        // --- Create Unix DGRAM socketpair ---
        var fds: [Int32] = [-1, -1]
        let spErr = socketpair(AF_UNIX, SOCK_DGRAM, 0, &fds)
        guard spErr == 0 else {
            let e = errno
            logger.error("startTunnel: socketpair failed errno=\(e)")
            throw NSError(domain: POSIXError.errorDomain, code: Int(e))
        }
        socketFds = fds
        logger.debug("startTunnel: socketpair created fds[\(fds[0]), \(fds[1])]")

        // Set 256KB send/recv buffers on both ends.
        let bufSize: Int32 = 262144
        for fd in fds {
            var bs = bufSize
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bs, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bs, socklen_t(MemoryLayout<Int32>.size))
        }
        logger.debug("startTunnel: socket buffers set to \(bufSize) bytes")

        // --- dup fds[0] before passing to Go — os.NewFile takes ownership ---
        let dupFd = dup(fds[0])
        guard dupFd >= 0 else {
            let e = errno
            logger.error("startTunnel: dup(fds[0]) failed errno=\(e)")
            Darwin.close(fds[0]); Darwin.close(fds[1])
            throw NSError(domain: POSIXError.errorDomain, code: Int(e))
        }
        logger.debug("startTunnel: dup'd fds[0]=\(fds[0]) → dupFd=\(dupFd)")

        // --- Start VpnlibRunTunnel on background queue ---
        let sem = tunnelDoneSem
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { sem.signal(); return }
            self.logger.debug("RunTunnel: starting with dupFd=\(dupFd)")
            let err = VpnlibRunTunnel(Int(dupFd))
            if let err = err {
                self.logger.error("RunTunnel: returned error: \(err.localizedDescription)")
            } else {
                self.logger.debug("RunTunnel: returned nil (clean exit)")
            }
            sem.signal()
        }

        // --- Start packetFlow ↔ fds[1] bridge ---
        logger.debug("startTunnel: starting packetFlow bridge on fds[1]=\(fds[1])")
        startBridge(bridgeFd: fds[1])

        logger.debug("startTunnel: done")
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        logger.debug("stopTunnel: entry reason=\(String(describing: reason))")

        // 1. Signal Go to stop.
        logger.debug("stopTunnel: calling VpnlibDisconnect")
        VpnlibDisconnect()

        // 2. Wait for RunTunnel goroutine to return.
        logger.debug("stopTunnel: waiting for RunTunnel to finish")
        tunnelDoneSem.wait()
        logger.debug("stopTunnel: RunTunnel finished")

        // 3. Close fds[0] (Swift's original copy — Go has its own dup'd copy).
        let fd0 = socketFds[0]
        let fd1 = socketFds[1]
        if fd0 >= 0 {
            Darwin.close(fd0)
            logger.debug("stopTunnel: closed fds[0]=\(fd0)")
        }
        // 4. Close fds[1] (bridge end).
        if fd1 >= 0 {
            Darwin.close(fd1)
            logger.debug("stopTunnel: closed fds[1]=\(fd1)")
        }
        socketFds = [-1, -1]

        logger.debug("stopTunnel: done")
    }

    // MARK: - Bridge

    private func startBridge(bridgeFd: Int32) {
        // packetFlow → fds[1]
        readFromPacketFlow(bridgeFd: bridgeFd)
        // fds[1] → packetFlow
        readFromSocket(bridgeFd: bridgeFd)
    }

    private func readFromPacketFlow(bridgeFd: Int32) {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self = self else { return }
            for packet in packets {
                let written = packet.withUnsafeBytes { buf in
                    Darwin.write(bridgeFd, buf.baseAddress!, buf.count)
                }
                if written < 0 {
                    self.logger.error("bridge: write to socket failed errno=\(errno)")
                    return
                }
            }
            self.readFromPacketFlow(bridgeFd: bridgeFd)
        }
    }

    private func readFromSocket(bridgeFd: Int32) {
        let mtu = 1500
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var buf = [UInt8](repeating: 0, count: mtu)
            while true {
                let n = Darwin.read(bridgeFd, &buf, mtu)
                if n <= 0 {
                    self.logger.debug("bridge: socket read returned \(n), stopping")
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

    private func prefixLenToMask(_ len: Int) -> String {
        let mask: UInt32 = len == 0 ? 0 : ~UInt32(0) << (32 - len)
        return "\((mask >> 24) & 0xFF).\((mask >> 16) & 0xFF).\((mask >> 8) & 0xFF).\(mask & 0xFF)"
    }

    private func gatewayFromPrefix(_ ip: String, prefixLen: Int) -> String {
        // Derive gateway as first address in the subnet (host bits zeroed, +1).
        let octets = ip.split(separator: ".").compactMap { UInt32($0) }
        guard octets.count == 4 else { return "10.0.0.1" }
        let addr: UInt32 = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
        let netMask: UInt32 = prefixLen == 0 ? 0 : ~UInt32(0) << (32 - prefixLen)
        let network = addr & netMask
        let gw = network | 1
        return "\((gw >> 24) & 0xFF).\((gw >> 16) & 0xFF).\((gw >> 8) & 0xFF).\(gw & 0xFF)"
    }
}
