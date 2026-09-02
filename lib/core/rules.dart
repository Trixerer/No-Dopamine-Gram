import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Una rotta che non deve esistere dentro l'app (livello A).
class RouteRule {
  const RouteRule({required this.id, required this.pattern, required this.label});

  final String id;
  final String pattern;
  final String label;

  late final RegExp regExp = RegExp(pattern);
}

/// Identita' di una regola qualsiasi, per il canarino.
class TrackedRule {
  const TrackedRule({required this.id, required this.label, required this.level});

  final String id;
  final String label;

  /// 'A' rotte, 'B' css, 'C' dom, 'D' risposta.
  final String level;
}

/// Le regole dei quattro livelli, caricate da `assets/rules/rules.json`.
///
/// Sono dati e non codice di proposito: quando Instagram cambia qualcosa si
/// aggiorna il file, non l'app.
class RuleSet {
  RuleSet._(this._raw)
      : version = _raw['version'] as int,
        updated = _raw['updated'] as String,
        home = _raw['home'] as String,
        host = _raw['host'] as String;

  final Map<String, dynamic> _raw;

  final int version;
  final String updated;
  final String home;
  final String host;

  static Future<RuleSet> load() async {
    final text = await rootBundle.loadString('assets/rules/rules.json');
    return RuleSet._(jsonDecode(text) as Map<String, dynamic>);
  }

  late final List<RouteRule> routes = [
    for (final r in (_raw['routes'] as List).cast<Map<String, dynamic>>())
      RouteRule(
        id: r['id'] as String,
        pattern: r['pattern'] as String,
        label: r['label'] as String,
      ),
  ];

  /// Il livello D è spento per impostazione predefinita: con il feed
  /// cronologico non serve. Resta pronto per quando servirà.
  bool get responseEnabledByDefault =>
      (_raw['response'] as Map<String, dynamic>)['enabled'] as bool? ?? false;

  /// Ogni regola che il canarino può vedere passare.
  late final List<TrackedRule> tracked = [
    for (final r in routes) TrackedRule(id: r.id, label: r.label, level: 'A'),
    for (final r in (_raw['css'] as List).cast<Map<String, dynamic>>())
      TrackedRule(id: r['id'] as String, label: r['label'] as String, level: 'B'),
    for (final r in (_raw['dom'] as List).cast<Map<String, dynamic>>())
      TrackedRule(id: r['id'] as String, label: r['label'] as String, level: 'C'),
    for (final r in ((_raw['response'] as Map<String, dynamic>)['rules'] as List)
        .cast<Map<String, dynamic>>())
      TrackedRule(id: r['id'] as String, label: r['label'] as String, level: 'D'),
    const TrackedRule(
      id: 'resp.blocklist',
      label: 'Post nascosti su segnalazione del livello D',
      level: 'D',
    ),
  ];

  RouteRule? blockedRouteFor(String path) {
    for (final rule in routes) {
      if (rule.regExp.hasMatch(path)) return rule;
    }
    return null;
  }

  /// Le regole così come le vede la pagina, con il livello D allineato alla
  /// scelta dell'utente invece che al valore scritto nel file.
  String asInjectedJson({required bool responseEnabled}) {
    final copy = jsonDecode(jsonEncode(_raw)) as Map<String, dynamic>;
    (copy['response'] as Map<String, dynamic>)['enabled'] = responseEnabled;
    return jsonEncode(copy);
  }
}
