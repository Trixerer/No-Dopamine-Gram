import 'package:flutter_test/flutter_test.dart';
import 'package:no_dopamine_gram/core/rules.dart';
import 'package:no_dopamine_gram/core/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<NdStore> open({int sessions = 0}) async {
    SharedPreferences.setMockInitialValues({'nd.sessions': sessions});
    return NdStore.open(await RuleSet.load());
  }

  Iterable<String> idsOf(List<RuleHealth> health) => health.map((h) => h.rule.id);

  test('sotto le tre sessioni non allarma mai', () async {
    final store = await open();
    expect(store.alarming, isEmpty);
  });

  test('i contatori di guai tacciono finché non contano', () async {
    final store = await open(sessions: 10);

    // A zero sono la notizia buona: non devono comparire.
    expect(idsOf(store.alarming), isNot(contains('dom.refused')));
    expect(idsOf(store.alarming), isNot(contains('rewrite.failed')));

    store.record({'dom.refused': 1});
    expect(idsOf(store.alarming), contains('dom.refused'));
  });

  test('col livello D spento le sue regole non allarmano', () async {
    final store = await open(sessions: 10);
    expect(store.responseEnabled, isFalse);

    final dormienti = store.health.where((h) => h.dormant).toList();
    expect(dormienti, isNotEmpty);
    expect(dormienti.every((h) => !h.isAlarming), isTrue);
    // `css.neutralized` è del livello B ma nasconde solo ciò che segnala il D.
    expect(idsOf(dormienti), contains('css.neutralized'));

    await store.setResponseEnabled(true);
    expect(store.health.where((h) => h.dormant), isEmpty);
  });

  test('un filtro che non ha mai trovato niente allarma', () async {
    final store = await open(sessions: 10);
    final muta = store.health.firstWhere(
      (h) => h.rule.kind == RuleKind.filter && !h.dormant,
    );
    expect(muta.neverSeen, isTrue);
    expect(idsOf(store.alarming), contains(muta.rule.id));

    // Appena trova qualcosa, tace.
    store.record({muta.rule.id: 1});
    expect(idsOf(store.alarming), isNot(contains(muta.rule.id)));
  });

  test('i conteggi da id sconosciuti vengono scartati', () async {
    final store = await open(sessions: 10);
    store.record({'id.inventato.da.un.iframe': 99});
    expect(idsOf(store.health), isNot(contains('id.inventato.da.un.iframe')));
  });
}
