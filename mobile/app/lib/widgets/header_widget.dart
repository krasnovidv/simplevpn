import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HeaderWidget extends StatelessWidget {
  final String subtitle;
  final VoidCallback? onSettingsTap;

  const HeaderWidget({
    super.key,
    required this.subtitle,
    this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 22,
                    color: AppColors.white,
                    letterSpacing: 1,
                  ),
                  children: const [
                    TextSpan(text: 'RKN'),
                    TextSpan(text: '·', style: TextStyle(color: AppColors.magenta)),
                    TextSpan(text: 'PNH'),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onSettingsTap,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.dim2, width: 1),
                  ),
                  child: const Icon(Icons.settings, size: 16, color: AppColors.dim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 12,
              color: AppColors.dim,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
