import Flutter
import NetworkExtension

class VpnPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.simplevpn/vpn"
    private var statusObserver: NSObjectProtocol?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = VpnPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Observe VPN status changes and notify Flutter
        instance.statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { notification in
            guard let session = notification.object as? NETunnelProviderSession else { return }
            let status: String
            switch session.status {
            case .connected: status = "connected"
            case .connecting: status = "connecting"
            case .disconnecting: status = "disconnecting"
            case .disconnected: status = "disconnected"
            default: status = "unknown"
            }
            channel.invokeMethod("onStatusChanged", arguments: status)
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let config = args["config"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing config", details: nil))
                return
            }
            let killSwitch = args["kill_switch"] as? Bool ?? false
            let autoReconnect = args["auto_reconnect"] as? Bool ?? false
            startVpn(config: config, killSwitch: killSwitch, autoReconnect: autoReconnect, result: result)

        case "disconnect":
            stopVpn(result: result)

        case "status":
            getStatus(result: result)

        case "setKillSwitch":
            guard let args = call.arguments as? [String: Any],
                  let enabled = args["enabled"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing enabled", details: nil))
                return
            }
            setKillSwitch(enabled: enabled, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startVpn(config: String, killSwitch: Bool, autoReconnect: Bool, result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            let manager = managers?.first ?? NETunnelProviderManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.simplevpn.app.tunnel"
            proto.serverAddress = "SimpleVPN"
            proto.providerConfiguration = ["config": config]

            // Kill switch: includeAllNetworks blocks all traffic when VPN drops
            if #available(iOS 14.2, *) {
                proto.includeAllNetworks = killSwitch
                proto.excludeLocalNetworks = true  // Allow local network access
            }

            manager.protocolConfiguration = proto
            manager.isEnabled = true
            manager.isOnDemandEnabled = autoReconnect

            // On-demand rules for auto-reconnect
            if autoReconnect {
                let connectRule = NEOnDemandRuleConnect()
                connectRule.interfaceTypeMatch = .any
                manager.onDemandRules = [connectRule]
            } else {
                manager.onDemandRules = []
            }

            manager.saveToPreferences { error in
                if let error = error {
                    result(FlutterError(code: "SAVE_ERROR", message: error.localizedDescription, details: nil))
                    return
                }

                manager.loadFromPreferences { error in
                    if let error = error {
                        result(FlutterError(code: "LOAD_ERROR", message: error.localizedDescription, details: nil))
                        return
                    }

                    do {
                        try (manager.connection as? NETunnelProviderSession)?.startTunnel()
                        result(nil)
                    } catch {
                        result(FlutterError(code: "START_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func stopVpn(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            guard let manager = managers?.first else {
                result(nil)
                return
            }
            manager.connection.stopVPNTunnel()
            result(nil)
        }
    }

    private func setKillSwitch(enabled: Bool, result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            guard let manager = managers?.first,
                  let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else {
                result(FlutterError(code: "NO_VPN", message: "No VPN configured", details: nil))
                return
            }

            if #available(iOS 14.2, *) {
                proto.includeAllNetworks = enabled
                proto.excludeLocalNetworks = true
            }

            manager.saveToPreferences { error in
                if let error = error {
                    result(FlutterError(code: "SAVE_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        }
    }

    private func getStatus(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            guard let manager = managers?.first else {
                result("disconnected")
                return
            }

            switch manager.connection.status {
            case .connected: result("connected")
            case .connecting: result("connecting")
            case .disconnecting: result("disconnecting")
            case .disconnected: result("disconnected")
            default: result("unknown")
            }
        }
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
