import 'package:flutter/material.dart';

import '../models/vpn_config.dart';
import '../services/app_prefs.dart';
import '../theme/chrome.dart';
import '../widgets/chrome/backdrop.dart';
import '../widgets/chrome/chrome_orb.dart';
import '../widgets/chrome/chrome_ui.dart';
import 'app_scope.dart';
import 'qr_scanner_screen.dart';

/// First launch. Without access configured it asks for the invite QR first;
/// with it, «Спрятаться» requests the system VPN permission and connects.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _asking = false;

  Future<void> _scan() async {
    final app = AppScope.read(context);
    final cfg = await Navigator.of(context).push<VpnConfig>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (cfg != null) await app.saveConfig(cfg);
  }

  Future<void> _hide() async {
    final app = AppScope.read(context);
    setState(() => _asking = true);
    final ok = await app.connect();
    if (!mounted) return;
    setState(() => _asking = false);
    if (ok) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final app = AppScope.of(context);
    final hasAccess = app.config != null;
    final animate = AppPrefs.instance.animate(context);
    final mood = _asking ? OrbMood.connecting : OrbMood.idle;

    return Scaffold(
      body: ChromeBackdrop(
        mood: mood,
        animate: animate,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const TopBar(),
              Expanded(
                child: Center(
                  child: ChromeOrb(mood: mood, size: (box.maxHeight * 0.38).clamp(200.0, 300.0), animate: animate),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Headline(lines: ['Привет,', 'невидимка'], size: 38, hot: true),
                  const SizedBox(height: 14),
                  EnterAnim(
                    key: ValueKey(hasAccess),
                    child: Text(
                      hasAccess
                          ? 'Один сервер, одна кнопка, ноль вопросов. Сейчас Android спросит разрешение — не пугайся, он всех спрашивает.'
                          : 'Одна кнопка, ноль вопросов. Сначала отсканируй QR-код из приглашения — или просто открой ссылку, которую тебе прислали.',
                      style: bodyStyle(c, height: 1.5),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  PrimaryButton(
                    label: hasAccess ? 'Спрятаться' : 'Сканировать QR',
                    icon: Icons.chevron_right_rounded,
                    iconTrailing: true,
                    shine: animate,
                    onTap: _asking ? null : (hasAccess ? _hide : _scan),
                  ),
                  const SizedBox(height: 14),
                  Text('Без рекламы · без регистрации · без одобрения',
                      textAlign: TextAlign.center, style: bodyStyle(c, size: 12.5, weight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
