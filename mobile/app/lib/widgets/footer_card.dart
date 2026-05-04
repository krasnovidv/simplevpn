import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FooterCard extends StatelessWidget {
  final String route;
  final String publicIp;
  final String uptime;
  final double downMbps;
  final double upMbps;
  final bool isConnected;

  const FooterCard({
    super.key,
    required this.route,
    required this.publicIp,
    required this.uptime,
    required this.downMbps,
    required this.upMbps,
    this.isConnected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.dim2, width: 1),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FooterRow(
                  label: 'ROUTE',
                  value: route,
                  accent: isConnected ? AppColors.cyan : AppColors.dim,
                ),
                _FooterRow(
                  label: 'PUBLIC IP',
                  value: publicIp,
                  accent: isConnected ? AppColors.cyan : AppColors.magenta,
                ),
                _FooterRow(
                  label: 'UPTIME',
                  value: uptime,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _SpeedTile(label: '↓ DOWN', value: downMbps)),
                    const SizedBox(width: 12),
                    Expanded(child: _SpeedTile(label: '↑ UP', value: upMbps)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterRow extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _FooterRow({
    required this.label,
    required this.value,
    this.accent = AppColors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.dim2,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 10,
              color: AppColors.dim,
              letterSpacing: 1.5,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 13,
                color: accent,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedTile extends StatelessWidget {
  final String label;
  final double value;

  const _SpeedTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 9,
              color: AppColors.dim,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'MB/s',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 10,
                  color: AppColors.dim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
