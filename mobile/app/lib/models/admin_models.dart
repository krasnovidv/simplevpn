// Models for the admin API.

class AdminUser {
  final String username;
  final String createdAt;
  final bool disabled;

  const AdminUser({
    required this.username,
    required this.createdAt,
    required this.disabled,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        username: json['username'] as String,
        createdAt: json['created_at'] as String? ?? '',
        disabled: json['disabled'] as bool? ?? false,
      );
}

class AdminStatus {
  final String status;
  final String version;
  final int uptimeSecs;
  final int clientCount;
  final String listen;

  const AdminStatus({
    required this.status,
    required this.version,
    required this.uptimeSecs,
    required this.clientCount,
    required this.listen,
  });

  factory AdminStatus.fromJson(Map<String, dynamic> json) => AdminStatus(
        status: json['status'] as String? ?? '',
        version: json['version'] as String? ?? '',
        uptimeSecs: json['uptime_secs'] as int? ?? 0,
        clientCount: json['client_count'] as int? ?? 0,
        listen: json['listen'] as String? ?? '',
      );
}

class ConnectedClient {
  final String id;
  final String remoteAddr;
  final String connectedAt;
  final int bytesIn;
  final int bytesOut;
  final String assignedIp;
  final String username;

  const ConnectedClient({
    required this.id,
    required this.remoteAddr,
    required this.connectedAt,
    required this.bytesIn,
    required this.bytesOut,
    required this.assignedIp,
    required this.username,
  });

  factory ConnectedClient.fromJson(Map<String, dynamic> json) => ConnectedClient(
        id: json['id'] as String? ?? '',
        remoteAddr: json['remote_addr'] as String? ?? '',
        connectedAt: json['connected_at'] as String? ?? '',
        bytesIn: json['bytes_in'] as int? ?? 0,
        bytesOut: json['bytes_out'] as int? ?? 0,
        assignedIp: json['assigned_ip'] as String? ?? '',
        username: json['username'] as String? ?? '',
      );
}

// Validation constants mirroring server constraints.
class AdminConstraints {
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 1024;
  static const int maxUsernameLength = 255;

  static String? validateUsername(String? value) {
    if (value == null || value.isEmpty) return 'Username is required';
    if (value.length > maxUsernameLength) {
      return 'Username must be ≤$maxUsernameLength characters';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < minPasswordLength) {
      return 'Password must be ≥$minPasswordLength characters';
    }
    if (value.length > maxPasswordLength) {
      return 'Password must be ≤$maxPasswordLength characters';
    }
    return null;
  }
}
