# Stato dei lavori — No Dopamine Gram

Ultimo aggiornamento: **13 settembre 2026**. Documento di ripresa: leggi questo
prima di riaprire il progetto.

Documento di design completo (perimetro, architettura, rischi):
<https://claude.ai/code/artifact/936c7746-e4b5-4b37-8812-5d5ddef9fb10>

> ⚠️ Il documento di design è **superato su un punto**: vedi
> [Cambio di progetto sul livello D](#cambio-di-progetto-sul-livello-d).
> Va aggiornato.

---

## Dove siamo

L'app è una WebView che carica Instagram e filtra ciò che si vede, su quattro
livelli. **L'app gira.** Il 13 settembre è stata costruita, installata ed
eseguita per la prima volta sull'emulatore `Pixel_10_Pro` (Android 17): carica
Instagram, il pannello del canarino si apre, e i conteggi arrivano dalla pagina
vera.

Cosa ha già confermato il primo avvio, senza bisogno di login:

- lo script si inietta a document-start e il ponte verso Dart funziona;
- il **livello B ha trovato corrispondenze sulla pagina reale**:
  `css.nav.reels` e `css.nav.explore` hanno segnato un colpo ciascuno, e nella
  barra di navigazione le voci Reel ed Esplora non ci sono;
- il tasto indietro, la pressione lunga per le diagnostiche e il ritorno alla
  WebView funzionano, senza eccezioni nel logcat.

`flutter analyze` è pulito, `flutter test` passa (4 test su `RuleSet`, che
verificano anche che gli asset siano davvero nel bundle),
`flutter build apk --debug` va a buon fine con tutti i file attuali.

### Ambiente

| | |
|---|---|
| Progetto | `~/Documenti/AndroidStudio/no_dopamine_gram` |
| Flutter | 3.47.2 stable · Dart 3.13.2 (`~/Apps/sdk/flutter`) |
| Android | AGP 9.1.0 · Kotlin 2.4.0 · Gradle 9.3.1 |
| Emulatore | `android emulator start Pixel_10_Pro` → `emulator-5554` (già avviato una volta) |
| Identità git | `treixerer <fabioripa99@gmail.com>`, impostata in locale sul repo |

### Come si lancia

```sh
android emulator start Pixel_10_Pro          # → emulator-5554
flutter build apk --debug
android install --apks=build/app/outputs/flutter-apk/app-debug.apk \
                --device=emulator-5554
adb shell monkey -p it.fabioripa.no_dopamine_gram \
                 -c android.intent.category.LAUNCHER 1
android screen capture -o /tmp/shot.png
```

`android layout` non serve a niente qui: quasi tutto lo schermo è una WebView e
non compare nel dump dell'accessibilità. Per guardare l'app si usa
`android screen capture`.

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

`record()` accetta solo gli id che esistono in `rules.tracked`: il ponte
JavaScript è raggiungibile da qualunque frame della pagina, iframe di terzi
compresi, e senza quel filtro un frame estraneo potrebbe riempire le preferenze
di chiavi inventate.

### `lib/web/ig_web_view.dart` — la WebView e il livello A nativo
Gate su `shouldOverrideUrlLoading`: host non consentiti → browser di sistema via
`url_launcher`; rotte bloccate → `CANCEL`. Registra i tre handler JavaScript.
`mediaPlaybackRequiresUserGesture: false` perché le storie restano intatte.

### `lib/ui/diagnostics_page.dart` — il pannello del canarino
Stato di ogni regola raggruppato per livello, interruttore per il livello D,
azzeramento conteggi.

### `lib/ui/shell_page.dart` — il pezzo che tiene insieme tutto
Carica in un unico future le regole, lo store, il bootstrap JS e lo
User-Agent, poi disegna la WebView a tutto schermo dentro una `SafeArea`.
Niente cromatura: il banner in cima compare **solo** quando `store.alarming`
non è vuoto, e le diagnostiche si aprono con una pressione lunga nell'angolo in
alto a sinistra. `PopScope` manda il tasto indietro alla WebView e, quando non
c'è più cronologia, esce. `WidgetsBindingObserver` scrive i cookie su disco
alla pausa. Al ritorno dalle diagnostiche con `needsReload == true` la WebView
viene ricreata sostituendo la `GlobalKey`: gli user script sono
`initialUserScripts` e non si aggiornano a caldo.

Lo UA si ricava dal default del motore (`getDefaultUserAgent()`) togliendo
`; wv` **e** il token `Version/4.0`: sono i due segnali gratuiti che dicono
"non sono un browser", e un UA scritto a mano sarebbe a sua volta
un'incoerenza, perché i Client Hints riportano la versione vera di Chromium.

### `lib/main.dart` — la radice
`MaterialApp` con `ThemeMode.system` e `ShellPage` come home. Il tema si vede
solo nelle diagnostiche e nel banner: tutto il resto dello schermo è Instagram.

### `test/rules_test.dart` — le regole sotto test
Quattro test su `RuleSet`: caricamento dall'asset (che verifica di riflesso la
dichiarazione nel `pubspec.yaml`), unicità degli id, cosa il livello A blocca e
cosa non deve bloccare (`/reelsofcheese` non è la sezione Reel), e
l'allineamento del livello D alla scelta dell'utente.

### `rewrites` — l'unica cosa che il livello A riscrive
"Per te" non è una sezione da vietare, è il feed sbagliato: bloccarla
lascerebbe l'utente senza casa. `rewrite.home` manda `/` su
`/?variant=following` per tre vie, in ordine di costo:

1. **i link**: `retargetLinks()` ripunta gli `a[href="/"]` (logo e tasto casa)
   sulla variante, così a navigare è React e nessuno ricarica niente;
2. **la rete**: se la SPA finisce comunque su `/` nuda, `enforceRewrite()`
   fa `location.replace`;
3. **il cancello nativo**: `_gate` in `ig_web_view.dart`, per i caricamenti
   veri di pagina (primo avvio, link esterni che rientrano).

Il ripiego conta: se un giorno la variante sparisse, riscrivere all'infinito
lascerebbe l'utente senza casa. Se entro 2,5 secondi si torna sulla rotta
appena riscritta, la riscrittura si arrende e lo segna su `rewrite.failed`.

### Il canarino sa distinguere tre silenzi
Il primo canarino allarmava su qualunque regola a zero colpi, e il risultato
era un banner rosso fisso — che è il modo più rapido per farsi ignorare. Ora
ogni contatore dichiara che cosa significa il suo zero (`RuleKind`):

| tipo | lo zero è | allarma quando |
|---|---|---|
| `filter` | un guasto | non ha mai trovato niente, o ha smesso da 14 giorni |
| `backstop` | la norma | ha lavorato e poi ha smesso |
| `trouble` | la notizia buona | conta anche un solo colpo |

Le rotte dei Reel sono `backstop`: non possono scattare finché il CSS nasconde
la voce che ci porta, quindi il loro silenzio dice che il livello B regge.
`dom.refused` e `rewrite.failed` sono `trouble`. Le regole del livello D sono
*dormienti* finché il livello D è spento, e con loro `css.neutralized`, che
nasconde solo ciò che il livello D segnala.

Con questo, sull'account di prova, il banner **non compare**: è la prima volta
che l'app è invisibile come dice di voler essere.

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

1. **Primo accesso vero e verifica delle cinque domande aperte** (sotto).
   Serve il login dell'utente: non è una cosa che si può automatizzare. È il
   passo che sblocca tutti gli altri.

2. **Tarare le regole che restano.** Confermate sul campo il 13 settembre:
   `css.nav.reels`, `css.explore.grid`, `css.profile.suggested`,
   `dom.feed.suggested`. `dom.feed.reelchip` è ancora a zero, ma **non è
   rotta**: nel feed non è ancora passato un solo Reel, e i suoi selettori
   `article:has(...)` sono validi (vedi sotto). Va riguardata quando un Reel
   comparirà davvero.

3. **Guardare `dom.feed.reelchip` quando passerà un Reel.** È l'unica regola
   di cui non si sa ancora niente: nel feed non ne è passato uno.

4. **Aggiornare il documento di design** con il cambio sul livello D.

Chiuso il 13 settembre: asset dichiarati nel `pubspec.yaml`, `shell_page.dart`
scritto, `main.dart` riscritto, smoke test del contatore sostituito con i test
sulle regole, build e installazione sull'emulatore riuscite.

---

## Verifiche aperte (servono un account loggato)

1. ~~**`?variant=following` esiste ancora sul web?**~~ **Sì, verificato il 13
   settembre da loggati.** In cima al feed c'è un menu a tendina "Per te ⌄"
   con due voci, *Following* e *Favorites*: scegliendo Following l'URL diventa
   esattamente `https://www.instagram.com/?variant=following`, che è già il
   valore di `home`. **Il livello D resta dormiente.**

   Due code da tenere a mente: il passaggio fra le varianti cambia solo la
   query e non il path (per questo `onRouteChange` ora guarda anche
   `location.search`), e navigando su "casa" dentro la SPA si torna a `/`
   senza variante — il feed algoritmico rientra dalla finestra. Va deciso se
   riscrivere la rotta.
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

**`closest()` senza tetto spegne lo schermo.** È il guasto che ha reso l'app
inutilizzabile al primo accesso vero, ed è istruttivo. La regola
`dom.feed.suggested` cercava il contenitore di un blocco "Suggested for you"
con `closest('article, section, div[role="presentation"]')`. Nel momento in cui è
successo, in quella pagina, **di `<article>` e `div[role="presentation"]` ce
n'erano zero**: l'unica voce che corrispondeva ancora era `section`, e il
`<section>` più vicino è quello che avvolge **tutta l'app**.

Attenzione a non trarne la lezione sbagliata, come ho fatto io sul momento:
`<article>` **esiste**, ed è davvero il contenitore di un post. Mancava perché
quel feed non aveva nemmeno un post dentro — era tutto account suggeriti.
Il che rende la trappola peggiore, non migliore: il selettore era corretto e
ha funzionato per mesi, e a farlo sparare in alto è bastata una pagina in uno
stato insolito.
Risultato: un elemento marcato, 193 KB di pagina nascosti, schermo nero con la
sola barra di navigazione.

La lezione non è "correggi quel selettore" — è che `closest()` risale finché
non trova qualcosa, quindi *una regola scritta male può sempre arrivare alla
radice*. Ora in mezzo c'è un cancello (`safeToHide` + `hostFor` in
`bootstrap.js`): non si marca mai `html`, `body`, `main`, né un elemento che
contiene `main`, né uno che pesa più del 40% della pagina; e la risalita è
limitata a `climb.maxLevels` livelli dentro `climb.maxHtml` caratteri. Il caso
peggiore diventa "la regola non fa niente", che il canarino sa già raccontare —
e i rifiuti si contano sotto `dom.refused`.

**Il PATH di Flutter.** `~/.bashrc` è a posto, ma i processi aperti prima della
sua modifica ereditano un PATH senza Flutter. Per questo `flutter` e `dart` sono
anche symlink in `~/.local/bin`.
