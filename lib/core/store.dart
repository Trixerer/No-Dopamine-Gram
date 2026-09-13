import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rules.dart';

/// Stato di salute di una singola regola.
class RuleHealth {
  const RuleHealth({
    required this.rule,
    required this.hits,
    required this.lastHit,
    required this.dormant,
  });

  final TrackedRule rule;
  final int hits;
  final DateTime? lastHit;

  /// Il livello a cui appartiene è spento: il suo silenzio non dice niente,
  /// né in bene né in male.
  final bool dormant;

  bool get _isFilter => rule.kind == RuleKind.filter;

  /// Non ha mai trovato niente: o Instagram è cambiato, o la regola era
  /// sbagliata dall'inizio. Non vale per le reti di sicurezza, che a non
  /// scattare mai fanno il loro mestiere.
  bool get neverSeen => _isFilter && hits == 0;

  /// Funzionava e ha smesso. È il caso che conta davvero, e conta anche per
  /// le reti di sicurezza: se una ha lavorato e poi ha smesso, è successo
  /// qualcosa.
  bool get wentQuiet =>
      (_isFilter || rule.kind == RuleKind.backstop) &&
      hits > 0 &&
      lastHit != null &&
      DateTime.now().difference(lastHit!) > const Duration(days: 14);

  /// Un contatore di guai che ha contato qualcosa.
  bool get misfired => rule.kind == RuleKind.trouble && hits > 0;

  bool get isAlarming => !dormant && (wentQuiet || neverSeen || misfired);
}

/// Conteggi del canarino e preferenze, su disco.
///
/// Un filtro che fallisce in silenzio rimette la dopamina davanti senza
/// avvisare: questa classe esiste perché quel fallimento faccia rumore.
class NdStore extends ChangeNotifier {
  NdStore(this._prefs, this.rules);

  static const _kHits = 'nd.hits';
  static const _kLast = 'nd.last';
  static const _kSessions = 'nd.sessions';
  static const _kResponse = 'nd.response_enabled';

  final SharedPreferences _prefs;
  final RuleSet rules;

  Map<String, int> _hits = {};
  Map<String, int> _last = {};

  /// Il ponte JavaScript è raggiungibile da qualunque frame della pagina,
  /// iframe di terzi compresi: accettiamo solo gli id che conosciamo, così un
  /// frame estraneo non può riempire le preferenze di chiavi inventate.
  late final Set<String> _knownIds = {for (final r in rules.tracked) r.id};

  static Future<NdStore> open(RuleSet rules) async {
    final prefs = await SharedPreferences.getInstance();
    final store = NdStore(prefs, rules)
      .._hits = _readMap(prefs, _kHits)
      .._last = _readMap(prefs, _kLast);
    await prefs.setInt(_kSessions, store.sessions + 1);
    return store;
  }

  static Map<String, int> _readMap(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  int get sessions => _prefs.getInt(_kSessions) ?? 0;

  bool get responseEnabled =>
      _prefs.getBool(_kResponse) ?? rules.responseEnabledByDefault;

  Future<void> setResponseEnabled(bool value) async {
    await _prefs.setBool(_kResponse, value);
    notifyListeners();
  }

  /// Un lotto di conteggi arrivato dalla pagina.
  void record(Map<String, int> batch) {
    if (batch.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    batch.forEach((id, count) {
      if (!_knownIds.contains(id)) return;
      _hits[id] = (_hits[id] ?? 0) + count;
      _last[id] = now;
      changed = true;
    });
    if (!changed) return;
    _prefs.setString(_kHits, jsonEncode(_hits));
    _prefs.setString(_kLast, jsonEncode(_last));
    notifyListeners();
  }

  /// Col livello D spento, le sue regole non possono trovare niente — e
  /// `css.neutralized` nasconde solo ciò che il livello D segnala, quindi
  /// tace insieme a lui.
  bool _dormant(TrackedRule rule) =>
      !responseEnabled && (rule.level == 'D' || rule.id == 'css.neutralized');

  List<RuleHealth> get health => [
        for (final rule in rules.tracked)
          RuleHealth(
            rule: rule,
            hits: _hits[rule.id] ?? 0,
            lastHit: _last[rule.id] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(_last[rule.id]!),
            dormant: _dormant(rule),
          ),
      ];

  /// Sotto le tre sessioni non allarmiamo: le regole non hanno ancora avuto
  /// occasione di incontrare le pagine giuste.
  List<RuleHealth> get alarming =>
      sessions < 3 ? const [] : health.where((h) => h.isAlarming).toList();

  Future<void> reset() async {
    _hits = {};
    _last = {};
    await _prefs.remove(_kHits);
    await _prefs.remove(_kLast);
    notifyListeners();
  }
}
