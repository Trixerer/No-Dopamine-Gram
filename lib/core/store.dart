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
  });

  final TrackedRule rule;
  final int hits;
  final DateTime? lastHit;

  /// Non ha mai trovato niente: o Instagram è cambiato, o la regola era
  /// sbagliata dall'inizio.
  bool get neverSeen => hits == 0;

  /// Funzionava e ha smesso. È il caso che conta davvero.
  bool get wentQuiet =>
      hits > 0 &&
      lastHit != null &&
      DateTime.now().difference(lastHit!) > const Duration(days: 14);

  bool get isAlarming => wentQuiet || neverSeen;
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
    batch.forEach((id, count) {
      _hits[id] = (_hits[id] ?? 0) + count;
      _last[id] = now;
    });
    _prefs.setString(_kHits, jsonEncode(_hits));
    _prefs.setString(_kLast, jsonEncode(_last));
    notifyListeners();
  }

  List<RuleHealth> get health => [
        for (final rule in rules.tracked)
          RuleHealth(
            rule: rule,
            hits: _hits[rule.id] ?? 0,
            lastHit: _last[rule.id] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(_last[rule.id]!),
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
