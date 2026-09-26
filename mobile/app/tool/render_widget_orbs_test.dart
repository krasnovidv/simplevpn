// Renders static orb frames for the Android home-screen widgets (which cannot
// run the animated Flutter orb). Regenerate after changing ChromeOrb:
//   flutter test --update-goldens tool/render_widget_orbs_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/theme/chrome.dart';
import 'package:simplevpn/widgets/chrome/chrome_orb.dart';

const _res = '../android/app/src/main/res';

void main() {
  for (final dark in [false, true]) {
    for (final mood in [OrbMood.idle, OrbMood.connecting, OrbMood.connected]) {
      testWidgets('orb ${mood.name} ${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = const Size(420, 420);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: buildChromeTheme(dark ? Brightness.dark : Brightness.light),
            child: Center(
              child: RepaintBoundary(
                child: SizedBox(
                  width: 420,
                  height: 420,
                  // The orb's glow and orbit reach past its box.
                  child: Center(child: ChromeOrb(mood: mood, size: 300, animate: false)),
                ),
              ),
            ),
          ),
        ));
        final dir = dark ? 'drawable-night-nodpi' : 'drawable-nodpi';
        await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('$_res/$dir/orb_${mood.name}.png'));
      });
    }
  }
}
