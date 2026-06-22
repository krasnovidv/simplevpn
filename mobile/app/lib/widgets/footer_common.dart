/// Shared types and helpers for the swappable "status widget" footers.
///
/// Every footer is a self-contained widget that receives exactly two inputs:
/// the VPN [FooterConnState] and `secs` (seconds connected). The numbers each
/// footer shows are theatre (mood, not telemetry) — see design/handoff_footers.
library;

/// The VPN connection state machine, shared by every footer.
enum FooterConnState { idle, connecting, connected, disconnecting }

/// Which status-widget footer the user has chosen to show under the button.
///
/// [random] is a *mode*, not a concrete footer — it rolls a concrete footer
/// from [footerRandomPool] each launch (and on each idle→connecting in the
/// prototype). [speed] is the legacy plain up/down meter card.
enum FooterKind { random, tug, monster, map, receipt, pet, speed }

/// Concrete footers eligible for "random each launch" (excludes speed).
const List<FooterKind> footerRandomPool = [
  FooterKind.tug,
  FooterKind.monster,
  FooterKind.map,
  FooterKind.receipt,
  FooterKind.pet,
];

/// The default footer shipped to new users.
const FooterKind footerDefault = FooterKind.tug;

class FooterOption {
  final FooterKind kind;
  final String name;
  final String desc;
  final bool dice;
  const FooterOption(this.kind, this.name, this.desc, {this.dice = false});
}

/// Catalog used by the Settings picker. Order matches the design handoff.
const List<FooterOption> footerOptions = [
  FooterOption(FooterKind.random, 'Случайный при запуске',
      'Сюрприз каждую сессию',
      dice: true),
  FooterOption(FooterKind.tug, 'Перетягивание каната', 'Ты против Наблюдателя'),
  FooterOption(
      FooterKind.monster, 'Трафик-гремлин', 'Жрёт твои пакеты'),
  FooterOption(FooterKind.map, 'ASCII-маршрут', 'Живая карта прыжков тоннеля'),
  FooterOption(FooterKind.receipt, 'Чек отказа', 'Твои бумаги, распечатаны'),
  FooterOption(FooterKind.pet, 'Призрак-питомец', 'Твоя анонимность, живая'),
  FooterOption(FooterKind.speed, 'Классические скорости',
      'Простые счётчики вверх/вниз'),
];

/// Stable string ids for persistence.
String footerKindToId(FooterKind k) => switch (k) {
      FooterKind.random => 'random',
      FooterKind.tug => 'tug',
      FooterKind.monster => 'monster',
      FooterKind.map => 'map',
      FooterKind.receipt => 'receipt',
      FooterKind.pet => 'pet',
      FooterKind.speed => 'speed',
    };

FooterKind footerKindFromId(String? id) => switch (id) {
      'random' => FooterKind.random,
      'tug' => FooterKind.tug,
      'monster' => FooterKind.monster,
      'map' => FooterKind.map,
      'receipt' => FooterKind.receipt,
      'pet' => FooterKind.pet,
      'speed' => FooterKind.speed,
      _ => footerDefault,
    };

String footerOptionName(FooterKind k) =>
    footerOptions.firstWhere((o) => o.kind == k).name;

/// HH:MM:SS formatting shared by every footer.
String fmtFooterTime(int s) {
  final h = (s ~/ 3600).toString().padLeft(2, '0');
  final m = ((s ~/ 60) % 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$h:$m:$sec';
}
