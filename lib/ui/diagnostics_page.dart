import 'package:flutter/material.dart';

import '../core/store.dart';

/// Il pannello del canarino: cosa sta ancora funzionando e cosa ha smesso.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, required this.store});

  final NdStore store;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _needsReload = false;

  static const _levelNames = {
    'A': 'Navigazione',
    'B': 'CSS',
    'C': 'DOM',
    'D': 'Risposta',
  };

  String _lastSeen(DateTime? when) {
    if (when == null) return 'mai';
    final days = DateTime.now().difference(when).inDays;
    if (days == 0) return 'oggi';
    if (days == 1) return 'ieri';
    return '$days giorni fa';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = widget.store;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_needsReload);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Stato dei filtri')),
        body: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final health = store.health;
            final alarming = store.alarming;
            final byLevel = <String, List<RuleHealth>>{};
            for (final h in health) {
              byLevel.putIfAbsent(h.rule.level, () => []).add(h);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: alarming.isEmpty
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alarming.isEmpty
                              ? 'Tutte le regole stanno lavorando'
                              : '${alarming.length} regole non trovano più niente',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          alarming.isEmpty
                              ? 'Sessioni registrate: ${store.sessions}.'
                              : 'Instagram potrebbe aver cambiato qualcosa. '
                                  'Finché non le sistemi, quel contenuto ti arriva davanti.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Filtro sulla risposta (livello D)'),
                  subtitle: const Text(
                    'Legge le risposte di Instagram senza modificarle, per '
                    'riconoscere i contenuti suggeriti prima che vengano '
                    'disegnati. Serve solo se il feed cronologico si sporca.',
                  ),
                  value: store.responseEnabled,
                  onChanged: (value) async {
                    await store.setResponseEnabled(value);
                    setState(() => _needsReload = true);
                  },
                ),
                const Divider(height: 32),
                for (final level in const ['A', 'B', 'C', 'D'])
                  if (byLevel[level] != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, top: 8),
                      child: Text(
                        'Livello $level · ${_levelNames[level]}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    for (final h in byLevel[level]!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          h.isAlarming && store.sessions >= 3
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: h.isAlarming && store.sessions >= 3
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                          size: 20,
                        ),
                        title: Text(h.rule.label),
                        subtitle: Text(
                          '${h.rule.id} · ${h.hits} volte · ultima: ${_lastSeen(h.lastHit)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                const Divider(height: 32),
                TextButton.icon(
                  onPressed: () => store.reset(),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Azzera i conteggi'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
