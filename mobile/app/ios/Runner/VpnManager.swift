import Flutter
import NetworkExtension

class VpnPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.simplevpn/vpn"
    private var statusObserver: NSObjectProtocol?
    private var channel: FlutterMethodChannel?
    // Retained self pointer passed as observer context to CFNotificationCenter.
    private var _darwinObserverSelf: Unmanaged<VpnPlugin>?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = VpnPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)

        // NEVPNStatusDidChange covers the OS-level connect/disconnect lifecycle.
        instance.statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak instance] notification in
            guard let session = notification.object as? NETunnelProviderSession else { return }
            let status: String
            switch session.status {
            case .connected: status = "connected"
            case .connecting: status = "connecting"
            case .disconnecting: status = "disconnecting"
            case .disconnected: status = "disconnected"
            default: status = "unknown"
            }
            // Emit a legacy string so the Dart layer's backwards-compat path handles it.
            instance?.channel?.invokeMethod("onStatusChanged", arguments: status)
        }

        // Darwin notification from PacketTunnelProvider carries the full structured status.
        instance.setupDarwinObserver()
    }

    // MARK: - Darwin cross-process notification

    private func setupDarwinObserver() {
        let selfRetained = Unmanaged.passRetained(self)
        _darwinObserverSelf = selfRetained
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            selfRetained.toOpaque(),
            { _, observer, _, _, _ in
                guard let obs = observer else { return }
                Unmanaged<VpnPlugin>.fromOpaque(obs).takeUnretainedValue()
                    .readAndForwardTunnelStatus()
            },
            CFNotificationName("com.simplevpn.tunnelStatus" as CFString),
            nil,
            .deliverImmediately
        )
    }

    func readAndForwardTunnelStatus() {
        // Key must match PacketTunnelProvider.statusDefaultsKey = "vpn_tunnel_status"
        guard let defaults = UserDefaults(suiteName: "group.com.simplevpn.app"),
              let json = defaults.string(forKey: "vpn_tunnel_status"),
              let data = json.data(using: .utf8),
              let statusMap = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("onStatusChanged", arguments: statusMap)
        }
    }

    // MARK: - Method calls from Dart

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

        case "getLogs":
            getLogs(result: result)

        case "getStats":
            getStats(result: result)

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
            let reconnectMaxAttempts = args["reconnect_max_attempts"] as? Int ?? 5
            let reconnectMaxBackoffS = args["reconnect_max_backoff_s"] as? Int ?? 60
            let splitMode = args["split_tunnel_mode"] as? String ?? "off"
            let splitRoutes = args["split_tunnel_routes"] as? [String] ?? []
            proto.providerConfiguration = [
                "config": config,
                "auto_reconnect": autoReconnect,
                "max_retries": reconnectMaxAttempts,
                "max_backoff_s": reconnectMaxBackoffS,
                "split_tunnel_mode": splitMode,
                "split_tunnel_routes": splitRoutes,
            ]

            // Kill switch: includeAllNetworks blocks all traffic when VPN drops.
            // iOS < 14.2 does not support includeAllNetworks — emit a warning so Dart
            // can surface "Kill switch unavailable on this iOS version" to the user.
            if #available(iOS 14.2, *) {
                proto.includeAllNetworks = killSwitch
                proto.excludeLocalNetworks = true  // Allow local network access
                NSLog("[VpnPlugin] Kill switch configured: includeAllNetworks=%@", killSwitch ? "true" : "false")
            } else if killSwitch {
                NSLog("[VpnPlugin] Kill switch requested but iOS < 14.2 — not supported")
                DispatchQueue.main.async { [weak instance] in
                    instance?.channel?.invokeMethod("onStatusChanged", arguments: [
                        "state": "error",
                        "errorKind": "unsupported_kill_switch",
                        "errorMessage": "Kill switch requires iOS 14.2 or later",
                    ])
                }
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
                NSLog("[VpnPlugin] setKillSwitch: includeAllNetworks=%@ saved to prefs", enabled ? "true" : "false")
            } else if enabled {
                NSLog("[VpnPlugin] setKillSwitch: iOS < 14.2, includeAllNetworks not supported — no-op")
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

    private func getLogs(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            guard let manager = managers?.first,
                  let session = manager.connection as? NETunnelProviderSession,
                  session.status == .connected,
                  let data = "getLogs".data(using: .utf8) else {
                result("")
                return
            }
            do {
                try session.sendProviderMessage(data) { responseData in
                    let logs = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    result(logs)
                }
            } catch {
                result("")
            }
        }
    }

    private func getStats(result: @escaping FlutterResult) {
        let fallback = """
        {"bytes_in":0,"bytes_out":0,"since_ms":0}
        """
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            guard let manager = managers?.first,
                  let session = manager.connection as? NETunnelProviderSession,
                  session.status == .connected,
                  let data = "getStats".data(using: .utf8) else {
                result(fallback)
                return
            }
            do {
                try session.sendProviderMessage(data) { responseData in
                    let stats = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? fallback
                    result(stats)
                }
            } catch {
                result(fallback)
            }
        }
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let retained = _darwinObserverSelf {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                retained.toOpaque(),
                CFNotificationName("com.simplevpn.tunnelStatus" as CFString),
                nil
            )
            retained.release()
        }
    }
}
