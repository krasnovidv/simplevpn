import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'screens/root_screen.dart';
import 'services/app_prefs.dart';
import 'theme/chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await AppPrefs.instance.load();
  runApp(const ProviderScope(child: SimpleVPNApp()));
}

class SimpleVPNApp extends StatelessWidget {
  const SimpleVPNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppPrefs.instance.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'RKNPNH',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        themeMode: mode,
        theme: buildChromeTheme(Brightness.light),
        darkTheme: buildChromeTheme(Brightness.dark),
        home: const RootScreen(),
      ),
    );
  }
}
