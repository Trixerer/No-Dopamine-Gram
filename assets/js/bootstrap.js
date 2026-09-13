/* No Dopamine Gram - livelli B, C, D dentro la pagina.
 * Iniettato a document-start, prima del JavaScript di Instagram.
 * Regola invariante: non rimuoviamo mai nodi dal DOM e non mutiamo mai le
 * risposte di rete. Marchiamo e basta: il DOM lo possiede React, la risposta
 * la possiede Instagram. Rompere uno dei due significa schermata bianca. */
(function () {
  'use strict';
  if (window.__ND_ACTIVE__) return;
  window.__ND_ACTIVE__ = true;

  var R = window.__ND_RULES__ || {};
  var MARK = 'data-nd-neutralized';

  /* ---------- canarino: conteggi verso Dart, in batch ---------- */
  var counts = Object.create(null);
  var flushQueued = false;

  function hit(id) {
    counts[id] = (counts[id] || 0) + 1;
    if (flushQueued) return;
    flushQueued = true;
    setTimeout(flush, 1500);
  }

  function flush() {
    flushQueued = false;
    var payload = counts;
    counts = Object.create(null);
    if (!Object.keys(payload).length) return;
    try {
      window.flutter_inappwebview.callHandler('nd_canary', payload);
    } catch (e) {
      /* il bridge non c'è ancora: rimetti in coda, non perdere il conteggio */
      for (var k in payload) counts[k] = (counts[k] || 0) + payload[k];
    }
  }

  function report(channel, data) {
    try { window.flutter_inappwebview.callHandler(channel, data); } catch (e) {}
  }

  /* ---------- livello B: CSS ---------- */
  function installCss() {
    if (document.getElementById('nd-style')) return;
    var out = [];
    (R.css || []).forEach(function (rule) {
      var sel = (rule.selectors || []).join(',\n');
      if (sel) out.push(sel + ' {\n  display: none !important;\n}');
    });
    if (!out.length) return;
    var st = document.createElement('style');
    st.id = 'nd-style';
    st.textContent = out.join('\n');
    (document.head || document.documentElement).appendChild(st);
  }

  /* Il canarino del CSS non può girare a ogni mutazione: costerebbe troppo.
   * Gira quando la pagina si è assestata e a ogni cambio di rotta. */
  function auditCss() {
    (R.css || []).forEach(function (rule) {
      if (rule.id === 'css.neutralized') return; /* dipende dal livello C */
      var found = (rule.selectors || []).some(function (s) {
        try { return document.querySelector(s) !== null; } catch (e) { return false; }
      });
      if (found) hit(rule.id);
    });
  }

  /* ---------- livello C: DOM ---------- */

  /* Il pericolo del livello C non e' nascondere troppo poco, e' nascondere
   * troppo. `closest()` risale finche' non trova una corrispondenza: se il
   * selettore non descrive piu' niente di vicino - e Instagram ha smesso di
   * usare <article> e role="presentation" - arriva fino al <section> che
   * avvolge tutta l'app, e una regola sbagliata spegne lo schermo.
   *
   * Questo cancello sta in mezzo e trasforma quel caso in "la regola non fa
   * niente", che e' un guasto che il canarino sa gia' raccontare. */
  function tooBigToHide(el) {
    var root = document.querySelector('main') || document.body;
    if (!root || !el.innerHTML) return false;
    return el.innerHTML.length > (root.innerHTML.length || 1) * 0.4;
  }

  function safeToHide(el) {
    if (!el || el.nodeType !== 1) return false;
    var tag = el.tagName;
    if (tag === 'HTML' || tag === 'BODY' || tag === 'MAIN') return false;
    var main = document.querySelector('main');
    if (main && (el === main || el.contains(main))) return false;
    return !tooBigToHide(el);
  }

  /* Il contenitore da marcare. Si sale di un numero fisso di livelli e si
   * resta dentro un budget di contenuto: una risalita illimitata e' proprio
   * quella che finiva sulla radice della pagina. */
  function hostFor(start, rule) {
    if (!start) return null;
    var climb = rule.climb || {};
    var maxLevels = climb.maxLevels || 8;
    var maxHtml = climb.maxHtml || 20000;

    /* Se la regola nomina un contenitore e quel contenitore e' stretto, vince
     * lui: un punto di riferimento vero e' piu' preciso di qualunque misura. */
    if (rule.closest) {
      var near = null;
      try { near = start.closest(rule.closest); } catch (e) {}
      if (near && safeToHide(near) && near.innerHTML.length <= maxHtml) return near;
    }

    var host = null;
    var el = start;
    for (var i = 0; el && i < maxLevels; i++, el = el.parentElement) {
      if (!safeToHide(el) || el.innerHTML.length > maxHtml) break;
      host = el;
    }
    return host;
  }

  function neutralize(el, ruleId) {
    if (!el) return;
    if (el.getAttribute(MARK) === '1') return;
    /* Il rifiuto va contato: una regola che punta sempre troppo in alto e'
     * rotta, e deve vedersi nelle diagnostiche invece di sparire in silenzio. */
    if (!safeToHide(el)) { hit('dom.refused'); return; }
    el.setAttribute(MARK, '1');
    hit(ruleId);
  }

  function scanAttrRules(root) {
    (R.dom || []).forEach(function (rule) {
      (rule.attrSelectors || []).forEach(function (sel) {
        var nodes;
        try { nodes = root.querySelectorAll(sel); } catch (e) { return; }
        for (var i = 0; i < nodes.length; i++) {
          neutralize(hostFor(nodes[i], rule), rule.id);
        }
      });
    });
  }

  function scanPhraseRules(root) {
    var rules = (R.dom || []).filter(function (r) { return (r.phrases || []).length; });
    if (!rules.length || !root.querySelectorAll) return;
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    var node;
    while ((node = walker.nextNode())) {
      var text = node.nodeValue;
      if (!text || text.length > 60) continue;
      for (var i = 0; i < rules.length; i++) {
        var rule = rules[i];
        for (var j = 0; j < rule.phrases.length; j++) {
          if (text.indexOf(rule.phrases[j]) !== -1) {
            neutralize(hostFor(node.parentElement, rule), rule.id);
            break;
          }
        }
      }
    }
  }

  /* ---------- livello D: lettura delle risposte, mai scrittura ---------- */
  var blockedCodes = new Set();

  function interesting(url) {
    var pats = (R.response && R.response.urlPatterns) || [];
    for (var i = 0; i < pats.length; i++) if (url.indexOf(pats[i]) !== -1) return true;
    return false;
  }

  function nodeMatches(node, m) {
    if (!m) return false;
    if (m.hasKey) {
      return Object.prototype.hasOwnProperty.call(node, m.hasKey) && node[m.hasKey] != null;
    }
    if (m.keyEquals) {
      for (var k in m.keyEquals) if (node[k] !== m.keyEquals[k]) return false;
      return true;
    }
    return false;
  }

  function codeOf(node) {
    return node.code || (node.media && node.media.code) || null;
  }

  function harvest(root) {
    var rules = (R.response && R.response.rules) || [];
    if (!rules.length) return;
    var seen = new Set();
    var stack = [root];
    var depth = 0;
    while (stack.length && depth++ < 200000) {
      var cur = stack.pop();
      if (!cur || typeof cur !== 'object') continue;
      if (seen.has(cur)) continue;
      seen.add(cur);
      if (Array.isArray(cur)) {
        for (var i = 0; i < cur.length; i++) stack.push(cur[i]);
        continue;
      }
      for (var r = 0; r < rules.length; r++) {
        if (nodeMatches(cur, rules[r].match)) {
          var code = codeOf(cur);
          if (code && !blockedCodes.has(code)) {
            blockedCodes.add(code);
            hit(rules[r].id);
            scheduleScan();
          }
        }
      }
      for (var key in cur) stack.push(cur[key]);
    }
  }

  function readBody(text) {
    if (!text || text.charAt(0) !== '{') return;
    try { harvest(JSON.parse(text)); } catch (e) { /* streaming o non-JSON: ignora */ }
  }

  function scanBlocklist(root) {
    if (!blockedCodes.size || !root.querySelectorAll) return;
    var links = root.querySelectorAll('a[href^="/p/"], a[href^="/reel/"]');
    for (var i = 0; i < links.length; i++) {
      var parts = links[i].getAttribute('href').split('/');
      if (blockedCodes.has(parts[2])) {
        neutralize(links[i].closest('article') || links[i], 'resp.blocklist');
      }
    }
  }

  function installNetworkReaders() {
    if (!(R.response && R.response.enabled)) return;

    var origFetch = window.fetch;
    if (typeof origFetch === 'function') {
      window.fetch = function (input, init) {
        var promise = origFetch.apply(this, arguments);
        var url = typeof input === 'string' ? input : (input && input.url) || '';
        if (!interesting(url)) return promise;
        return promise.then(function (res) {
          /* clone(): leggiamo una copia nostra, l'originale arriva a Instagram
           * intatto e senza che il suo stream venga consumato da noi. */
          try { res.clone().text().then(readBody, function () {}); } catch (e) {}
          return res;
        });
      };
    }

    var open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      this.__nd_url = url;
      return open.apply(this, arguments);
    };
    var send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function () {
      var xhr = this;
      if (xhr.__nd_url && interesting(String(xhr.__nd_url))) {
        xhr.addEventListener('load', function () {
          try {
            if (!xhr.responseType || xhr.responseType === 'text') readBody(xhr.responseText);
          } catch (e) {}
        });
      }
      return send.apply(this, arguments);
    };
  }

  /* ---------- livello A dentro la SPA ---------- */
  /* shouldOverrideUrlLoading non vede i cambi di rotta di React: li vediamo qui. */
  function routeBlocked(path) {
    var routes = R.routes || [];
    for (var i = 0; i < routes.length; i++) {
      try {
        if (new RegExp(routes[i].pattern).test(path)) return routes[i];
      } catch (e) {}
    }
    return null;
  }

  function enforceRoute() {
    var rule = routeBlocked(location.pathname);
    if (!rule) return false;
    hit(rule.id);
    report('nd_route_blocked', { id: rule.id, label: rule.label, path: location.pathname });
    if (history.length > 1) history.back();
    else location.replace(R.home || '/');
    return true;
  }

  function watchRoutes() {
    ['pushState', 'replaceState'].forEach(function (name) {
      var orig = history[name];
      history[name] = function () {
        var out = orig.apply(this, arguments);
        onRouteChange();
        return out;
      };
    });
    window.addEventListener('popstate', onRouteChange);
  }

  var lastPath = null;
  function onRouteChange() {
    /* La query fa parte della rotta: passare da "Per te" a "Following" cambia
     * solo `?variant=`, e senza guardarla il cambio di feed non si vede. */
    var here = location.pathname + location.search;
    if (here === lastPath) return;
    lastPath = here;
    if (enforceRoute()) return;
    report('nd_route', { path: location.pathname, search: location.search });
    scheduleScan();
    setTimeout(auditCss, 1200);
  }

  /* ---------- osservatore ---------- */
  var scanQueued = false;
  function scheduleScan() {
    if (scanQueued) return;
    scanQueued = true;
    /* microtask: gira prima del prossimo paint, quindi l'elemento marcato
     * non arriva mai a schermo. */
    Promise.resolve().then(function () {
      scanQueued = false;
      scanAll(document.body || document.documentElement);
    });
  }

  function scanAll(root) {
    if (!root) return;
    scanAttrRules(root);
    scanPhraseRules(root);
    scanBlocklist(root);
  }

  function startObserver() {
    var target = document.body || document.documentElement;
    new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var added = records[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          if (added[j].nodeType === 1) scanAll(added[j]);
        }
      }
    }).observe(target, { childList: true, subtree: true });
    scanAll(target);
  }

  /* ---------- avvio ---------- */
  installNetworkReaders();
  watchRoutes();

  function onReady() {
    installCss();
    startObserver();
    lastPath = location.pathname;
    enforceRoute();
    setTimeout(auditCss, 2500);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', onReady, { once: true });
  } else {
    onReady();
  }
})();
