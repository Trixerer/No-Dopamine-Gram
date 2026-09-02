# Stato dei lavori — No Dopamine Gram

Ultimo aggiornamento: **2 settembre 2026**. Documento di ripresa: leggi questo
prima di riaprire il progetto.

Documento di design completo (perimetro, architettura, rischi):
<https://claude.ai/code/artifact/936c7746-e4b5-4b37-8812-5d5ddef9fb10>

> ⚠️ Il documento di design è **superato su un punto**: vedi
> [Cambio di progetto sul livello D](#cambio-di-progetto-sul-livello-d).
> Va aggiornato.

---

## Dove siamo

L'app è una WebView che carica Instagram e filtra ciò che si vede, su quattro
livelli. Lo scheletro dei filtri è scritto e compila; **l'app non è ancora mai
stata eseguita**, perché manca la UI che la tiene insieme (`main.dart` è ancora
il contatore di default di Flutter).

`flutter analyze` è pulito. `flutter build apk --debug` è andato a buon fine
l'ultima volta che è stato lanciato (prima però che esistessero `lib/ui/` e i
file nuovi: **da rilanciare**).

### Ambiente

| | |
|---|---|
| Progetto | `~/Documenti/AndroidStudio/no_dopamine_gram` |
| Flutter | 3.47.2 stable · Dart 3.13.2 (`~/Apps/sdk/flutter`) |
| Android | AGP 9.1.0 · Kotlin 2.4.0 · Gradle 9.3.1 |
| Emulatore | `android emulator start Pixel_10_Pro` → `emulator-5554` (già avviato una volta) |
| Identità git | `treixerer <fabioripa99@gmail.com>`, impostata in locale sul repo |

---

## Fatto

### `assets/rules/rules.json` — le regole come dati
Tutte le regole dei quattro livelli in un file versionabile, aggiornabile senza
ricompilare. Contiene rotte bloccate (A), selettori CSS (B), regole DOM (C) e
regole di riconoscimento sulle risposte (D, spente per impostazione predefinita).
`home` punta a `https://www.instagram.com/?variant=following`.

### `assets/js/bootstrap.js` — livelli B, C, D dentro la pagina
310 righe, iniettate a document-start prima del JavaScript di Instagram.
Sintassi verificata con `node --check`. Contiene:

- **canarino** con conteggi in batch verso Dart (`nd_canary`), che rimette in
  coda i conteggi se il bridge non è ancora pronto;
- **livello B**: CSS iniettato una regola per voce di configurazione, più un
  audit periodico che dice se una regola ha smesso di trovare corrispondenze;
- **livello C**: `MutationObserver` che marca (`data-nd-neutralized`) senza mai
  rimuovere nodi — il DOM lo possiede React, rimuovere significa schermata
  bianca. Regole per attributo e per frase di testo;
- **livello D**: lettura delle risposte tramite `res.clone()`, mai scrittura;
- **livello A dentro la SPA**: `pushState`/`replaceState`/`popstate` intercettati,
  perché i cambi di rotta di React non passano da `shouldOverrideUrlLoading`.

### `lib/core/rules.dart` — modello e caricamento delle regole
`RuleSet.load()` legge l'asset. Espone `blockedRouteFor(path)` per il livello A
e `asInjectedJson()`, che allinea `response.enabled` alla scelta dell'utente
invece che al valore scritto nel file.

### `lib/core/store.dart` — canarino e preferenze su disco
`NdStore` (SharedPreferences) accumula conteggi e data dell'ultimo colpo per
ogni regola. Due allarmi distinti: `neverSeen` (non ha mai trovato niente) e
`wentQuiet` (funzionava e ha smesso da più di 14 giorni — è il caso che conta).
Non allarma sotto le tre sessioni.

### `lib/web/ig_web_view.dart` — la WebView e il livello A nativo
Gate su `shouldOverrideUrlLoading`: host non consentiti → browser di sistema via
`url_launcher`; rotte bloccate → `CANCEL`. Registra i tre handler JavaScript.
`mediaPlaybackRequiresUserGesture: false` perché le storie restano intatte.

### `lib/ui/diagnostics_page.dart` — il pannello del canarino
Stato di ogni regola raggruppato per livello, interruttore per il livello D,
azzeramento conteggi.

### Configurazione Android
`AndroidManifest.xml`: permesso `INTERNET`, etichetta "No Dopamine Gram",
`<queries>` per l'intent VIEW https (link dei direct che escono nel browser).

---

## Cambio di progetto sul livello D

**Scoperto scrivendo il codice, non ancora riportato nel documento di design.**

Il documento dice «sostituisci, non cancellare»: mutare la risposta lasciando
intatta la sua forma. Implementandolo è emerso che **non serve mutare affatto**.

Il livello D ora **legge e basta**: aggancia `fetch`/`XHR`, legge una `clone()`
della risposta e si limita a *riconoscere* i contenuti indesiderati, mettendone
lo shortcode in una blocklist. È poi il livello C che, alla comparsa del nodo,
lo marca prima che venga disegnato — i callback di `MutationObserver` sono
microtask, girano prima del paint successivo, quindi l'elemento non arriva mai
a schermo.

Cosa ci guadagna:

- spariscono tutti i rischi documentati sulla mutazione (cursori di
  paginazione, `has_more`, chiavi React, avvelenamento della cache client);
- sparisce il problema dello streaming: `clone()` ci dà uno stream nostro da
  svuotare con calma, senza consumare quello di Instagram;
- la risposta che arriva a Instagram è byte per byte la sua.

**Il limite da tenere presente:** la lettura della clone è asincrona, quindi un
riconoscimento tardivo può arrivare dopo il render. L'osservatore ri-scansiona
quando la blocklist cresce, ma in quel caso il post può lampeggiare un istante.
Con il feed cronologico questo percorso è raramente in uso.

---

## Da fare, in ordine

1. **Dichiarare gli asset nel `pubspec.yaml`.** La sezione `assets:` è ancora
   commentata: senza, `rootBundle.loadString` fallisce e l'app non parte.
   Servono `assets/rules/rules.json` e `assets/js/bootstrap.js`.

2. **Scrivere `lib/ui/shell_page.dart`.** È il pezzo mancante che tiene insieme
   tutto. Deve:
   - caricare in un unico future `RuleSet.load()`, `NdStore.open()`, il
     bootstrap JS da `rootBundle`, e lo User-Agent;
   - **ricavare lo UA dal default della WebView** (`InAppWebViewController
     .getDefaultUserAgent()`) togliendo `; wv`, invece di scriverne uno a mano:
     un UA che non combacia con il motore vero è a sua volta un'incoerenza,
     perché i Client Hints riportano la versione reale di Chromium;
   - niente cromatura: WebView a tutto schermo, `SafeArea`;
   - `PopScope` che manda il tasto indietro alla WebView (`goBackIfPossible`);
   - `WidgetsBindingObserver` che chiama `flushCookies()` alla pausa, così la
     sessione sopravvive e non si rifà il login (il login dentro una WebView è
     il momento in cui Meta fa scattare le challenge);
   - banner in cima **solo** quando `store.alarming` non è vuoto — l'app è
     invisibile finché qualcosa non si rompe, che è il senso del canarino;
   - accesso alle diagnostiche con pressione lunga in un angolo;
   - al ritorno dalle diagnostiche con `needsReload == true`, ricreare la
     WebView cambiando una `ValueKey`: gli user script sono `initialUserScripts`
     e non si aggiornano a caldo.

3. **Riscrivere `lib/main.dart`.** Ora è ancora il contatore di default.
   `MaterialApp` con `ThemeMode.system` e `ShellPage` come home.

4. **Compilare e installare sull'emulatore.**
   `flutter build apk --debug` poi `android install` / `android run`,
   `android screen` per lo screenshot.

5. **Primo accesso vero e verifica delle cinque domande aperte** (sotto).
   Serve il login dell'utente: non è una cosa che si può automatizzare.

6. **Aggiornare il documento di design** con il cambio sul livello D.

7. **Tarare le regole su ciò che si vede davvero.** I selettori CSS e le frasi
   del livello C sono ipotesi ragionevoli scritte senza aver visto l'HTML
   loggato: vanno confermati uno per uno guardando la pagina vera.

---

## Verifiche aperte (servono un account loggato)

1. **`?variant=following` esiste ancora sul web?** È la domanda che vale tutte
   le altre: se il feed cronologico c'è, il livello D resta dormiente.
2. **Quanto sono complete storie e direct sul web mobile** rispetto all'app
   nativa? È il rischio più concreto per la lista di funzioni.
3. **Il service worker `/www-service-worker.js?s=push` ha un handler `fetch`?**
   Se sì gira in un contesto separato e il nostro hook non lo vede: buco nel
   filtro.
4. **Quali risposte arrivano in streaming?** Con la lettura via `clone()` il
   problema è molto ridotto, ma i corpi a chunk vanno comunque riconosciuti.
5. **Il login dentro la WebView passa liscio** o fa scattare una challenge?

---

## Trappole già incontrate

**AGP 9 e `flutter_inappwebview`.** La versione stabile 6.1.5 (ottobre 2024)
**non compila** con AGP 9: il suo `build.gradle` usa
`getDefaultProguardFile('proguard-android.txt')`, che AGP 9 rifiuta perché
include `-dontoptimize`. La beta **6.2.0-beta.3** usa la variante
`-optimize` e compila. Da qui il vincolo in `pubspec.yaml`:
`flutter_inappwebview: ^6.2.0-beta.3`. Se un giorno il pacchetto morisse, il
piano B è un `PlatformView` con canale nativo — il plugin ufficiale
`webview_flutter` **non** è un'alternativa: non espone né l'iniezione a
document-start né l'intercettazione delle richieste.

**Il PATH di Flutter.** `~/.bashrc` è a posto, ma i processi aperti prima della
sua modifica ereditano un PATH senza Flutter. Per questo `flutter` e `dart` sono
anche symlink in `~/.local/bin`.
