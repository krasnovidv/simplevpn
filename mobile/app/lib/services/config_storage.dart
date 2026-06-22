import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_config.dart';
import '../models/split_tunnel_config.dart';

class ConfigStorage {
  static const _keyConfig = 'vpn_config';
  static const _keyAutoReconnect = 'auto_reconnect';
  static const _keyKillSwitch = 'kill_switch';
  static const _keyReconnectMaxAttempts = 'reconnect_max_attempts';
  static const _keyReconnectMaxBackoff = 'reconnect_max_backoff_s';
  static const _keySplitTunnelMode = 'split_tunneling_mode';
  static const _keySplitTunnelApps = 'split_tunneling_apps';
  static const _keySplitTunnelRoutes = 'split_tunneling_routes';
  static const _keyFooterWidget = 'footer_widget';

  // Credentials stored encrypted (Android EncryptedSharedPreferences / iOS Keychain)
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<VpnConfig?> loadConfig() async {
    final json = await _secureStorage.read(key: _keyConfig);
    if (json == null) return null;
    return VpnConfig.fromJson(json);
  }

  Future<void> saveConfig(VpnConfig config) async {
    await _secureStorage.write(key: _keyConfig, value: config.toJson());
  }

  Future<bool> getAutoReconnect() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoReconnect) ?? false;
  }

  Future<void> setAutoReconnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoReconnect, value);
  }

  Future<bool> getKillSwitch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyKillSwitch) ?? false;
  }

  Future<void> setKillSwitch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKillSwitch, value);
  }

  // 0 = unlimited
  Future<int> getReconnectMaxAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyReconnectMaxAttempts) ?? 5;
  }

  Future<void> setReconnectMaxAttempts(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReconnectMaxAttempts, value);
  }

  Future<int> getReconnectMaxBackoff() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyReconnectMaxBackoff) ?? 60;
  }

  Future<void> setReconnectMaxBackoff(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReconnectMaxBackoff, value);
  }

  Future<SplitTunnelConfig> getSplitTunnelConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_keySplitTunnelMode) ?? 'off';
    final appsJson = prefs.getString(_keySplitTunnelApps) ?? '[]';
    final routesJson = prefs.getString(_keySplitTunnelRoutes) ?? '[]';
    try {
      final apps = (jsonDecode(appsJson) as List).cast<String>();
      final routes = (jsonDecode(routesJson) as List).cast<String>();
      return SplitTunnelConfig.fromJson({
        'mode': modeStr,
        'apps': apps,
        'routes': routes,
      });
    } catch (_) {
      return SplitTunnelConfig.defaultConfig;
    }
  }

  Future<void> setSplitTunnelConfig(SplitTunnelConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final json = config.toJson();
    await prefs.setString(_keySplitTunnelMode, json['mode'] as String);
    await prefs.setString(_keySplitTunnelApps, jsonEncode(json['apps']));
    await prefs.setString(_keySplitTunnelRoutes, jsonEncode(json['routes']));
  }

  // Status-widget footer preference. Stores the chosen footer id (or 'random');
  // see widgets/footer_common.dart. Defaults to the shipped default ('tug').
  Future<String> getFooterWidget() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFooterWidget) ?? 'tug';
  }

  Future<void> setFooterWidget(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFooterWidget, id);
  }
}
