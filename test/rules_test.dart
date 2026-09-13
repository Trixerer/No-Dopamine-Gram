import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_dopamine_gram/core/rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RuleSet', () {
    test('si carica dall\'asset dichiarato nel pubspec', () async {
      final rules = await RuleSet.load();
      expect(rules.host, 'instagram.com');
      expect(rules.home, startsWith('https://www.instagram.com/'));
      expect(rules.routes, isNotEmpty);
    });

    test('ogni regola tracciata ha un id unico', () async {
      final rules = await RuleSet.load();
      final ids = rules.tracked.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(rules.tracked.map((r) => r.level).toSet(), {'A', 'B', 'C', 'D'});
    });

    test('il livello A blocca i reel e l\'esplora, non il resto', () async {
      final rules = await RuleSet.load();
      expect(rules.blockedRouteFor('/reels/'), isNotNull);
      expect(rules.blockedRouteFor('/explore/'), isNotNull);
      expect(rules.blockedRouteFor('/explore/people/'), isNotNull);
      expect(rules.blockedRouteFor('/'), isNull);
      expect(rules.blockedRouteFor('/p/Cxyz123/'), isNull);
      expect(rules.blockedRouteFor('/direct/inbox/'), isNull);
      // Un profilo che comincia per "reel" non è la sezione Reel.
      expect(rules.blockedRouteFor('/reelsofcheese'), isNull);
    });

    test('asInjectedJson allinea il livello D alla scelta dell\'utente', () async {
      final rules = await RuleSet.load();
      Map<String, dynamic> response(bool enabled) =>
          (jsonDecode(rules.asInjectedJson(responseEnabled: enabled))
              as Map<String, dynamic>)['response'] as Map<String, dynamic>;

      expect(response(true)['enabled'], isTrue);
      expect(response(false)['enabled'], isFalse);
      // La copia non deve intaccare le regole originali.
      expect(rules.responseEnabledByDefault, isFalse);
    });
  });
}
