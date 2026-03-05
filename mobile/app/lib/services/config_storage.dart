import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_config.dart';

class ConfigStorage {
  static const _keyConfig = 'vpn_config';
  static const _keyAutoReconnect = 'auto_reconnect';
  static const _keyKillSwitch = 'kill_switch';

  Future<VpnConfig?> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyConfig);
    if (json == null) return null;
    return VpnConfig.fromJson(json);
  }

  Future<void> saveConfig(VpnConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyConfig, config.toJson());
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
}
