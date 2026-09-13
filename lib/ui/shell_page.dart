import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/rules.dart';
import '../core/store.dart';
import '../web/ig_web_view.dart';
import 'diagnostics_page.dart';

/// Tutto quello che deve esistere prima di poter disegnare la WebView.
class _Boot {
  const _Boot({
    required this.rules,
    required this.store,
    required this.bootstrapJs,
    required this.userAgent,
  });

  final RuleSet rules;
  final NdStore store;
  final String bootstrapJs;
  final String userAgent;
}

/// L'unica schermata dell'app: Instagram a tutto schermo e, sopra, solo ciò
/// che serve quando qualcosa si rompe.
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> with WidgetsBindingObserver {
  late Future<_Boot> _boot;

  /// Cambia quando la WebView va ricreata: gli user script sono
  /// `initialUserScripts` e non si aggiornano a caldo.
  GlobalKey<IgWebViewState> _webKey = GlobalKey<IgWebViewState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot = _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<_Boot> _load() async {
    final rules = await RuleSet.load();
    final (store, bootstrapJs, userAgent) = await (
      NdStore.open(rules),
      rootBundle.loadString('assets/js/bootstrap.js'),
      _resolveUserAgent(),
    ).wait;
    return _Boot(
      rules: rules,
      store: store,
      bootstrapJs: bootstrapJs,
      userAgent: userAgent,
    );
  }

  /// Lo User-Agent vero della WebView, senza i due segnali che dicono
  /// "non sono un browser": `; wv` e il token `Version/4.0`.
  ///
  /// Si parte dal default del motore invece di scriverne uno a mano perché i
  /// Client Hints riportano comunque la versione reale di Chromium: un UA
  /// inventato sarebbe a sua volta un'incoerenza.
  Future<String> _resolveUserAgent() async {
    final base = await InAppWebViewController.getDefaultUserAgent();
    return base
        .replaceAll('; wv', '')
        .replaceAll(RegExp(r'Version/\d+\.\d+ '), '')
        .trim();
  }

  /// Alla pausa scriviamo i cookie su disco: il login dentro una WebView è il
  /// momento in cui Meta fa scattare le challenge, perderlo costa caro.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _webKey.currentState?.flushCookies();
    }
  }

  Future<void> _onBack() async {
    final wentBack = await _webKey.currentState?.goBackIfPossible() ?? false;
    // Niente cronologia da risalire: il tasto indietro fa quello che ci si
    // aspetta da un'app, esce.
    if (!wentBack) await SystemNavigator.pop();
  }

  Future<void> _openDiagnostics(NdStore store) async {
    final needsReload = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DiagnosticsPage(store: store)),
    );
    if (needsReload == true && mounted) {
      setState(() => _webKey = GlobalKey<IgWebViewState>());
    }
  }

  void _onRouteBlocked(String label) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$label: non esiste qui dentro.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Boot>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BootError(
            error: snapshot.error!,
            onRetry: () => setState(() => _boot = _load()),
          );
        }
        final boot = snapshot.data;
        if (boot == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _shell(boot);
      },
    );
  }

  Widget _shell(_Boot boot) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              IgWebView(
                key: _webKey,
                rules: boot.rules,
                store: boot.store,
                userAgent: boot.userAgent,
                bootstrapJs: boot.bootstrapJs,
                onRouteBlocked: _onRouteBlocked,
              ),
              // L'app è invisibile finché qualcosa non si rompe: è il senso
              // del canarino.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: boot.store,
                  builder: (context, _) {
                    final alarming = boot.store.alarming;
                    if (alarming.isEmpty) return const SizedBox.shrink();
                    return _CanaryBanner(
                      count: alarming.length,
                      onTap: () => _openDiagnostics(boot.store),
                    );
                  },
                ),
              ),
              // L'accesso alle diagnostiche, nell'angolo, a pressione lunga.
              Positioned(
                top: 0,
                left: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPress: () => _openDiagnostics(boot.store),
                  child: const SizedBox(width: 56, height: 56),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanaryBanner extends StatelessWidget {
  const _CanaryBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  count == 1
                      ? 'Una regola non trova più niente.'
                      : '$count regole non trovano più niente.',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: scheme.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('I filtri non si sono caricati.'),
              const SizedBox(height: 8),
              // Senza regole la WebView sarebbe Instagram e basta: meglio non
              // aprirla affatto che aprirla senza filtri.
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Riprova')),
            ],
          ),
        ),
      ),
    );
  }
}
