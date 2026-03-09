import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_config.dart';

class ConfigStorage {
  static const _keyConfig = 'vpn_config';
  static const _keyAutoReconnect = 'auto_reconnect';
  static const _keyKillSwitch = 'kill_switch';

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
}
