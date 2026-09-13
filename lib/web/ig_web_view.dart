import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/rules.dart';
import '../core/store.dart';

/// Gli host che possono vivere dentro l'app. Tutto il resto esce nel browser
/// di sistema: qui dentro esiste solo Instagram.
const _allowedHosts = <String>{
  'instagram.com',
  'www.instagram.com',
  'accountscenter.instagram.com',
  'help.instagram.com',
  'about.instagram.com',
  'facebook.com',
  'www.facebook.com',
  'm.facebook.com',
  'accountscenter.facebook.com',
};

bool _isAllowedHost(String host) {
  if (_allowedHosts.contains(host)) return true;
  return host.endsWith('.cdninstagram.com') || host.endsWith('.fbcdn.net');
}

/// La WebView e i quattro livelli di filtro che ci vivono dentro.
class IgWebView extends StatefulWidget {
  const IgWebView({
    super.key,
    required this.rules,
    required this.store,
    required this.userAgent,
    required this.bootstrapJs,
    required this.onRouteBlocked,
  });

  final RuleSet rules;
  final NdStore store;
  final String userAgent;
  final String bootstrapJs;
  final void Function(String label) onRouteBlocked;

  @override
  State<IgWebView> createState() => IgWebViewState();
}

class IgWebViewState extends State<IgWebView> {
  InAppWebViewController? _controller;

  Future<bool> goBackIfPossible() async {
    final controller = _controller;
    if (controller == null) return false;
    if (await controller.canGoBack()) {
      await controller.goBack();
      return true;
    }
    return false;
  }

  Future<void> flushCookies() => CookieManager.instance().flush();

  Future<void> goHome() async {
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.rules.home)),
    );
  }

  UnmodifiableListView<UserScript> get _userScripts {
    final json = widget.rules.asInjectedJson(
      responseEnabled: widget.store.responseEnabled,
    );
    return UnmodifiableListView([
      // Le regole arrivano prima dello script che le usa, entrambe prima di
      // qualunque riga di Instagram.
      UserScript(
        source: 'window.__ND_RULES__ = $json;',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      UserScript(
        source: widget.bootstrapJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]);
  }

  void _registerHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'nd_canary',
      callback: (args) {
        if (args.isEmpty || args.first is! Map) return;
        final batch = <String, int>{};
        (args.first as Map).forEach((key, value) {
          if (value is num) batch['$key'] = value.toInt();
        });
        widget.store.record(batch);
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'nd_route_blocked',
      callback: (args) {
        if (args.isEmpty || args.first is! Map) return;
        final label = (args.first as Map)['label'];
        if (label is String) widget.onRouteBlocked(label);
      },
    );

    // Utile solo mentre si sviluppa: dice su che rotta si trova la SPA.
    controller.addJavaScriptHandler(
      handlerName: 'nd_route',
      callback: (args) {
        if (kDebugMode && args.isNotEmpty) debugPrint('[nd] rotta: ${args.first}');
        return null;
      },
    );
  }

  Future<NavigationActionPolicy> _gate(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;

    // I frame interni non li tocchiamo: il livello A vale per le rotte vere.
    if (action.isForMainFrame != true) return NavigationActionPolicy.ALLOW;

    if (!_isAllowedHost(uri.host)) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
      return NavigationActionPolicy.CANCEL;
    }

    final blocked = widget.rules.blockedRouteFor(uri.path);
    if (blocked != null) {
      widget.store.record({blocked.id: 1});
      widget.onRouteBlocked(blocked.label);
      return NavigationActionPolicy.CANCEL;
    }

    // I caricamenti veri di pagina passano di qui; dentro la SPA ci pensa
    // `bootstrap.js`. Entrambi servono: questo è il caso del primo avvio e
    // dei link esterni che rientrano.
    final rewrite = widget.rules.rewriteFor(uri.path, uri.query);
    if (rewrite != null) {
      widget.store.record({rewrite.id: 1});
      unawaited(controller.loadUrl(
        urlRequest: URLRequest(url: WebUri('${uri.scheme}://${uri.host}${rewrite.to}')),
      ));
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.rules.home)),
      initialUserScripts: _userScripts,
      initialSettings: InAppWebViewSettings(
        // La WebView Android si dichiara con "; wv": è l'unico segnale
        // gratuito che direbbe "non sono un browser".
        userAgent: widget.userAgent,
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        // Le storie restano intatte, autoplay compreso.
        mediaPlaybackRequiresUserGesture: false,
        thirdPartyCookiesEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        cacheEnabled: true,
        supportZoom: false,
        transparentBackground: true,
        useHybridComposition: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        _registerHandlers(controller);
      },
      shouldOverrideUrlLoading: _gate,
    );
  }
}
