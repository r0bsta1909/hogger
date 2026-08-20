---
name: love2d-lan-game
user-invocable: true
description: Erprobte Architektur-, Netcode- und Auslieferungsmuster für LÖVE2D-Spiele mit LAN-Multiplayer in jeder Konstellation — 1v1-Sportspiel, Arena-Shooter, Koop-Zerg bis 40 Spieler, persistente Welt/MMORPG-artig — plus Zero-Config-Discovery, Turniermodus, Asset-Pipeline von Platzhalter bis Final, Release-Bau von .love/.exe/.app und CI-Zuschnitt auf gehosteten Runnern. Laden bei jedem Projekt mit LÖVE/love2d + Netzwerk (ENet, luasocket, Snapshots, Lockstep-Frage, Skalierungsfragen), LAN-Party-Betrieb, Turniersystem, Headless-Balancing-Sim, Asset- oder Packaging-Fragen sowie bei GitHub-Actions-Matrix und Minutenverbrauch — vor der ersten Architekturentscheidung, vor der ersten Zeile Netzcode und vor dem Aufsetzen der CI.
---

# LÖVE2D-Spiel für LAN und Turnier — destillierte Learnings

Quellen: **zwei** vollständig durchgezogene Projekte.

- **P1 — Arcade-Sportspiel** (Win + macOS, 2–8 Spieler/Match, 20-Teilnehmer-Turnier, zwei echte
  LAN-Abende). Ursprung von §1–§10.
- **P2 — Koop-Zerg gegen einen Boss** (Win + macOS, 5–40 Spieler, ~50 Entitäten, 60-Hz-Vollzustand,
  Balancing per Headless-Sim, Asset-Pipeline von Platzhalter bis Final, Release-Pipeline für
  `.love`/`.exe`/`.app`). Ursprung von §11–§13 und der Messwerte in §3.1.

Alles hier ist gebaut, gemessen oder teuer schiefgegangen — nichts ist Theorie.
Punkte mit **[gemessen]** sind Fallen, die erst im echten Betrieb auffielen.

**Geltungsbereich:** Die gemessene Hülle ist inzwischen: kleiner Weltzustand (bis ~700 B pro
Snapshot), **bis 40 gleichzeitige Spieler**, LAN-RTT < 5 ms. §1, §2, §4, §5, §7–§13 gelten
**genre-unabhängig** für jedes LÖVE2D-LAN-Projekt — die Fallen dort hängen an Plattform, Lua 5.1,
ENet/LuaSocket und der Werkzeugkette, nicht am Spieltyp. §6 gilt, sobald ein Turnier gebraucht
wird (und sein Event-Log-Muster generalisiert auf jede persistente Welt). Nur die
Snapshot-Strategie in §3 ist skalenabhängig; §3.1 gibt die Eskalationsleiter und seit P2 einen
gemessenen Anker bei 40 Spielern. Abschnitte mit **[abgeleitet]** sind aus den gemessenen
Prinzipien gefolgert, aber nicht selbst im Betrieb verifiziert — dort gilt §10 doppelt: erst
messen, dann eskalieren.

## 1. Reihenfolge: Fundament vor Netcode

Netcode auf eine unvorbereitete Codebasis zu setzen heißt, ihn zweimal zu schreiben.
**Vier Eigenschaften müssen stehen, bevor die erste Zeile Netzcode entsteht** — in dieser
Abhängigkeitsreihenfolge:

1. **Logische Weltgröße ist eine Konstante** (z. B. 800×600). Fensteranpassung ausschließlich als
   Render-Transformation mit Letterbox/Pillarbox. Sonst spielen zwei Clients mit verschiedenen
   Fenstern verschiedene Spiele, und Snapshot-Koordinaten sind bedeutungslos.
2. **Fixer Simulationsschritt** (1/60 s) mit Akkumulator; Rendering entkoppelt und interpoliert
   (`alpha = accumulator / TICK_DT`). Akkumulator deckeln (`min(acc, 0.25)`) gegen Spiral of Death.
   `TICK_DT` ist eine Konstante im Sim-Code, kein Parameter — der `dt` aus `love.update` erreicht
   die Physik nie. Sprungstellen (Ball-Reset) müssen den Interpolationspuffer des Renderers zurücksetzen.
3. **Input-Abstraktion:** Die Simulation konsumiert genau ein `InputFrame` pro Spieler pro Tick,
   erzeugt von genau einer Quelle: Tastatur/Gamepad, Bot, Netzwerk, Replay. Kein `love.keyboard.isDown`
   in der Simulation. Format: **1 Byte Bitmaske** (`left=1, right=2, jump=4, …`), reservierte Bits
   müssen 0 sein und werden vom Empfänger **verworfen statt maskiert** — so fällt ein
   Protokollversionsfehler sofort auf. Richtungstasten sind Zustände (Flankenerkennung in der Sim);
   abgeleitete Gesten (Doppeltipp-Dash) erkennt die Eingabequelle und liefert einen Impuls-Bit —
   sonst muss die Sim Tipp-Historien führen, der Bot Tasten simulieren und das Netz Tastenfolgen tragen.
4. **Ruleset/Prefs-Trennung:** `Ruleset` = simulationsrelevant, vom Host verteilt, kanonisch gehasht,
   im Match unveränderlich. `Prefs` = rein lokal (Lautstärke, Tasten, Anzeige). Ohne die Trennung
   kann jeder Client still seine Physik ändern. Validierung lehnt ungültige Werte **ab statt zu
   klemmen** — ein still geklemmter Wert erzeugt verschiedene Rulesets bei gleichem Hash.

**Absicherung des Refactorings:** Vor dem Umbau Referenz-Replays aufzeichnen (Inputs + erwartete
Positionen je Tick), nach jedem Schritt bitgleich reproduzieren. Ein Umbau, der keine Stelle bewegt,
ist nachweislich Umsortierung statt Änderung. Toleranz erst dort, wo sich die Arithmetik wirklich
ändert; jede akzeptierte Abweichung einzeln protokollieren — alles, was nicht in der Liste steht,
ist ein Fehler. **[gemessen]** 0,01 % Schwerkraftänderung lässt die Hälfte der Referenzen durchfallen;
variabler vs. fixer Timestep divergiert nach 40–190 Ticks um > 0,5 px, in langen Rallyes um Hunderte px
— deshalb: Referenzsatz für den festen Schritt durch **Wiedergabe derselben Inputs** erzeugen,
nicht durch erneutes Spielen.

## 2. Die Simulation ist rein (`src/sim/` ist love-frei)

`step(state, inputs, ruleset) → events` ist die einzige Stelle, an der sich Spielzustand ändert.
Verboten darunter: `love.*`, `os.time/clock`, ungeseedetes `math.random`, Iteration über
nicht-numerische Schlüssel, wenn die Reihenfolge das Ergebnis beeinflusst.

- **Warum, auch ohne Lockstep:** Replays, headless Physik-Regression (CI ohne Fenster!),
  Client-Vorhersage mit derselben Physik, Prüfsummen. Vier Nutzer für eine billige Regel.
- Mutation in place statt neuem State ist ok (60 Kopien/s sind Allokationsdruck auf alter Hardware);
  Determinismus hängt nur daran, *was* gelesen wird.
- Kosmetik als **Ereignisliste** zurückgeben (`{type="wall_hit", x=…}`), die die Renderschicht in
  Partikel/Sound übersetzt. Die Sim bleibt stumm, und der Client kann Effekte auch aus Snapshots ableiten.
- Braucht ein Modul außerhalb der Sim einen Hash (z. B. Ruleset-Hash), den Hash **in der Sim selbst
  rechnen** (djb2, ~10 Zeilen) statt `love.data.hash` — sonst ist die Sim nicht mehr headless testbar.
  Ein Hash im LAN erkennt Abweichung, er sichert nichts ab; djb2 reicht. **Nie zwei Hashes über
  dieselbe Sache** — beim ersten Auseinanderlaufen ist nicht entscheidbar, welcher recht hat.
- **Anti-Zufall:** kein `math.random` in der Sim, keine zufälligen Timingfenster. Turnierbetrieb
  verträgt keine unbegründete Varianz, und jede Zufallsquelle ist eine Determinismus-Falle.
- Zuerst prüfen: braucht die Sim überhaupt Zufall? „Kein Zufall" ist schärfer und billiger als ein
  deterministischer PRNG, der nie gebraucht wird.

## 3. Netcode-Architektur: Host-autoritative Snapshots

**Kein Lockstep cross-platform mit LuaJIT.** Lockstep verlangt bitweisen Float-Determinismus.
Der ist Win-x86-64 vs. macOS-ARM64 nicht erreichbar: verschiedene Befehlssätze, und LÖVE 11.5 hat
den JIT auf Apple Silicon **abgeschaltet** — Interpreter gegen JIT sind zwei Ausführungspfade
derselben Arithmetik. **[gemessen]** Sogar das Vorzeichen der Null entsteht unterschiedlich.
Der Ausweg (Festkomma) heißt: gesamte Physik neu schreiben, in Lua 5.1 ohne Integer-Typ.
**Kein Rollback/GGPO bei LAN:** bringt die Determinismus-Anforderung durch die Hintertür zurück,
Aufwand um ein Vielfaches höher, Nutzen bei RTT < 5 ms nicht wahrnehmbar.

**Stattdessen:** Ein Spieler-Rechner ist Host und simuliert autoritativ; Clients senden nur Inputs,
der Host sendet Zustands-Snapshots. Bei kleinem Weltzustand (zweistellige Bytezahl) **volle Tickrate
senden (60 Hz)** — das ist billiger als jede Optimierung: keine Delta-Kompression, keine
Interpolation über Lücken nötig. Desync ist per Konstruktion unmöglich; es gibt nur eine Wahrheit.

**Client-Darstellung — das Endergebnis zweier LAN-Abende:** Der Gast simuliert die **ganze Welt**
lokal mit der echten Physik vor (eigene Eingabe live, Gegner neutral) und setzt sie je Snapshot neu
auf: Snapshot anwenden, eigene Eingaben seit dessen `ackInputTick` aus einer Maskenhistorie wieder
vorspielen (**Rebase + Replay**, gedeckelt). Angezeigt wird nur dieser Zustand — **eine Zeitbasis**.
Der Host bleibt die einzige Autorität; geändert ist nur, was der Gast zeichnet.

Warum nicht die naheliegenden Zwischenstufen — beide gebaut und verworfen **[gemessen]**:
- *Interpolationspuffer (Ball aus der Vergangenheit) + Vorhersage nur des eigenen Blobs (Blob im
  Jetzt)* = **zwei Zeitbasen in einem Bild.** Sichtbarer Effekt: Ball wird „im" Blob getroffen statt
  außen, besonders im Sprung. Der Versatz hängt am Puffer, nicht an der RTT — er bleibt auch bei RTT 0.
- Ein Entnahme-Puffer, der je Tick genau einen Snapshot zieht, **ratscht bei Ankunftsschüben hoch**
  und hält sein Soll nie (Soll 2, real 4–5 → 80–90 ms Versatz). Puffer-Tuning ist eine Problemklasse,
  die mit dem Vollzustands-Ansatz komplett verschwindet.
- Lineare Ball-Extrapolation zappelt an jeder Wand-/Netzberührung; mit der echten Physik
  fortschreiben erledigt genau diesen Einwand.

Werkzeuge des Abgleichs (gelten auch für Teilvorhersagen):
- Snapshot trägt `ackInputTick` (welchen Input-Tick des Empfängers der Host verarbeitet hat).
  Verglichen wird die **gespeicherte** Vorhersage zu diesem Tick, nie die Gegenwart — sonst wird
  Laufzeit als Fehler gemessen und permanent „korrigiert".
- Steht `ackInputTick` still (Eingabeverlust), **nicht vergleichen** — der Host hat mit einer
  Eingabe gerechnet, die der Gast nie geschickt hat.
- Korrektur als **Sichtversatz**: Abweichung sofort in die Simulationsposition übernehmen, gezeichnet
  wird sie plus einem Versatz, der über wenige Ticks linear auf null läuft. Nie die Position langsam
  nachziehen — dann rechnen die nächsten Ticks mit einer bekannt falschen Zahl.
- **Harte Übernahmen zählen nicht als Fehler:** Ansagen des Hosts (Punkt, Reset) werden sofort
  übernommen und erhöhen keinen Fehlerzähler, sonst stehen nach zehn Punkten zehn Phantom-„Fehler" im Overlay.
- Vorhersage ruft **dieselben Sim-Funktionen** auf, nie eine Kopie der Bewegungslogik — eine zweite
  Wahrheit driftet beim ersten Balancing-Eingriff still gegen den Host und sieht aus wie ein Netzproblem.
  Lieber zwei lokale Funktionen im Sim-Modul exportieren als sechs Zeilen kopieren.

**Eingaben:** Jedes INPUT-Paket trägt die Masken der letzten ~3 Ticks (Redundanz, 2 Byte) —
Einzelpaketverluste werden unsichtbar. Fehlt Input zum Tick: **letzte Maske wiederholen**
(Repeat-Last), nicht Null-Input — sonst ruckelt die Figur bei jedem Verlust zum Stillstand.
Jitter-Puffer klein halten (~2 Ticks): Latenz ist teurer als seltene Vertauschung. Input-Delay 0 im LAN.

### 3.1 Skalierung über die gemessene Hülle hinaus **[Stufe 0 gemessen, Stufen 2–4 abgeleitet]**

**[gemessen] P2, der Anker bei 40 Spielern:** 40 echte ENet-Clients, ~50 Entitäten,
60-Hz-Vollzustand ohne jede Optimierung, 10-Minuten-Lauf mit Zufallsbewegung und
Fähigkeits-Spam. Ergebnis: Host-Tickdauer **Mittel 0,44 ms, p95 0,60 ms, p99 0,77 ms,
max 11,9 ms** gegen ein Gate von 16,6 ms; Upstream **20,7 Mbit/s**; Lua-Heap stabil bei ~12 MB.
**Stufe 0 der Leiter trägt bis dahin** — keine Entkopplung der Snapshot-Rate, kein
Relevanzfilter, keine Delta-Kompression. Wer bei dieser Größenordnung optimiert, optimiert
ohne Messung. Der p95 liegt eine Größenordnung unter dem Budget: der Kopf nach oben ist groß,
und der erste Engpass wird die Sim sein, nicht das Packen (der Snapshot ist für alle Clients
identisch und wird **einmal pro Tick** gepackt — Packkosten wachsen nicht mit N).

Für größere Welten (viele Entitäten, > 40 Spieler, MMORPG-artig) bleibt die Architektur
dieselbe — Host-autoritativ, Clients senden Inputs, Lockstep bleibt aus denselben Gründen
unerreichbar. Was sich ändert, ist nur die Snapshot-Strategie. **Eskalationsleiter — jede
Stufe erst betreten, wenn die Rechnung oder Messung es verlangt, nie prophylaktisch:**

1. **Erst rechnen, dann optimieren:** Snapshotgröße × Tickrate × Clientzahl gegen die
   LAN-Bandbreite halten. Ein Gigabit-LAN trägt Größenordnungen mehr, als die Intuition
   vermutet; im LAN ist fast immer die **Host-CPU** (Sim + N-faches Packen) der erste Engpass,
   nicht die Leitung. Wer ohne Rechnung Delta-Kompression baut, bezahlt Komplexität für ein
   Problem, das er nicht hat.
2. **Snapshot-Rate von der Tickrate entkoppeln** (Sim bleibt 60 Hz, Snapshots z. B. 20–30 Hz).
   Kosten: Der Renderer braucht Interpolation zwischen Snapshots für fremde Entitäten — damit
   ist die Zwei-Zeitbasen-Frage aus §3 zurück. Antwort bleibt Rebase + Replay für alles, womit
   der Spieler direkt interagiert; die Interpolations-Vergangenheit ist nur dort akzeptabel,
   wo keine Nahinteraktion stattfindet.
3. **Relevanzfilter (Interest Management):** nur senden, was der Client sieht oder gleich
   sehen kann. Konsequenz, die mitentschieden werden muss: Die ganze Welt lokal vorzusimulieren
   wird unmöglich — Vorhersage auf die eigene Entität und ihre Nahzone begrenzen, ferne
   Entitäten rein aus Snapshots zeichnen. Der Filter ist Sim-nahe Logik → love-frei bauen und
   headless testen (§8).
4. **Delta-Kompression zuletzt.** Sie kauft Bandbreite gegen die teuerste Komplexität
   (Baseline-Verwaltung, Ack-Tracking, Resync-Pfade, die nie geübt werden) und ist im LAN fast
   nie nötig. Wer hier ankommt, sollte vorher §10 gelesen haben: gemessen statt vermutet.

Weitere Übertragungen aus den gemessenen Mustern:

- **Persistente Welt = Turnier-Muster (§6):** append-only Ereignis-Log als Wahrheit, genau eine
  `applyEvent`-Funktion, ein Schreiber (der Host), atomares Speichern mit tmp/bak. Die Gründe
  sind identisch: Recovery ohne eigenen Codepfad, ein Ableitungsweg, menschenreparierbare Datei.
- **Late-Join/Reconnect** wird bei langen Sessions vom Randfall zum Kernfeature: Vollzustand
  beim Join als Blocktransfer über den reliable Kanal, danach normale Snapshots. Die
  Discovery-Bake muss dafür während der Session weiterlaufen (§5, §7).
- **Dedizierter Host** (Rechner ohne Spieler) als Kommandozeilenflag derselben Binary
  (`--dedicated`), kein zweites Artefakt — dasselbe Prinzip wie `--beamer` in §7. Sinnvoll,
  sobald die Host-CPU der Engpass ist oder der Host-Spieler einen unfairen Latenzvorteil hätte,
  der bei der Spielart stört.

## 4. ENet + LuaSocket: die teuren Fallen

LÖVE bringt `lua-enet` und `luasocket` mit — **keine Fremdbibliothek für Netcode nötig**.
ENet für Spiel/Lobby (reliable + unreliable Kanäle), LuaSocket-UDP **nur** für Broadcast-Discovery
(ENet kann keinen Broadcast).

- **Ereignisschleife pro Frame vollständig leeren** (`while event do … event = host:service(0) end`),
  nie nur ein Ereignis je Durchlauf — bei 60 Hz Snapshots staut die Queue sonst sofort.
- **[gemessen] `peer:send` legt nur in die Queue.** Auf die Leitung geht ein Paket erst beim nächsten
  `service()`/`flush()`. Wer nur am Frame-Anfang serviced, verschickt alles einen Frame zu spät —
  je Richtung ~16 ms, die im Overlay wie Netzlatenz aussehen (App-RTT 77 ms bei ENet-RTT 20 ms).
  **`flush()` am Frame-Ende**, nachdem alle Ticks gefahren sind.
- **ENet-Peer-Timeout auf ~5000 ms** setzen — der Default (30 s) lässt tote Slots im LAN minutenlang stehen.
- **[gemessen] `lua-enet` wirft aus `host:service()` einen harten Lua-Fehler** („Error during
  service"), sobald der UDP-Socket irgendetwas meldet — auf macOS genügt dafür die
  **Firewall-Nachfrage bei einer unsignierten App** oder eine kurz wegfallende Schnittstelle.
  Ohne Absicherung beendet ein einzelner Socket-Fehler den ganzen Prozess: das Spiel stirbt in
  dem Moment, in dem der Gast den Firewall-Dialog noch vor sich hat. Gegenmittel ist ein
  **Netz-Guard in reinem Lua**, durch den `service`, `flush`, `send`, `broadcast`, `timeout`
  **und** `host_create`/`connect` laufen: Fehler werden geschluckt und gezählt (höchstens einer
  je Frame, sonst zählt die Service-Schleife denselben Fehler mehrfach), erst **~2 s
  ununterbrochener** Fehler gelten als Verbindungsverlust, und **ein einziger Erfolg setzt die
  Uhr zurück** — bestätigt der Nutzer die Firewall-Nachfrage, läuft das Spiel einfach weiter.
  Die Service-Schleife bricht beim ersten Fehler ab, statt zu drehen. Reine Lua-Fehlerpolitik
  heißt: headless testbar (Fälle „Dauerfehler kippt nach 2 s" und „abwechselnd Fehler/Erfolg
  tötet nie" gehören in die Suite). Der Ausfall endet im **Trennungsdialog des Spiels**, die
  technische Ursache im Debug-Overlay — nie als Absturz.
- **[gemessen] Die Peerzahl ist ein Argument von `enet.host_create(addr, peerCount, channels)`,
  und zu klein dimensioniert fällt sie erst im Stresstest auf.** 32 Peers tragen keine 40
  Spieler. Mit Reserve dimensionieren (Zielspielerzahl + ~20 %) und die Zahl im Stresstest
  gegen die echte Zielgröße fahren, nicht gegen die Entwicklungsgröße.
- **[gemessen] Ein Prozess kann denselben ENet-Port nicht zweimal binden.** Wer gleichzeitig
  zwei Host-Rollen hat (z. B. Turnier-Host + Match-Host): zweiter Wirt auf `*:0` (ephemer),
  tatsächlichen Port mit `host:get_socket_address()` zurücklesen und über die Kontrollverbindung
  melden. **Kein Portbereich mit Ausweichlogik** — der Ausweichpfad ist der Code, der erst am
  Partyabend zum ersten Mal läuft.
- **LuaSocket immer `settimeout(0)`**, gepollt in `love.update`. Blockierende Aufrufe halten die
  gesamte Hauptschleife an. Kein Thread nötig bei kleinen Datenmengen.
- **[gemessen] `socket.udp4()` statt `socket.udp()`:** LuaSocket 3.0 (in LÖVE 11.5) liefert bei
  `udp()` einen IPv6-Socket; `sendto` an `255.255.255.255` scheitert darauf mit „Host unbekannt",
  und die Discovery findet still nichts.
- Kanalaufteilung: **reliable** für Lobby/Kontrolle/Turnier, **unreliable** für Snapshots (veraltete
  sind wertlos, Neuübertragung schadet) und Inputs (Redundanz kompensiert).

### Wire-Format (Lua 5.1: kein `string.pack` — `love.data.pack`)

- **Little-Endian und explizit dimensionierte Typen** (`<`-Präfix, `i4`, `f`, `d`) — sonst
  interpretieren Win und macOS verschieden. **[gemessen]** `love.data.pack` selbst ist auf beiden
  Plattformen bitidentisch (per Test gegen feste Referenzbytes abgesichert — so einen Test schreiben!).
- 3-Byte-Header vor jeder Nachricht: `protoVersion, msgType, flags`. Abweichende Version beim Join
  **mit Klartext abweisen**, nicht per Timeout — auf jeder LAN-Party kursiert eine alte ZIP.
  Reserviertes `flags`-Feld beim Empfang **nicht prüfen** — sonst ist es für seinen Zweck
  (später erweitern ohne Versionssprung) wertlos.
- Zeichenketten mit Längenpräfix (`s1`), Sender kürzen vorher aufs Feldmaß. Kein `z`, keine feste
  Breite — ein fremder String verschiebt sonst den Rest der Nachricht. Große Nachrichten (`s4`) als
  benannte Einzelausnahme, nicht als Gewohnheit.
- **[gemessen] Die negative Null begradigen** (`x + 0.0` auf jedes Float-Feld vor dem Packen):
  IEEE 754 kennt ±0, und die Arithmetik erzeugt das Vorzeichen plattformabhängig (JIT vs.
  Interpreter). Fürs Spiel egal, für Byte-Prüfsummen ein Fehlalarm in jedem Ruhe-Tick.
- **Snapshot-Feldliste gegen den echten State erheben, nicht entwerfen** — und einen Test schreiben,
  der sie gegen den State erzwingt. Eine am Schreibtisch erfundene Liste kodiert Phasen, die es
  nicht gibt, und vergisst Sichtbares (Anzeige-Timer, Cooldowns). Faustregel: übertragen wird, was
  der Empfänger **zeichnet**; nicht übertragen wird, was sich aus dem Ruleset ableitet oder reine
  Sim-Buchführung ist. Anzeigewerte dürfen quantisiert werden (u1-Verhältnis statt Float).
- Kosmetik nicht übertragen: der Client leitet Partikel/Sounds aus **Zustandsübergängen zwischen zwei
  Snapshots** ab (Vorzeichenwechsel an der Wand = Wandtreffer …). Diese Ableitung ist eine reine
  Funktion über zwei Tabellen → love-frei bauen und headless testen, auch wenn sie zur Renderschicht
  gehört. Ehrlich dokumentieren, was **nicht** ableitbar ist (Ereignisse, die keine Spur im Zustand
  hinterlassen), und den Verzicht benennen.
- **Konfig-Daten selbstbeschreibend übertragen** (Schlüssel-Wert-Folge mit Name + Typkennung), nicht
  als festes Feldlayout: ein vergessener Layout-Nachzug ist ein stiller Zahlendreher, der erst am
  Partyabend auffällt. Zahlen dabei als `d` (float64) — ein Umweg über float32 verändert den Wert
  und damit den Hash der empfangenen Kopie.
- **Kanonische Serialisierung für alles, was gehasht wird:** Schlüssel sortiert, Zahlen fest
  formatiert (`%.17g` für Verlustfreiheit). `pairs()` liefert je Instanz andere Reihenfolgen —
  derselbe Inhalt ergäbe sonst verschiedene Hashes, und der Fehler zeigt sich erst live.
- Zwei Versionsbegriffe: `protoVersion` (harte Abweisung) und `buildHash` über alle Quelldateien
  (**nur Warnung** — sonst blockiert ein kosmetischer Patch das ganze Turnier).

### Fehlerdetektion: zwei Klassen, zwei Zähler

- **Protokollfehler-Detektor:** Host sendet periodisch eine Prüfsumme (djb2) **über die gepackten
  Snapshot-Bytes**; der Client packt den gelesenen Snapshot mit eigenem Code erneut und vergleicht.
  Findet: falsch interpretierte Snapshots, abweichende Feldlisten, verschiedene Builds.
  **Nie über die Zahlen hashen:** Host hält float64, die Leitung float32 — jede Zahlen-Prüfsumme
  schlägt in jedem bewegten Tick an; feste Formatierung (`%.3f`) verschiebt das nur auf
  Rundungsgrenzen = seltene, unerklärliche Fehlalarme, der teuerste Fehlertyp, weil er das Vertrauen
  in den Detektor zerstört. Über die Rohbytes des Empfangs hashen wäre eine Tautologie — erst das
  **erneute Packen aus der gelesenen Tabelle** prüft das Lesen. Fehlender Snapshot zählt als
  „fehlend", nicht als Desync (unreliable Kanal).
- **Vorhersagefehler** zählt der Korrekturzähler aus §3 separat. Ein gemeinsamer Wert sagt im
  Fehlerfall nicht, wer schuld ist — und das ist die Frage, die abends gestellt wird.
- **Debug-Overlay (F3) und CSV-Mitschnitt (F4, 1 Zeile/s) gehören in den Release-Build.** Das Overlay
  ist das einzige Diagnosewerkzeug, das am Partyabend existiert; ein Foto davon ist eine
  Momentaufnahme, eine CSV ist eine Messreihe. Dev-Builds loggen Abweichungen zusätzlich in eine
  Datei — **mit Zeilendeckel**, sonst füllt ein sich wiederholender Fehler die Platte.

## 5. Zero-Config-Discovery (UDP-Broadcast)

```
Host:    Socket auf festem Discovery-Port (reuseaddr), ANNOUNCE an alle Rundrufziele je 1 s,
         auf PROBE sofort unicast an die Absenderadresse antworten
Client:  Socket A auf flüchtigem Port ("*", 0) — fragen + Antwort empfangen
         Socket B auf dem Discovery-Port, falls frei — Announces mithören (Bind darf scheitern)
         PROBE alle 2 s an alle Rundrufziele; Liste nach ~5 s ohne ANNOUNCE bereinigen
Rundrufziele: 255.255.255.255  UND  <eigenes /24>.255  UND  127.0.0.1
```

- **Der suchende Client bindet den Discovery-Port nicht fest** — sonst laufen Host und Client nie
  auf demselben Rechner (genau der Test- und „mal kurz schauen"-Aufbau). Deshalb Unicast-Antwort auf PROBE.
- **[gemessen] `255.255.255.255` allein reicht nicht:** die Adresse ist an keine Schnittstelle
  gebunden; mit VPN/Hyper-V/VirtualBox/WSL wählt die Routentabelle die falsche. Die aus der eigenen
  IP abgeleitete Subnetz-Broadcastadresse ist gebunden und kommt an. Das PROBE zusätzlich an
  `127.0.0.1` macht den Lokalfall OS-unabhängig (30 Byte).
- **Lobby-ID in jedem ANNOUNCE:** ein Host auf demselben Rechner antwortet über Loopback **und**
  LAN-Adresse und stünde sonst doppelt in der Liste. Einträge mit gleicher ID zusammenführen,
  `127.0.0.1` bevorzugen.
- Magic-Bytes + derselbe 3-Byte-Header wie im Spielprotokoll; Fremdpakete still verwerfen.
- **Die Bake muss während des Matches weiterlaufen** — genau im Reconnect-Fall wird sie gebraucht.
  Vorsicht mit Szenen-Systemen, die nur die oberste Szene aktualisieren (§7).
- **Manuelle IP-Eingabe ist Pflichtfeature, nicht Notlösung** — als letzter Eintrag sichtbar in der
  Serverliste, und der Host zeigt seine LAN-IP groß in der Lobby. Firewall-Wegklicken, „öffentliches"
  Windows-Netzwerkprofil und Client-Isolation im WLAN sind der häufigste Ausfallgrund, und die
  IP-Eingabe funktioniert immer, wenn `ping` funktioniert.
- Namen sind im Netz Kennungen (Lobby, HUD, Bracket): Dubletten beim Join **durch Anhängen lösen**
  („ 2", „ 3"), nicht durch Ablehnen — Abweisen kostet drei Schritte gegen das
  Time-to-First-Match-Budget. Der Gast erfährt seinen tatsächlichen Namen aus dem Lobby-Zustand.

## 6. Turniermodus: absturzfest oder wertlos

Ein Turnier scheitert nie an der Bracket-Logik, sondern an: jemand ist auf dem Klo, ein Laptop
stürzt ab, jemand kommt zu spät, niemand weiß, wer dran ist. **Ein Turniersystem, das einen Absturz
nicht übersteht, ist schlechter als ein Zettel — ein Zettel stürzt nicht ab.**

- **Wahrheit ist ein append-only Ereignis-Log.** Bracket, Tabellen, Zustände sind daraus ableitbar.
  **Genau eine Funktion (`applyEvent`) mutiert den abgeleiteten Zustand** — Recovery, Netzsync und
  Live-Betrieb laufen alle durch sie. Diese eine Entscheidung trägt alles andere: Recovery ist dann
  kein eigener Code.
- **Atomar persistieren nach jedem Ereignis:** tmp schreiben → alte .bak löschen → json→bak →
  tmp→json. **[gemessen]** `love.filesystem` kann nicht umbenennen (kein rename/move in 11.5) —
  `os.rename` mit absoluten Pfaden aus `getSaveDirectory()` nehmen. Und `os.rename` überschreibt
  unter Windows **nicht** (POSIX schon) — für die strengere Plattform schreiben. Zwischen den beiden
  letzten Schritten existiert kurz keine Hauptdatei: genau dafür ist die .bak da; ein Absturz im
  Fenster kostet höchstens das letzte Ereignis.
- **Format der Datei: JSON mit eigenem Mini-Encoder** (~180 Zeilen für Objekte/Listen/Strings/
  Zahlen/Bool/null, sortierte Schlüssel, `%.17g`). Die Datei ist ein **Betriebsmittel**: Der Fall,
  für den sie existiert, ist der, in dem die Software versagt und ein Mensch sie nachts im Editor
  flicken muss. Kein `loadstring` auf Save-Dateien (eine halb geschriebene Datei lädt schlimmstenfalls
  eine syntaktisch ganze, inhaltlich halbe Tabelle). Die Datei enthält den abgeleiteten Zustand
  **zusätzlich** für den Menschen; der Lader ignoriert ihn und rechnet nur aus dem Log — ein Test,
  der beide Fassungen vergleicht, prüft laufend die Aussage „das Log ist die Wahrheit".
- **Über die Leitung gehen Log-Ereignisse, nie der abgeleitete Zustand.** Ein Log wächst nur hinten:
  die Differenz zweier Stände ist immer ein Suffix → Sync ist `fromIndex` + Nachforderung bei Lücke,
  ohne Invalidierung, ohne Resync-Pfad, der nie geübt wird. Ein übertragener Fertigzustand wäre ein
  zweiter Ableitungspfad — beim ersten Auseinanderlaufen unentscheidbar. Empfänger sind rein lesend;
  jede Bedienung geht als Nachricht an den Turnier-Host (ein Schreiber pro Log). Unbekannte
  Ereignisarten verwerfen und zählen, nicht anwenden. Erstübertragung in Blöcken.
- **Deterministische Tiebreaker, kein Münzwurf, kein Stillstand.** Jede Stelle, an der der Automat
  sonst würfeln oder stehenbleiben müsste, bekommt eine Regel mit **einem einzigen, vorab
  feststehenden Anker** (z. B. Setznummer aus sichtbarem Seed): beidseitiger No-Show → Walkover für
  den Höhergesetzten; Offline-Blockade → eigener Timer ab dem Moment, ab dem das Match sonst spielbar
  wäre; Gleichstand nach genau einer Stichsatzrunde → Anker entscheidet (sonst ist Terminierung
  nicht beweisbar). **Ein** Anker für alle Gleichstandsfragen — zwei Anker sind zwei Wahrheiten,
  und abends weiß niemand, welche wo gilt. Jede solche Entscheidung landet als Log-Eintrag mit
  Begründungstext: ein unerklärbares Ergebnis ist teurer als ein unbeliebtes.
- **Messwerte entscheiden nur oberhalb einer Schwelle.** Host-Wahl per RTT: Median (nicht Mittel —
  ein GC-Ausreißer kippt sonst die Wahl) über ~5 s, entscheidet nur bei > 5 ms Unterschied, darunter
  der Anker. Ein Maß, das auf Rauschen entscheidet, ist ein Münzwurf mit Messgerät. Messwerte und
  Grund der Wahl ins Log (die Frage „warum hostet der?" kommt garantiert); die Rohproben nicht —
  ins Log gehört nur, was die Rekonstruktion überleben muss. Verbindungsstatus ist Laufzeitzustand,
  kein Log-Ereignis.
- **Ergebnisse schreibt der Match-Host aus dem Simulationszustand**, Spieler melden nichts —
  „beide behaupten gewonnen zu haben" kann damit nicht auftreten. Ausbleibende Meldung: nach 60 s
  nachfragen, dann Match neu ansetzen (Host-Absturz ist nicht die Schuld eines Spielers → kein Walkover).
- **Export als Markdown/CSV per Tastendruck** ist die einzige echte Versicherung: versagt die
  Software komplett, läuft das Turnier vom Ausdruck weiter. Für Menschen ohne Software geschrieben
  (Namen statt IDs, Einheiten im Spaltenkopf, Korrekturen markiert). Rein lesende Tasten darf jeder
  drücken. Direkt geschrieben, ohne tmp/bak — der nächste Druck ersetzt einen missglückten Export.
- Weichere Betriebsregeln, die den Abend retten: Freilose und Gruppenaufteilung automatisch aus der
  Teilnehmerzahl (abends stehen 17 oder 23 Leute da, niemand will rechnen); Gruppenphase vor K.o.
  (reines Single Elim schickt die Halbe Party nach einem Match nach Hause); parallele Matches ab
  ~12 Teilnehmern Pflicht, sonst dauert der Abend 3,5 h; Aufruf mit **Signalton** (niemand starrt
  auf sein Menü); ausgeschiedene Spieler sofort zurück ins freie Spiel; manuelle Ergebniskorrektur
  nur als protokolliertes `manual_override` mit Begründung.

## 7. App-Struktur: Szenen mit Sockets

Ein Szenen-Stack, der nur die oberste Szene aktualisiert, ist für lokale Spiele richtig
(Nichtaktualisieren **ist** die Pause) — und bricht bei der ersten Szene, die Sockets hält:
Der ENet-Wirt darunter wird nicht mehr bedient, nach dem Peer-Timeout gelten alle als offline.
**[gemessen]** — und der erste Flicken (Verbindung in die obere Szene durchreichen) ist ein
Sonderfall, der bei jeder weiteren Socket-Szene neu gebaut werden müsste.

- Lösung: Szenen melden sich mit `alwaysUpdate = true` an; `update` treibt die oberste **und** jede
  so markierte darunter (von unten nach oben). Eingabe-Events bekommt weiterhin nur die oberste.
- **Ein Netzspiel pausiert nie einseitig.** Menü über dem Netzspiel hält es nicht an; die eigene
  Eingabe ist währenddessen **neutral** (nicht Repeat-Last — das ist hier Absicht, keine Lücke).
  Eine Pause, die nur eine Seite kennt, ist ein Desync mit Ansage. Wer im Ballwechsel ins Menü geht,
  verliert den Punkt — seine Entscheidung.
- ESC beendet im Netz-/Turnierkontext nichts; das Verlassen ist ein benannter Menüpunkt.
- `conf.lua`: Version pinnen, ungenutzte Module abschalten (`physics`, `video`, `thread`, …).
  Beamer-/Zweitmodus als Kommandozeilenflag derselben Binary (`--beamer`), kein zweites Artefakt.
- Fonts/Sounds einmal laden (nie `newFont` im draw); Sounds als kleiner Stimmen-Pool statt Klonen.

## 8. Tests: vier Ebenen, headless zuerst

| Ebene | Was | Läuft |
|---|---|---|
| A | Physik-Regression gegen Referenz-Replays | headless (pures Lua), CI |
| B | Regel-Unit-Tests (Punkte, Satzende, Deuce, Queues, Lobby, Snapshot-Codec) | headless, CI |
| C | Netzwerk-Integration: zwei echte Prozesse auf 127.0.0.1, Eingabe-Injektion | Skript |
| D | Manuelle Abnahme: Blindtest Spielgefühl, LAN-Simulation, Turnier-Chaos-Szenario | Hand |

- Die Trennlinie im Netzcode: **alles, was entscheidet, ist rein und headless testbar**
  (Snapshot-Codec-Logik, Jitter-Puffer, Lobby-Zustand, Vorhersage, Prüfsumme); nur der Transport
  braucht enet/socket. Genau die reinen Teile tragen die Fehler, die am Abend teuer sind.
- Ein Testflag, das die love-Freiheit **beweist** (Sim laden mit vergiftetem `love`-Global), hält
  die Regel maschinell.
- Byte-Golden-Test fürs Wire-Format: ein voller Snapshot gegen feste Referenzbytes, auf Win- und
  macOS-CI — fängt Endianness, Packformat und die ±0-Falle.
- Selbsttest-Flags im Quellordner (`--net-selftest`, `--tournament-selftest` mit N Prozessen und
  Exit-Codes) machen Netz- und Turnierabnahmen wiederholbar; zwei Instanzen auf einem Rechner
  brauchen getrennte Identitäten (`--client-id`), weil sie sich die Prefs-Datei teilen.
- Chaos-Szenario als Turnier-Abnahme: N Teilnehmer (simulierte Clients erlaubt), währenddessen
  gezielt No-Show, Client-Kill im Satz, Turnier-Host-Kill zwischen Runden, Rechnerwechsel,
  Match-Host-Kill bei parallelen Matches. Erfolg = Turnier endet korrekt mit ≤ 2 manuellen Eingriffen.
- **[gemessen] Das gebaute Paket aus einem fremden Verzeichnis testen**, nie aus dem Repo-Wurzel:
  Lua findet `tests/`/`tools/` sonst über den Suchpfad der Arbeitskopie und meldet grün, ohne das
  Paket geprüft zu haben. Testflags gehören zum Quellordner; das Paket wird gespielt.
  Schärfste Form der Gegenprobe: nach dem Release die **fertige `.exe` aus dem Release
  herunterladen** und mit `--headless --test` fahren — das prüft Paketwurzel, Suchpfade und
  angehängtes Archiv in einem Zug (§12).
- **[gemessen] Integrationstests nie über eine feste Zeitspanne definieren, sondern über ein
  Ergebnisziel** („bis > 50 Treffer gefallen sind", Deckel als Notausgang). Eine feste Frist ist
  auf dem eigenen Rechner großzügig und auf einem langsameren oder mitbenutzten CI-Runner
  zu knapp: derselbe Test lief lokal durch und riss auf dem macOS-Runner die 150-s-Frist mit
  32 statt > 50 Treffern. Das sieht wie ein Flake aus, ist aber eine Messgröße mit falscher
  Einheit — Zeit statt Fortschritt.
- Paketverlust simulieren: Windows `clumsy`, macOS `dnctl/pfctl`, Linux `tc netem`.

## 9. Betrieb (LAN-Party-Realität)

- **Kabel schlägt WLAN, immer.** Switch + Kabel gehören auf die Packliste als Festlegung, nicht als
  Empfehlung — empfohlene Hardware bringt niemand mit. Vorher fragen, wer keine Ethernet-Buchse hat.
- Zielmetrik: **Time-to-First-Match ≤ 90 s ab ZIP-Download.** Jede Funktion, die Erklärung braucht,
  steht unter Verdacht.
- Firewall ist der häufigste Ausfallgrund: Windows-Abfrage „Private Netzwerke" ankreuzen;
  weggeklickt = für den Abend unsichtbar. Auf die Beamer-Folie: „ZIP erst entpacken, dann starten"
  und der macOS-Rechtsklick-Weg (Ad-hoc-Signatur). Niemand liest LIESMICH-Dateien auf einer Party.
- Der Turnier-Host-Rechner: kein Standby, kein Windows-Update, nicht der Laptop von jemandem, der
  um Mitternacht heimfährt — ohne Failover steht das Turnier, solange er aus ist.
- Fehlermeldungen im Spiel als Klartext mit Handlungsanweisung („Regelwerk stimmt nicht überein →
  Preset neu laden"), nie als Timeout oder Code.
- Nach dem Abend: Netlogs/CSV einsammeln — echte Netzwerkdaten von echter Hardware schlagen jeden
  Labortest. Drei Fragen beantworten: Wie lange brauchte der langsamste Gast? Wie oft griff der
  Turnierleiter ein? Hat sich etwas „falsch angefühlt"?

## 10. Arbeitsweise, die diese Qualität erzeugt hat

- **Spec vor Code, ADRs vor Implementierung** — jede Architekturentscheidung mit Kontext,
  verworfenen Alternativen und einem **Revisionsauslöser** („woran erkennt man, dass die
  Entscheidung neu bewertet gehört"). Der Revisionsauslöser ist das wertvollste Feld: Er ersetzt
  „für immer richtig" durch „richtig, bis X eintritt".
- **Gemessen statt vermutet:** Behauptungen über Plattformverhalten (rename-Semantik, Broadcast,
  Port-Bindung, Float-Bytes) mit einem Minimaltest belegen, bevor darauf gebaut wird — die Hälfte
  der [gemessen]-Punkte oben widersprach der ersten Annahme.
- **Eine Wahrheit pro Frage:** ein Hash, ein Ableitungspfad, ein Gleichstands-Anker, eine Physik.
  Jede Zweitkopie driftet still und zeigt sich als scheinbares Netzproblem.
- Betriebstauglichkeit vor Feature: „Was passiert, wenn jemand den Stecker zieht?" ist die Frage an
  jeden Vorschlag. Eine Funktion, die einen Absturz oder No-Show nicht übersteht, ist nicht fertig.
- Lua-5.1-Realität einplanen: kein `string.pack`, kein Integer-Typ, kein `//`; JIT auf Apple Silicon
  aus → Performance dort separat prüfen.

**Zahlen und Balancing (P2, trug den gesamten Zahlenteil):**

- **Alle Spielzahlen in genau einer flachen Tabelle**, je Eintrag `{wert, min, max, schritt,
  quelle}`. Das Live-Tuning-Panel **generiert sich vollständig daraus** — keine Variable wird je
  von Hand ins UI gebaut, also kann auch keine vergessen werden. Derselbe Zwang, der die Sim
  ehrlich hält, macht das Panel gratis.
- **Headless-Sim vor dem ersten Playtest.** Ein grobes, schnelles Modell (1D-Distanz, 0,1-s-Ticks,
  kein Pathing) beantwortet Balancing-Fragen in Sekunden statt in LAN-Abenden. Es teilt mit dem
  Spiel **ausschließlich die Zahlentabelle**, nie die Mechanik — zwei Simulationen, eine
  Zahlenquelle.
- **Falsifikationskriterien als automatisches Pass/Fail formulieren**, bevor getunt wird
  („Siegquote bei N=10 zwischen 60 und 90 %", „der Heil-Maximierer verliert in > 95 % der Läufe").
  Erst dann ist ein Sweep eine Messung statt einer Meinung. Zu jedem gerissenen Kriterium gehört
  ein vorher benannter **Stellhebel** — sonst wird beim ersten roten Ergebnis am nächstbesten
  Wert gedreht.
- **[gemessen] Deterministisch-homogene Agenten erzeugen Stufenfunktions-Siegquoten.** Ein Band
  wie „60–90 %" ist erst mit Streuung eine messbare Größe: je Agent ein Skill-Faktor, je Lauf ein
  gemeinsamer Koordinationsfaktor, beide deterministisch aus dem geloggten Seed. Die Streuung ist
  Sim-Modellparameter, nicht Spielverhalten — die Sim bleibt reproduzierbar.
- **[gemessen] Eine Testpyramide ohne Zeichentest hat ein Loch in der Mitte — und zwar genau dort, wo
  der Spieler steht.** Die love-freien Stufen (Unit, Determinismus) rufen den Renderer nie auf, der
  headless-Integrationstest läuft mit abgeschaltetem Grafikmodul, und Screenshot-Gegenproben treffen
  immer nur den einen Zustand, in dem der Bot gerade ist. In diesem Projekt hat ein Refactoring eine
  lokale Variable entfernt, die zwanzig Zeilen weiter unten noch benutzt wurde: **jede Wiederbelebung
  stürzte ab**, alle Gates waren grün, und das Release ging raus. Gegenmittel ist billig: ein Modus,
  der den Renderer für jede Klasse und jeden Zustand einmal wirklich ausführt und bei jedem Lua-Fehler
  rot wird — 150 Zeichenläufe in fünf Sekunden. Drei Details entscheiden über seinen Wert: die Sichten
  **durch den echten Netz-Codec** bauen (so prüft er Renderer und Wire-Format gegeneinander), **jede
  Maus-Hover-Position** mit abklappern (Tooltips sind eigene Zweige, die sonst nie laufen), und ihn in
  der CI auf Linux mit `xvfb` + Software-GL fahren — Windows-Runner haben kein OpenGL 2, macOS ist
  zehnmal so teuer.
- **[gemessen] Ein Zustandszweig, den der Testaufbau nie erreicht, ist ungetestet — auch wenn er
  „abgedeckt" aussieht.** Der Bot-Spieler in den Screenshot-Läufen war fast immer Geist oder Leiche,
  also lief der Zweig „lebend mit Klasse" in keinem einzigen Bild. Bei Zustandsmaschinen die Zustände
  **aufzählen und erzwingen**, statt zu hoffen, dass ein Durchlauf sie streift.
- **[gemessen] Die Nachweismatrix wächst schneller als ihr Nutzen — und niemand merkt es.** Eine
  Matrix aus vier Dimensionen war nach ein paar Runden auf 2,5 Stunden je Nachweis gewachsen,
  obwohl **drei Viertel ihrer Zellen eine Dimension variierten, die längst per Entscheid
  festlag** und deren Wert die Zahlentabelle selbst herleitet. Vor jeder Optimierung deshalb
  erst zählen, welche Zelle überhaupt ein Kriterium trägt: die überflüssige Dimension zu
  streichen war 4x, die Parallelisierung 5x und das Optimieren des heißen Codes nur 1,2x wert.
- **[gemessen] Die Sim ist peinlich parallel — und pures Lua reicht dafür.** Zellen sind
  unabhängig; `io.popen` startet Kindprozesse gleichzeitig und liefert unter Windows wie POSIX
  dieselbe Mechanik, wenn der Interpreterpfad aus dem `arg`-Vektor kommt (der Eintrag mit dem
  negativsten Index). Bedingung für gleiche Ergebnisse: **der Zellen-Seed hängt am Zellindex,
  nicht an der Abarbeitungsreihenfolge** — dann sind seriell und parallel bitgleich, und das
  gehört gegengeprüft, nicht geglaubt.
- **Jede Quote mit ihrem Vertrauensbereich berichten.** 300 Läufe sind ±5 pp, 1.000 Läufe ±2,7 pp.
  Ohne diese Zahl liest man Rauschen als Ergebnis — im eigenen Projekt maß ein Kriterium
  („Krits entscheiden nichts, ≤ 5 pp") mit 2,3 pp jahrelang überwiegend sein eigenes Rauschen
  (Niveau ~1,6 pp). Wer das nicht ausweist, tunt gegen Zufall.
- **[gemessen] Die drei billigsten Hotspots einer Lua-Sim** (zusammen 18 %): eine `assert`-Meldung,
  die bei **jedem** Aufruf zusammengebaut wird statt nur im Fehlerfall; ein `require` im Rumpf
  einer heißen Funktion (Ausweg aus einem Ringschluss — gehört in einen faul gefüllten Upvalue);
  eine Tabelle, die je Tick neu allokiert wird, statt einen Puffer wiederzuverwenden.
- **Ein Log-Leser ist billiger als ein weiterer Playtest.** Das Event-Log wurde jeden Abend
  geschrieben und **von nichts gelesen** — dabei beantwortet es genau die Fragen, für die man
  sonst Menschen befragt (Siegquote, Trylängen, ob die vorgesehene Rolle überhaupt gespielt
  wurde). Ein zweihundert Zeilen langes Auswertungsskript verwandelt jeden gespielten Abend in
  Messdaten. Zwei Details, die es tragfähig machen: den Leser durch **denselben Serialisierer**
  testen, den der Host benutzt (sonst driftet das Schema still), und die **abweichenden
  Parameter** mit ausweisen — sonst vergleicht man Zahlen aus zwei verschiedenen Welten.
- **Tuning-Protokoll als Ergebnisgedächtnis:** jede Balancing-Änderung mit Datum, **Auslöser** und
  **Ergebnis** an ein fortlaufendes Kapitel anhängen. Ohne das wird derselbe Wert dreimal in
  verschiedene Richtungen gedreht, weil niemand mehr weiß, warum er dort steht.
- **Dem Menschen die Regler erklären, statt für ihn zu drehen.** Eine Seite „Symptom → Regler →
  Richtung → Nebenwirkung" macht den Besitzer des Spiels handlungsfähig und spart die halben
  Nachweisläufe. Sie muss maschinell geprüft werden (nennt sie einen Parameter, den es nicht
  mehr gibt, schlägt der Test fehl) — eine Anleitung, die auf umbenannte Werte zeigt, ist
  schlimmer als keine.
- **Mensch nur fürs Gefühl.** Alles Messbare (Invarianten, Sweeps, Stresstest, Gates) prüft die
  Maschine selbst; der Mensch wird mit fertigem Validierungsbericht und **je einer Ein-Satz-Frage
  pro offenem Punkt** gerufen. Playtest-Zeit ist die knappste Ressource im Projekt.
- Kleinigkeit mit Zähnen: **GitHub schließt Issues nur über englische Schlüsselwörter**
  (`closes #12`). Wer Commits und PRs auf Deutsch schreibt, schließt seine Issues von Hand —
  sonst wächst die Arbeitsschlange still weiter, obwohl alles erledigt ist.

## 11. Asset-Kontrakt: Platzhalter → Final ohne Codeänderung

Ziel: Das Spiel ist ab Tag 1 voll spielbar und testbar, und die finalen Bilder und Sounds
tauschen sich später ein, **ohne dass eine Zeile Spielcode fasst**. Das entkoppelt die
Programmierung vollständig von der Kunst — beides ist sonst gegenseitig blockiert.

- **Kein Dateipfad im Spielcode.** Nur logische IDs aus einem Manifest
  (`id → {datei, maße, anker, frames}`). Ein Pfad im Spielcode ist eine Zusage an ein Dateisystem,
  die auf der anderen Plattform oder im gepackten Archiv anders lautet.
- **Platzhalter werden generiert, nie gemalt** — ein Werkzeug erzeugt aus dem Manifest einfarbige
  Formen in exakt den finalen Maßen, mit Kürzel-Beschriftung. Im Icon-Look ist der generierte
  Platzhalter dem Final so nah, dass komplette Meilensteine damit spielbar sind. Audio analog:
  Sinus-Blips; Musik-/Ambience-Slots spielen Stille, bis eine Datei liegt.
- **Ein Validator prüft jede echte Datei gegen den Kontrakt und läuft in der Testsuite.** Ein
  falsch geliefertes Final-Asset fällt damit im Test auf, nicht am LAN-Abend.
- **[gemessen] Der Kontrakt muss echte Menschen-Exporte aushalten, nicht die Idealdatei.** Was
  real ankam: `icon_krieger.png.png` (Windows blendet bekannte Endungen aus — der Standardfehler,
  und er wiederholt sich), 500×500 und 696×225 statt der vereinbarten 32×32, ein Icon mit Rand
  auf breiter Leinwand. Konsequenzen, die alle drei Fälle billig machen:
  - Der Validator erkennt die **doppelte Endung** und **sagt den korrekten Namen an**, statt nur
    „unbekannte Datei" zu melden.
  - Finale Bilder dürfen **größer** sein als das Manifest-Maß, müssen aber quadratisch sein; die
    Zeichenschicht **normalisiert beim Zeichnen** auf das Manifest-Maß. So bleiben
    hochauflösende Exporte scharf, und trotzdem steht nirgends im Spielcode eine Bildgröße.
    Nicht quadratisch = Fehler mit Ansage, nicht stille Verzerrung.
  - Ein Zuschneide-Werkzeug liegt daneben als **Werkzeug**, nicht als Build- oder Testschritt.
    Einmalige Reparaturen gehören nicht in die Pipeline, sonst laufen sie ewig mit.
- **[gemessen] Bildschirmfüllende Flächen `contain` zeichnen, nicht `cover`.** Ein 4:3-Splash auf
  einem 16:10-Fenster verliert bei `cover` oben und unten Streifen — also genau dort, wo Logo und
  Ladebalken sitzen. Schwarzer Rand ist hässlicher als nichts und besser als abgeschnitten. Solche
  Slots im Manifest als „mindestens"-Maß kennzeichnen, damit der Validator sie anders behandelt.
- Dateinamen strikt klein, keine Umlaute, keine Leerzeichen; Zeilenenden per `.gitattributes` auf
  LF erzwingen. Beides sind Fallen, die ausschließlich auf der jeweils anderen Plattform zünden.

## 12. Lieferpipeline: ein Tag, drei Pakete

Verteilung am LAN-Abend ist ein Release-Link, kein Ordner im Chat. Ein Tag `v*` baut alles.
**Die `.love` ist die eine Wahrheit**; `.exe` und `.app` sind dieselbe Datei mit einer
Laufzeitumgebung davor.

- **Archivwurzel ist der ganze Trick.** `main.lua`/`conf.lua` müssen in der **Wurzel** des
  ZIPs liegen, daneben die Quellbäume — LÖVEs Zip-Loader löst `require("modul.datei")` gegen die
  Archivwurzel auf. Wer den Projektordner mitverpackt, bekommt ein Archiv, das lokal funktioniert
  und gepackt nichts findet. **Im Build danach greifen** (`unzip -l … | grep " main.lua"`, dazu
  eine tief liegende Moduldatei) — zwei Zeilen, die den häufigsten Paketfehler unmöglich machen.
- **[gemessen] Auf Windows das Icon setzen, *bevor* die `.love` angehängt wird.** Das
  Ressourcen-Werkzeug schreibt die PE-Ressourcen neu und wirft angehängte Daten dabei weg — in
  der falschen Reihenfolge entsteht eine `.exe` mit hübschem Icon und ohne Spiel. Danach die
  mitgelieferte `love.exe`/`lovec.exe` aus dem Paket **entfernen**, sonst startet der Gast das
  falsche Programm.
- **[gemessen] Das `.app`-Bundle mit `zip -y` packen.** Ohne Symlink-Erhalt werden die
  Frameworks zu Kopien und das Bundle ist kaputt. Dazu die `Info.plist` umschreiben
  (`CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier`, `CFBundleIconFile`) und die
  Icon-Datei ersetzen, auf die sie zeigt — sonst heißt das Spiel im Dock weiterhin „LÖVE", und
  die vom Engine-Bundle geerbten Dateityp-Zuordnungen bleiben ebenfalls hängen.
- **Icons ohne Bildwerkzeug in der Pipeline.** `.ico` (Windows ab Vista) und `.icns` (macOS ab
  10.7) dürfen PNG-Daten **direkt einbetten**: Kopf schreiben, Bytes anhängen — das sind ~100
  Zeilen reines Lua. Eine Abhängigkeit weniger in der Pipeline ist eine Fehlerquelle weniger an
  dem Tag, an dem das Release gebraucht wird.
- **LÖVE-Version pinnen** (herunterladen statt „was der Runner hat") und ungenutzte Module in
  `conf.lua` abschalten. Der Build von heute muss in sechs Monaten dasselbe Paket erzeugen.
- Das Release gegenprüfen, indem die **heruntergeladene** Datei den Selbsttest fährt (§8).

## 13. CI-Ökonomie: die Job-Anzahl ist der Hebel

Cross-Platform-Beweis heißt Matrix, und eine Matrix auf gehosteten Runnern kostet — auf einem
privaten Repo echtes Geld, überall Wartezeit. **[gemessen] Der Verbrauch hängt fast nur an der
Job-Anzahl, kaum an der Testdauer:** Abgerechnet wird **pro Job auf die volle Minute aufgerundet
und erst danach mit dem OS-Faktor multipliziert** (Linux 1×, Windows 2×, macOS 10×). In P2 lief
eine Fünf-Job-Matrix 26 Sekunden und kostete 24 abgerechnete Minuten — 20 davon für zwei
macOS-Jobs mit zusammen 21 Sekunden echter Rechenzeit. Mit Triggern auf `push: main` **und**
`pull_request` zahlte jedes gemergte Feature das doppelt: 48 Minuten pro PR, und ein einziger
Bautag verbrauchte 98 % eines Monatskontingents.

- **Ein Schnellgate, ein Job.** Alle headless-Stufen laufen nacheinander in **derselben**
  Linux-Job-Instanz. Das ist zugleich das schnellere Feedback: ~40 s bis rot/grün, während
  Paketmanager-Installationen in einer Matrix Minuten brauchen. Tests zu beschleunigen bringt
  dagegen nichts — bei 10–20 s Laufzeit frisst die Aufrundung jede Ersparnis.
- **Die Matrix daneben, nicht darin.** Ein zweiter Workflow trägt Windows + macOS. Ist das
  Budget knapp, hängt er an `workflow_dispatch` und einem Label; ist es das nicht, hängt er an
  jedem PR. Beides ist eine Zeile Unterschied — **diese Zeile gehört mit ihrem Auslöser in einen
  ADR**, sonst ist nach der nächsten Budgetänderung niemand mehr sicher, warum es so steht.
- **Ein wöchentlicher `schedule` auf der Matrix** fängt Drift, die keinen Commit hat:
  Runner-Images, Paketstände, Fremd-Downloads. Zwischen zwei LAN-Abenden pusht niemand, und
  genau dann fault die Pipeline unbemerkt.
- **[gemessen] Auf Windows headless testen heißt `lovec.exe`, nicht `love.exe`.** `love.exe` ist
  ein GUI-Subsystem-Binary ohne angehängte Konsole — die Testausgabe ist unsichtbar. Auf
  Linux/macOS `SDL_VIDEODRIVER=dummy` setzen. Damit läuft die Integrationsstufe **auf allen drei**
  Plattformen; auf der Plattform, auf der entwickelt wird, ist sie besonders wertvoll, weil sie
  als einzige Stufe Pfade, Zeilenenden und Dateizugriff echt anfasst.
- **Ein Sammel-Gate als Pflicht-Check.** Ein einzelner Job mit `needs` auf die Matrix, der die
  Ergebnisse prüft, ist der stabile Name für die Branch-Schutzregel. Die Matrix-Namen direkt zu
  fordern (`test (macos-latest)` …) bricht bei jeder Matrix-Änderung, und der Bruch zeigt sich
  als unmergebarer PR.
- **`paths-ignore` und erzwungene Status-Checks vertragen sich nicht.** Ein reiner Doku-PR wartet
  dann ewig auf einen Check, der nie startet, und lässt sich nicht mergen. Bei kurzer Laufzeit ist
  Immer-Laufen die einfachere Wahrheit als eine Ausnahmeliste.
- `concurrency` mit `cancel-in-progress` in jedem Workflow: überholte Läufe sterben, statt bezahlt
  zu Ende zu laufen.
- **Branch-Schutz für ein Ein-Personen-Projekt:** PR-Pflicht und Pflicht-Checks ja, aber **null**
  erforderliche Reviews (sonst blockiert sich der einzige Entwickler selbst) und **kein**
  `enforce_admins` (sonst gibt es am Partyabend keinen Notausgang).
- Kostenloser Ausweg, falls das Budget trotzdem klemmt: Ein **öffentliches** Repo hat unbegrenzte
  Minuten. Für ein Hobbyprojekt ohne Geheimnisse ist das der billigste Hebel von allen — vor dem
  Umschalten einmal nach Zugangsdaten im Verlauf greifen, danach ist es öffentlich.
