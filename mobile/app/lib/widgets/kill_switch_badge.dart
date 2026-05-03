import 'package:flutter/material.dart';

enum KillSwitchBadgeKind { blocked, unsupported }

class KillSwitchBadge extends StatelessWidget {
  final KillSwitchBadgeKind kind;
  final VoidCallback? onTap;

  const KillSwitchBadge({super.key, required this.kind, this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      KillSwitchBadgeKind.blocked =>
        'Traffic blocked — kill switch active. Tap to disable.',
      KillSwitchBadgeKind.unsupported =>
        'Kill switch requires iOS 14.2 or later.',
    };

    return Tooltip(
      message: switch (kind) {
        KillSwitchBadgeKind.blocked =>
          'Kill switch is blocking all network traffic until you disconnect.',
        KillSwitchBadgeKind.unsupported =>
          'Your iOS version does not support the kill switch feature (requires 14.2+).',
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
