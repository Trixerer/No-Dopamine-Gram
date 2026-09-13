import 'package:flutter/material.dart';

import 'ui/shell_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NoDopamineGramApp());
}

class NoDopamineGramApp extends StatelessWidget {
  const NoDopamineGramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Quello che si legge nelle app recenti. Il nome sulla home viene invece
      // da `android:label` nel manifest: vanno tenuti allineati a mano.
      title: 'NDG',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      // Il tema si vede solo nelle diagnostiche e nel banner del canarino:
      // tutto il resto dello schermo è la pagina di Instagram.
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B5BDB),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B5BDB),
        brightness: Brightness.dark,
      ),
      home: const ShellPage(),
    );
  }
}
