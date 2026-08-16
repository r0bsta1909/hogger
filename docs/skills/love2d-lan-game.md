---
name: love2d-lan-game
description: Erprobte Architektur- und Netcode-Muster für LÖVE2D-Spiele mit LAN-Multiplayer in jeder Konstellation — 1v1-Sportspiel, Arena-Shooter, Koop, persistente Welt/MMORPG-artig — plus Zero-Config-Discovery und Turniermodus. Laden bei jedem Projekt mit LÖVE/love2d + Netzwerk (ENet, luasocket, Snapshots, Lockstep-Frage, Skalierungsfragen), LAN-Party-Betrieb oder integriertem Turniersystem — vor der ersten Architekturentscheidung und vor der ersten Zeile Netzcode.
---

# LÖVE2D-Spiel für LAN und Turnier — destillierte Learnings

Quelle: ein vollständig durchgezogenes Projekt (Arcade-Sportspiel, Win + macOS, 20-Teilnehmer-Turnier,
zwei echte LAN-Abende). Alles hier ist gebaut, gemessen oder teuer schiefgegangen — nichts ist Theorie.
Punkte mit **[gemessen]** sind Fallen, die erst im echten Betrieb auffielen.

**Geltungsbereich:** Die gemessene Hülle ist: kleiner Weltzustand (zweistellige Bytezahl pro
Snapshot), 2–8 aktive Spieler pro Match, LAN-RTT < 5 ms. §1, §2, §4, §5, §7–§10 gelten
**genre-unabhängig** für jedes LÖVE2D-LAN-Projekt — die Fallen dort hängen an Plattform, Lua 5.1
und ENet/LuaSocket, nicht am Spieltyp. §6 gilt, sobald ein Turnier gebraucht wird (und sein
Event-Log-Muster generalisiert auf jede persistente Welt). Nur die Snapshot-Strategie in §3
ist skalenabhängig; §3.1 gibt die Eskalationsleiter für größere Welten. Abschnitte mit
**[abgeleitet]** sind aus den gemessenen Prinzipien gefolgert, aber nicht selbst im Betrieb
verifiziert — dort gilt §10 doppelt: erst messen, dann eskalieren.

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

### 3.1 Skalierung über die gemessene Hülle hinaus **[abgeleitet]**

Für größere Welten (viele Entitäten, > 8 Spieler, MMORPG-artig) bleibt die Architektur
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
