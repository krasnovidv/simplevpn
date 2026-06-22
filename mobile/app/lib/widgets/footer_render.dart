import 'package:flutter/material.dart';
import 'footer_common.dart';
import 'footer_card.dart';
import 'footer_map.dart';
import 'footer_pet.dart';
import 'footer_receipt.dart';
import 'footer_tugwar.dart';
import 'footer_monster.dart';

/// Renders the status-widget footer chosen by the user. Mirrors the
/// `FooterRender` switch from design/handoff_footers/main-screens.jsx.
///
/// [kind] must already be resolved to a concrete footer (never
/// [FooterKind.random] — resolve that to a rolled footer before rendering).
class FooterRender extends StatelessWidget {
  final FooterKind kind;
  final FooterConnState state;
  final int secs;

  const FooterRender({
    super.key,
    required this.kind,
    required this.state,
    required this.secs,
  });

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case FooterKind.tug:
        return FooterTugWar(state: state, secs: secs);
      case FooterKind.monster:
        return FooterMonster(state: state, secs: secs);
      case FooterKind.map:
        return FooterMap(state: state, secs: secs);
      case FooterKind.receipt:
        return FooterReceipt(state: state, secs: secs);
      case FooterKind.pet:
        return FooterPet(state: state, secs: secs);
      case FooterKind.speed:
      case FooterKind.random: // safety fallback; random should be pre-resolved
        return _classicSpeeds();
    }
  }

  // Legacy "Classic Speeds" card. The home screen no longer tracks live
  // throughput, so these numbers are theatre (matching the design prototype).
  Widget _classicSpeeds() {
    final connected = state == FooterConnState.connected;
    return FooterCard(
      route: connected ? 'Рейкьявик, Исландия' : '— маршрут не выбран —',
      publicIp: connected ? '185.93.0.42 \u{1f1ee}\u{1f1f8}' : '93.184.27.11 (real)',
      uptime: connected ? fmtFooterTime(secs) : '—',
      // FooterCard renders MB/s above 1024 KB/s; scale to show big MB numbers.
      downKbps: connected ? 88.1 * 1024 : 0,
      upKbps: connected ? 12.4 * 1024 : 0,
      isConnected: connected,
    );
  }
}
