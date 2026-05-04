import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusCopy extends StatelessWidget {
  final String caption;
  final String cta;
  final Color ctaColor;

  const StatusCopy({
    super.key,
    required this.caption,
    required this.cta,
    required this.ctaColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Column(
        key: ValueKey('$caption|$cta'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            caption,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.dim,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            cta,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 22,
              color: ctaColor,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
