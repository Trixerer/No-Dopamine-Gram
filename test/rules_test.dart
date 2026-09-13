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

    test('il livello A blocca i reel, non il resto', () async {
      final rules = await RuleSet.load();
      expect(rules.blockedRouteFor('/reels/'), isNotNull);
      expect(rules.blockedRouteFor('/reels/audio/123/'), isNotNull);
      expect(rules.blockedRouteFor('/'), isNull);
      expect(rules.blockedRouteFor('/p/Cxyz123/'), isNull);
      expect(rules.blockedRouteFor('/direct/inbox/'), isNull);
      // Un profilo che comincia per "reel" non è la sezione Reel.
      expect(rules.blockedRouteFor('/reelsofcheese'), isNull);
      // La ricerca passa: serve a trovare account, e la griglia di post che
      // c'è sopra la toglie il livello B, non il livello A.
      expect(rules.blockedRouteFor('/explore/'), isNull);
      expect(rules.blockedRouteFor('/explore/search/'), isNull);
    });

    test('ogni pagina riceve al più un\'etichetta di rotta', () async {
      final rules = await RuleSet.load();
      String tagFor(String path) {
        for (final t in rules.routeTags) {
          if (RegExp(t.pattern).hasMatch(path)) return t.tag;
        }
        return 'other';
      }

      // L'ordine conta: la ricerca è dentro esplora e deve vincere lei.
      expect(tagFor('/explore/search/?q=x'), 'search');
      expect(tagFor('/explore/'), 'explore');
      expect(tagFor('/'), 'home');
      expect(tagFor('/direct/inbox/'), 'direct');
      expect(tagFor('/qualcuno/'), 'other');
    });

    test('la riscrittura porta casa sul feed cronologico', () async {
      final rules = await RuleSet.load();
      expect(rules.rewriteFor('/', '')?.to, '/?variant=following');
      // Già arrivati: non si riscrive di nuovo, o la riscrittura si rincorre.
      expect(rules.rewriteFor('/', 'variant=following'), isNull);
      // Tutto il resto non si tocca.
      expect(rules.rewriteFor('/direct/inbox/', ''), isNull);
      expect(rules.rewriteFor('/qualcuno/', ''), isNull);
      expect(rules.rewriteFor('/p/Cxyz123/', ''), isNull);
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
