import 'dart:developer' as developer;

/// Validates that [value] is a valid IPv4 address with port (e.g. 192.168.1.1:443).
/// Returns null if valid, or an error message string if invalid.
String? validateServerAddress(String value) {
  if (value.isEmpty) {
    developer.log('Validation: empty server address', name: 'validators');
    return 'Server address is required';
  }

  final colonIndex = value.lastIndexOf(':');
  if (colonIndex == -1) {
    developer.log('Validation: no colon separator found', name: 'validators');
    return 'Must be IP:port (e.g. 192.168.1.1:443)';
  }

  final ipPart = value.substring(0, colonIndex);
  final portPart = value.substring(colonIndex + 1);

  // Validate IPv4
  final octets = ipPart.split('.');
  if (octets.length != 4) {
    developer.log('Validation: expected 4 octets, got ${octets.length}',
        name: 'validators');
    return 'Invalid IP address (need 4 octets)';
  }

  for (final octet in octets) {
    final n = int.tryParse(octet);
    if (n == null || n < 0 || n > 255) {
      developer.log('Validation: invalid octet value', name: 'validators');
      return 'Invalid IP address (octets must be 0-255)';
    }
    // Reject leading zeros (e.g. "01", "001") except "0" itself
    if (octet.length > 1 && octet.startsWith('0')) {
      developer.log('Validation: octet has leading zero', name: 'validators');
      return 'Invalid IP address (no leading zeros)';
    }
  }

  // Validate port
  if (portPart.isEmpty) {
    developer.log('Validation: empty port', name: 'validators');
    return 'Port is required';
  }

  final port = int.tryParse(portPart);
  if (port == null || port < 1 || port > 65535) {
    developer.log('Validation: invalid port number', name: 'validators');
    return 'Port must be 1-65535';
  }

  return null;
}
