import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Una rotta che non deve esistere dentro l'app (livello A).
class RouteRule {
  RouteRule({required this.id, required this.pattern, required this.label});

  final String id;
  final String pattern;
  final String label;

  late final RegExp regExp = RegExp(pattern);
}

/// Una rotta che esiste ma e' quella sbagliata (livello A).
///
/// E' l'unico caso in cui il livello A riscrive invece di fermare: "Per te"
/// non e' una sezione da vietare, e' il feed sbagliato.
class RewriteRule {
  RewriteRule({
    required this.id,
    required this.label,
    required this.pattern,
    required this.to,
  });

  final String id;
  final String label;
  final String pattern;
  final String to;

  late final RegExp regExp = RegExp(pattern);
}

/// L'etichetta che finisce su `<html data-nd-route>`, perche' una regola CSS
/// possa valere solo sulla pagina giusta.
class RouteTag {
  const RouteTag({required this.tag, required this.pattern});

  final String tag;
  final String pattern;
}

/// Che cosa significa lo zero, per un contatore del canarino.
enum RuleKind {
  /// Deve trovare qualcosa: il silenzio prolungato e' il guasto.
  filter,

  /// Scatta solo se un altro livello ha ceduto prima. Non aver mai trovato
  /// niente e' la norma - la rotta dei Reel non puo' scattare finche' il CSS
  /// nasconde la voce che ci porta - ma se ha lavorato e ha smesso, allora
  /// qualcosa e' successo davvero.
  backstop,

  /// Conta i guai. Lo zero e' la notizia buona; e' il colpo a essere
  /// l'allarme. Senza questa distinzione il canarino griderebbe proprio
  /// quando tutto va bene, che e' il modo piu' rapido per farsi ignorare.
  trouble,
}

/// Identita' di una regola qualsiasi, per il canarino.
class TrackedRule {
  const TrackedRule({
    required this.id,
    required this.label,
    required this.level,
    this.kind = RuleKind.filter,
  });

  final String id;
  final String label;

  /// 'A' rotte, 'B' css, 'C' dom, 'D' risposta.
  final String level;

  final RuleKind kind;
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
  static RuleKind _kindOf(Map<String, dynamic> raw) =>
      raw['backstop'] == true ? RuleKind.backstop : RuleKind.filter;

  late final List<TrackedRule> tracked = [
    for (final r in (_raw['routes'] as List).cast<Map<String, dynamic>>())
      TrackedRule(
        id: r['id'] as String,
        label: r['label'] as String,
        level: 'A',
        kind: _kindOf(r),
      ),
    for (final r in (_raw['css'] as List).cast<Map<String, dynamic>>())
      TrackedRule(id: r['id'] as String, label: r['label'] as String, level: 'B'),
    for (final r in (_raw['dom'] as List).cast<Map<String, dynamic>>())
      TrackedRule(
        id: r['id'] as String,
        label: r['label'] as String,
        level: 'C',
        kind: _kindOf(r),
      ),
    for (final r in ((_raw['response'] as Map<String, dynamic>)['rules'] as List)
        .cast<Map<String, dynamic>>())
      TrackedRule(id: r['id'] as String, label: r['label'] as String, level: 'D'),
    for (final r in rewrites)
      TrackedRule(id: r.id, label: r.label, level: 'A'),
    const TrackedRule(
      id: 'rewrite.failed',
      label: 'Riscritture rinunciate: la rotta di arrivo non ha retto',
      level: 'A',
      kind: RuleKind.trouble,
    ),
    const TrackedRule(
      id: 'dom.refused',
      label: 'Marcature rifiutate perché puntavano troppo in alto',
      level: 'C',
      kind: RuleKind.trouble,
    ),
    const TrackedRule(
      id: 'resp.blocklist',
      label: 'Post nascosti su segnalazione del livello D',
      level: 'D',
    ),
  ];

  late final List<RewriteRule> rewrites = [
    for (final r in ((_raw['rewrites'] as List?) ?? const [])
        .cast<Map<String, dynamic>>())
      RewriteRule(
        id: r['id'] as String,
        label: r['label'] as String,
        pattern: r['pattern'] as String,
        to: r['to'] as String,
      ),
  ];

  /// La riscrittura per questa rotta, se serve. `null` se siamo gia' dove
  /// volevamo: senza questo controllo la riscrittura si rincorrerebbe.
  RewriteRule? rewriteFor(String path, String query) {
    for (final rule in rewrites) {
      if (!rule.regExp.hasMatch(path)) continue;
      if (query.isEmpty ? path == rule.to : '$path?$query' == rule.to) continue;
      return rule;
    }
    return null;
  }

  /// In ordine: la prima che corrisponde vince, e l'ordine e' quello del file
  /// (la ricerca sta dentro esplora, quindi deve venire prima).
  late final List<RouteTag> routeTags = [
    for (final t in ((_raw['routeTags'] as List?) ?? const [])
        .cast<Map<String, dynamic>>())
      RouteTag(tag: t['tag'] as String, pattern: t['pattern'] as String),
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
