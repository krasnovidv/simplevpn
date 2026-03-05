import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "com.simplevpn.app.tunnel", category: "PacketTunnel")

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        logger.info("Starting tunnel")

        guard let config = (protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["config"] as? String else {
            logger.error("No config found in provider configuration")
            throw NEVPNError(.configurationInvalid)
        }

        // Configure TUN settings
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        settings.mtu = 1380

        try await setTunnelNetworkSettings(settings)
        logger.info("Tunnel network settings applied")

        // Kill switch: includeAllNetworks blocks traffic when VPN disconnects
        if let manager = NETunnelProviderManager.forPerAppVPN() as? NETunnelProviderManager {
            // includeAllNetworks is set at the manager level, not here
            // It's configured when the VPN profile is saved
        }

        // Get the TUN file descriptor for the Go library
        // NEPacketTunnelProvider gives us packetFlow instead of raw fd
        // We use packetFlow.readPackets / writePackets

        logger.info("Starting packet forwarding")
        startPacketForwarding(config: config)
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        logger.info("Stopping tunnel, reason: \(String(describing: reason))")
        // Go library cleanup
        // Vpnlib.disconnect()
    }

    private func startPacketForwarding(config: String) {
        // Read packets from TUN and forward to Go library
        readPackets()
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }

            for (index, packet) in packets.enumerated() {
                // Forward packet to Go VPN library
                // Vpnlib.sendPacket(packet)
                _ = packet
                _ = protocols[index]
            }

            // Continue reading
            self.readPackets()
        }
    }

    func writePacket(_ data: Data) {
        // Write packet received from Go library back to TUN
        packetFlow.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
    }
}
