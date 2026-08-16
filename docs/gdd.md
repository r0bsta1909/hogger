# HOGGER MUSS STERBEN
## Game Design Document v2.0 — LÖVE2D LAN Koop-Zerg für 5–40 Spieler

**Projekt:** Privates Spaßprojekt (LAN-Party-Highlight, FRAGZEIT-Umfeld)
**Engine/Netz:** LÖVE2D über LAN nach Volley-Dash-Muster (Host-autoritativ, direkte Client-Verbindung, kein Hub)
**IP-Status:** Privat, WoW-Namen, -Icons und -Referenzen werden 1:1 verwendet
**Datum:** 2026-08-15

**Changelog v2.6 (M1-Befunde, Rob-Entscheidungen zu Issues #2/#3/#4):** Hogger erhält **Rundumschlag (Cleave)**: Autohit trifft bis zu `ceil(N/8)` Ziele im Nahkampf, Divisor justierbar im Panel — Begründung: sein Droh-Durchsatz muss mit N skalieren, sonst überrollen große Raids (M1-Kapazitätsbeweis; Fiktion: umzingelt drischt der Gnoll um sich) · Fress-Unterbrechung moderat verschärft: Schadensschwelle 2,5 % → 5 % Max-HP, Unterbrecher `ceil(N/10)+1` → `+2` · Nahkampf-Reichweite 40 px festgeschrieben (war unspezifiziert) · Sim-Agenten erhalten ein **Streuungsmodell** (Skill-Faktor je Spieler 0,7–1,3 auf verursachten Schaden, Gruppenfaktor je Lauf 0,75–1,25; Kap. 17.2) — ohne Streuung sind Siegquoten-Bänder wie F1 nicht messbar · Klarstellung Todesstrafe: Gesamtstrafe = N-skalierender Respawn-Timer (9.3) + Geisterlauf + Restanmarsch; die Feldposition verschiebt den Laufweg-Anteil · **M1-Sweep-Fixierung (alle Werte im Tuning-Panel justierbar):** Hogger-HP affin `430 × N − 950` (der Sockel bildet den Kleingruppen-Overhead ab; Formel per Sweep bestimmt — die Siegquoten-Bänder je N kollabieren exakt auf eine Gerade), Cleave-Divisor 5, Charge-CD 10 s, Respawn `clamp(8 + 0,52 × N; 10; 30)`, Laufweg 14 s (Geist 8 s + Anmarsch 6 s) → Gesamttodesstrafe 24,6 s (N=5) bis 42,8 s (N=40)
**Changelog v2.5 (ADR-001, Kap. 14):** Snapshots mit voller Tickrate 60 Hz als Vollzustand statt 20 Hz + Interpolation; Client-Input 60 Hz mit 3-Tick-Redundanz statt 30 Hz; Client-Darstellung per Rebase + Replay (eine Zeitbasis). Begründung, Rechnung und Revisionsauslöser in `docs/adr/001-snapshot-strategie.md`.
**Changelog v2.4 (Review-Einarbeitung):** Fünf-Sekunden-Regel statt Kein-Regen (10 Mana/s nach 5 s Cast-Pause, Vanilla-authentisch; Manatränke bewusst abgelehnt) · Charge wählt nur Ziele im Leash-Radius + 2-s-Leash-Hysterese gegen versehentliche Full-Heal-Resets · Fress-Unterbrechung zusätzlich per Schadensschwelle (≥ 2,5 % Max-HP im Kanal) gegen Stalling · Heil-Bedrohung 1,5 → 0,75 (Panel-Parameter) · Render-Hierarchie + Floating-Text-Budget + gedimmte Geister gegen Icon-Gulasch bei N≥20 · IP-Fallback-Zeile im Glitch-Screen nach 5 s Discovery-Fehlschlag · Turtle-Agent in der Sim gegen Heil-Stalling
**Changelog v2.3:** Wiederbelebung nicht am Friedhof, sondern am Wiederbelebungsfeld am Ende des Elwynn-Pfads Richtung Hogger · Die acht Klassenicons sind nur als Geist sichtbar und verschwinden nach der Wiederbelebung · Statt 40 dominanter Leichen nur dezent verstreute Totenkopf-Icons · Geistheiler ist funktionslose Szenerie mit Gag · Feldposition als expliziter Todesstrafen-Stellhebel im Tuning-Panel
**Changelog v2.2:** Der eigene Spieler ist der goldene Minimap-Pfeil im Zentrum (kein eigenes Klassenicon), nur andere Spieler/NPCs/Hogger sind Icons · Springen mit Leertaste als reines Feel-Feature (Sound, Pfeil-Hüpfer, Icon-Feedback bei anderen, Sprungzähler auf der Statistik-Tafel)
**Changelog v2.1:** Totensicht-Filter nur im Geist-Zustand (Spielstart tot, nach Wiederbelebung normale Farben) · Alle Allianz-Rassen und damit alle acht Klassen zurück (Mehrheit Mensch, ~1/3 andere Rassen, Rasse wird bei Wiederbelebung regelkonform ausgewürfelt, rein kosmetisch) · Leeroy als vollwertiger KI-NPC mit Pathfinding, der jeden Try mit den Spielern zu Hogger zieht · UI-Spezifikation an Referenzbildern ausgerichtet (Zonenbanner, Einheitenfenster mit Portrait/Stufenmedaillon, Elite-Drachenrahmen für Hogger, Ziel-des-Ziels) · Referenzbilder nach `docs/referenzen/`
**Changelog v2.0 (Neuschrieb entlang der Spielerlebnis-Beschreibung):** Das gesamte Spiel findet als bildschirmfüllende runde WoW-Minimap statt — nur Icons, keine Models · Fake-Client-Rahmung (wow.exe, Original-Ladescreen, Glitch) · Leeroy Jenkins als verfluchter NPC-Raid-Lead, Erzähler und Announcer · Fluch-Fiktion als Siegbedingung · Klassenwahl durch Betreten von Klassenicons am Friedhof, Namenseingabe im Leeroy-Intro · Try-Struktur mit hochzählender Uhr statt Countdown · Chat, Realmliste, Charaktererstellungsfenster, Cinematic und Text-Emotes ersatzlos gestrichen bzw. durch Leeroy ersetzt · XP-Leiste als Bogen an der Minimap-Innenkante · Funktionales Minimap-Zoom als Informationsmechanik · Minimal-Soundliste
**Frühere Versionen:** v1.0–v1.5 im Archiv (`docs/archiv/`); alle dort validierten Systeme (Fressen, Skalierung, Krits, Netcode, Test-Pyramide, GitHub-Workflow) sind hier unverändert übernommen, sofern nicht ausdrücklich geändert.

---

## 1. Vision & Spielerlebnis

**So erlebt es ein Spieler:** Auf dem Desktop liegt ein Icon, das aussieht wie das originale WoW-Icon, die Datei heißt `WoW.exe`. Er startet sie und sieht den originalen Ladescreen — dann glitcht das Bild, wird schwarz, und langsam erscheint etwas Neues: nicht der Login-Screen, nicht das Cinematic, sondern die **Totensicht** — der Spieler beginnt tot, als Geist am Friedhof, alles liegt unter dem bläulich-geisterhaften Entsättigungsfilter des Originals (Referenz: `docs/referenzen/totensicht.png`). Nur: Die runde Minimap füllt den gesamten Bildschirm. Sie IST das Spiel. Keine 3D-Welt, keine Models — nur Icons, Symbole, Pfeile und die vertrauten UI-Elemente rund um die Minimap (Referenz: `docs/referenzen/minimap.webp`). Am Friedhof im Wald von Elwynn wartet neben dem Geistheiler ein einzelnes Krieger-Icon: **Leeroy Jenkins.** Er erklärt den Fluch, fragt nach dem Namen, und dann stellt sich der Spieler auf eines von acht Klassenicons und belebt sich wieder — **der Blaufilter fällt ab, die Welt hat wieder normale Farben** — und er rennt mit dem Raid gegen einen Gnoll an, der nicht fallen will. Stirbt er, kippt die Welt zurück in die Totensicht, bis zur nächsten Wiederbelebung.

**Der Totensicht-Filter ist also ein Zustand, kein Dauerlook:** bläuliche Entsättigung + Geister-Wind + Audio-Tiefpass ausschließlich solange der eigene Charakter tot ist. Der Minimap-Icon-Look dagegen gilt immer.

**Intendierter Effekt (unverändert der Kern):** Kollektives Gelächter beim Sterben, kollektiver Triumph beim Kill. Neu hinzu kommt die **Rätselhaftigkeit des Rahmens** — die ersten Minuten, in denen der Raum begreift, was er da gerade gestartet hat ("Moment — das ist die MINIMAP?"), sind ein eigener geplanter Comedy-Beat, der genau einmal pro Spieler funktioniert und deshalb ungestört ablaufen muss (keine Erklärtexte, kein Tutorial, Leeroy erklärt nur die Fiktion, nie die Bedienung).

**Design-Konsequenzen:**
1. Der einzelne Tod ist folgenlos und komisch; die Todesstrafe (Respawn + Geisterlauf, gesamt 25–35 s) bleibt die tragende Balancing-Konstante des Attrition-Modells.
2. Der Sieg entsteht durch Gruppenlogistik (Fressen unterbrechen, Charge ködern, Respawn-Wellen), nicht durch Einzelskill.
3. Die Icon-Darstellung ist kein Sparzwang, sondern Fiktion: Leeroy selbst wundert sich, warum hier alles "so flach" ist. Jede Darstellungsentscheidung muss die Frage beantworten: "Wie würde die WoW-Minimap das zeigen?"

**Nicht-Ziele:** Keine Progression mit Wirkung, kein Loot mit Wirkung, keine Meta zwischen Trys außer XP/Kupfer-Zählern und dem Try-Zähler. Ein Try ist eine abgeschlossene Anekdote.

---

## 2. Fiktion: Der Fluch des Leeroy Jenkins

Leeroy Jenkins, einst Level-60-Mensch-Krieger, wurde welt-berühmt durch seinen unbedachten Sturmangriff samt Schlachtruf des eigenen Namens in einen Raum voller Drachenwelpen — kompletter Wipe der Gruppe. Der Hexenmeister seiner Gruppe verfluchte ihn dafür: **Leeroy führt auf ewig als Level-1-Mensch-Krieger einen aussichtslosen Hogger-Raid als Raid-Lead an.** Der Fluch bricht erst, wenn der Raid Hogger besiegt — dann sind Leeroy und alle Spieler frei.

Der Raid läuft bereits zum x-ten Mal, wenn neue Spieler das Spiel betreten. Die Gefallenen vergangener Versuche — mehrheitlich Menschen, aber gut ein Drittel Zwerge, Nachtelfen und Gnome aller Klassen, denn genau so haben sich echte Hogger-Raids zugetragen — sind auf der Karte als **dezent verstreute Totenkopf-Icons** präsent: einige um den Hügel, einige entlang des letzten Wegstücks. Genug, um das häufige Sterben zu verdeutlichen; nie so viele, dass die Karte unübersichtlich wird (Richtwert: ~10–12 statische Schädel, kleiner gerendert als mechanische Leichen). Diese Deko-Schädel sind reine Szenerie — Hogger frisst ausschließlich frische Spielerleichen. Leeroys bisheriger Raid bestand nach eigener Aussage "aus lauter Vollpfosten" und ist von jetzt auf gleich verschwunden — "ausgeloggt", "disconnected", wer weiß das schon. Spieler kamen und gingen aus Langeweile, keiner blieb. Nur Leeroy hat keine Wahl.

Leeroy erinnert sich nur an den Charge in die Welpen und den Wipe; danach tauchte er hier auf — als Icon, in einer Welt, die "so flach" ist. Er hat aufgehört, die Trys zu zählen.

**Der Fluch hat ihn geteilt** (v2.7): Was mit den Spielern redet, ist das **Echo von Leeroy Jenkins** — es steht am Friedhof, gibt die Quest, kommentiert alles und **muss dabei zusehen, wie seine eigene physische Gestalt Try um Try in denselben Gnoll chargt und abgeschlachtet wird.** Der Körper da vorne hört nichts, lernt nichts und schreit einmal pro Try seinen eigenen Namen. Die Strafe des Hexenmeisters ist damit vollständig: Leeroy muss sich selbst ewig beim Sterben zusehen — und den Neuen dabei freundlich erklären, dass Ablehnen keine Option ist.

**Fiktion als Systemklammer:** Der Fluch erklärt jede Spielmechanik diegetisch — warum alle Level 1 sind und bleiben (Fluch), warum man nach dem Tod zurückkommt (Fluch), warum man die Klasse wechseln kann (man belebt sich als eine der herumliegenden Leichen wieder), warum es kein Entkommen von der Karte gibt, und warum der Sieg das Spiel beendet (Fluchbruch). Nichts davon wird je als "Spielregel" erklärt.

---

## 3. Boot-Sequenz: Der falsche Client

Ablauf beim Start von `WoW.exe` (Gesamtdauer ≤ 20 s, ab dem zweiten Start pro Rechner per Klick überspringbar bis zum Glitch-Ende):

1. **Fenster öffnet mit Original-Ladescreen** (Vanilla-Splash), dazu die ersten Sekunden der Login-Musik.
2. Optional einmal pro Client pro Abend: kurzer Einblendungs-Gag "Position in der Warteschlange: 1 — Geschätzte Wartezeit: 4 Stunden" (1,5 s).
3. **Glitch:** Bild zerreißt (Scanlines, Versatz, Audio-Static), wird schwarz. 2–3 s Stille.
4. **Langsame Aufblende in die Totensicht:** Die runde Minimap baut sich unter dem Geist-Blaufilter auf (alle starten tot), Geister-Wind-Ambience setzt ein. Der Spieler steht als Geist-Icon am Friedhof. Leeroy beginnt zu sprechen (Kap. 5). Der Filter verschwindet erst mit der ersten Wiederbelebung.

**Verbindung, unsichtbar:** Während Schritt 1–3 läuft die LAN-Discovery. Findet der Client einen Host, verbindet er sich; findet er keinen, **wird diese Instanz selbst der Host** — der erste Spieler, der `WoW.exe` öffnet, ist der Realm. Kollision bei gleichzeitigem Start: Der Beacon mit dem ältesten Zeitstempel gewinnt, die anderen Instanzen degradieren sich automatisch zu Clients. Es gibt keinen sichtbaren Server-Browser, keine Realmliste, keine IP-Eingabe im Normalfall — die Fiktion kennt kein Menü. Schlägt die Discovery 5 s lang fehl (verwaltete Switches blockieren gelegentlich UDP-Broadcasts), erscheint im Glitch-Bild eine unaufdringliche, als Fehlerkonsole getarnte Zeile: "Realm nicht gefunden — IP:" mit Eingabefeld — der Fallback bleibt in der Fiktion. Weitere Notfall-Werkzeuge (Host erzwingen, Lautstärke) liegen im Debug-Overlay (F12), das kein normaler Spieler je sieht.

**Verbindungsabbruch/Host-Crash:** Authentischer WoW-Disconnect-Dialog ("Vom Server getrennt." — OK-Button), danach zurück zum Glitch-Schwarz und automatischer Reconnect-Versuch. Fehlerbehandlung als Fiktion recycelt.

---

## 4. Präsentation: Die Minimap ist das Spiel

Das gesamte Spiel findet in einem einzigen Look statt — 2D, ausschließlich Icons und Symbole, keine Models, keine Sprites von Figuren.

### 4.1 Bildaufbau

- **Die runde Minimap füllt die Bildschirmhöhe.** Der rechteckige Rest des Screens (Ecken, Seitenstreifen) ist mit dem dunklen WoW-UI-Hintergrund gefüllt — dort leben ausgelagerte UI-Elemente (4.3). **Zonenbanner** oben am Kreis wie im Original (Referenz `minimap.webp`: "Goldshire"): zeigt die aktuelle Unterzone ("Friedhof von Elwynn", "Der Elwynn-Pfad", "Wiederbelebungsfeld", "Hogger Hill") — billige Orientierung ganz ohne großes Kartenfenster.
- **Der eigene Spieler ist der goldene Spielerpfeil exakt im Zentrum** der Minimap — genau wie im Original (Referenz `minimap.webp`), kein eigenes Klassenicon. Der Pfeil zeigt die Blickrichtung, die der Maus folgt; die Welt bewegt sich unter ihm. Norden ist fixiert (N-Marker am Ring, keine Kartenrotation). Die eigene Klasse ist über das Einheitenfenster oben links jederzeit sichtbar.
- **Alle ANDEREN Entitäten** sind Icons mit Richtungspfeil, sofern sie sich bewegen: andere Spieler = ihr jeweiliges Klassenicon, Hogger = eigenes größeres Icon mit Pfeil, Ambient-Mobs = kleine Mob-Icons, Leeroy = markiertes Krieger-Icon, Geistheiler = Engel-Icon, Leichen = Totenkopf-Icons, die acht Wiederbelebungs-Klassenicons am Wiederbelebungsfeld (7.1) als begehbare Bodenmarker — **nur im Geist-Zustand sichtbar** und für den jeweiligen Spieler ausgeblendet, sobald er sich wiederbelebt hat. Das hält die Karte für Lebende aufgeräumt.
- **HP/Mana/Energie/Wut anderer Spieler und Gegner** werden als Mini-Balken direkt am jeweiligen Icon angezeigt. Geister anderer Spieler sind halbtransparente Versionen ihres Klassenicons; der eigene Pfeil ist im Geist-Zustand blass-bläulich (zusätzlich zum Vollbild-Filter).
- **Totensicht als Zustand:** Solange der eigene Charakter tot ist, liegt der bläuliche Entsättigungsfilter über dem gesamten Bild (Referenz `totensicht.png`) plus Geister-Wind und Audio-Tiefpass. Mit der Wiederbelebung springt die Welt in normale Elwynn-Farben zurück — dieser Farbwechsel ist das stärkste Zustands-Feedback des Spiels und braucht keinerlei Text.
- **Floating Combat Text** an den Icons — die Zahlen sind der Witz und bleiben maximal sichtbar. **Die Richtung ist ablesbar** (Playtest 2026-08-16): eigener ausgeteilter Schaden weiß, selbst erlittener Schaden rot, fremder Schaden gedämpft grau, Heilung grün; **Krits groß mit Ausrufezeichen** und Punch-Sound — gold, wenn man sie austeilt, glutrot, wenn man sie kassiert. Ein erlittener Treffer legt zusätzlich einen kurzen roten Rand an die Innenkante des Kreises.
- **Angriffe sind sichtbar, nicht nur ihre Zahlen** (Playtest 2026-08-16): jeder Treffer erzeugt für ~0,2 s ein Symbol von der Quelle zum Ziel — Geschoss in Schulfarbe (Feuer orange, Schatten violett, Heilig weißgold, Natur grün), Jäger-Pfeil als Spur, Zauberstab als fahlblauer Blitz, Nahkampf als kurzer Schlagbogen am Ziel, Charge breiter, Heilung als aufsteigender Ring. Weiterhin ausschließlich Symbole, keine Sprites; Effekt-Budget wie beim Floating Text. Die Zuordnung kommt aus dem Feld `art` des Schadensereignisses (17.3), nicht aus geratenen Schadenshöhen.
- **Render-Hierarchie (Pflicht gegen Icon-Gulasch bei N≥20), von unten nach oben:** Boden/Pfad → Deko-Schädel → mechanische Leichen → Geister (kleiner, gedimmt — dauerhaft 10–15 Geister sind gewolltes Hintergrundrauschen) → lebende Spieler-Icons → Leeroy → Mobs/Adds → Hogger → Floating Text → Ring-UI. Dazu ein **Floating-Text-Budget**: maximal ~30 gleichzeitige Texte, priorisiert eigene Ereignisse und Krits, der Rest wird still verworfen (Objekt-Pool, kein GC-Druck).
- **Springen (Leertaste):** rein fürs Gefühl, null Mechanik — kein Ausweichen, keine Kollisionsänderung, keine Reichweitenänderung. Feedback: WoW-Sprunglaut + Landegeräusch, der eigene Pfeil macht einen kurzen Hüpfer (Scale-Bounce + Mini-Schatten), und **die Klassenicons anderer Spieler im Sichtfeld hüpfen mit**, wenn deren Spieler springt (Jump-Flag im Snapshot, 1 Bit pro Entität). WoW-Spieler hüpfen permanent — wenn 15 Icons auf dem Weg zum Hügel synchron hoppeln, ist das Feel geliefert. Der Host zählt Sprünge pro Spieler mit; die Zahl landet auf der Statistik-Tafel.

### 4.2 Minimap-Ring (nur, was das Spiel wirklich braucht)

Am Ring der Minimap sitzen ausschließlich funktionale Elemente im Add-on-Button-Stil:

- **Unten mittig: die Fähigkeiten der aktuellen Klasse** als runde Buttons mit Cooldown-Sweep und Tastenkürzeln (1–4). Nie mehr Buttons als die Klasse Fähigkeiten hat.
- **Zoom + / −** am Ring (klassische Minimap-Position), zusätzlich Mausrad. **Zoom ist eine Informationsmechanik:** drei Stufen; herauszoomen zeigt mehr Karte, aber kleinere Icons und Balken (Übersicht gegen Lesbarkeit). Die maximale Stufe zeigt nie die ganze Karte — wer wissen will, was am Hügel passiert, muss hinlaufen oder als Geist zusehen.
- **Die Uhr** an ihrer originalen Minimap-Position, **zählt pro Try von 0:00 hoch.**
- **XP-Leiste als dünner Bogen an der Innenkante des Minimap-Kreises** — dezent, aber ablesbar; füllt sich im Uhrzeigersinn. Tooltip bei Hover: "Noch 399 Erfahrung bis Stufe 2."

### 4.3 Außerhalb des Kreises (Eckbereiche)

- **Oben links: das eigene Einheitenfenster** nach Original-Vorbild (Referenz `spieleranzeige_und_ziel.png`): rundes Rassen-Portrait, Namensbalken, HP-Balken (grün), Ressourcenbalken (blau/rot/gelb je Klasse).
- **Oben rechts: das Zielfenster** (angeklickter Spieler oder Gegner): Portrait, Namensbalken (rot = feindlich, gelb = neutral), Stufen-Medaillon (Spieler und Mobs: "1", Hogger: **"11" im goldenen Elite-Drachenrahmen** — das Original-Signal für "das wird nicht gut ausgehen"), HP/Ressource, darunter klein das **Ziel des Ziels** (bei Hogger als Ziel: wen er gerade verprügelt — taktisch nützlich und authentisch). Zielwahl per Klick auf ein Icon oder Tab-Durchschalten.
- **Buff-/Debuff-Leiste** unterhalb des Zielfensters: nur Buffs, die Level-1-Klassen tatsächlich haben — Schlachtruf, Frostrüstung, Siegel der Rechtschaffenheit, Verstohlenheit; Mal der Wildnis existiert NICHT (Druiden lernen es erst später). Dazu der einzige Debuff auf Spielern: **Hoggers Blutung** (Vicious Slice, 9.2), rot umrandet. Original-Buff-Icons mit Restdauer, **Tooltip bei Hover** (Name, Wirkung, Restdauer) — die Zahlen darin kommen aus `model.lua`, damit Anzeige und Wirkung nie auseinanderlaufen.
- **Unterbrechungszähler** erscheint nur während Hoggers Fressen als Balken am Hogger-Icon ("2/4") — Pflicht-UI, siehe 9.2.

### 4.4 Was es bewusst NICHT gibt

**Keinen Chat. Kein großes Kartenfenster.** Keine Menüleiste, keine Taschen, kein Charakterfenster, keine Einstellungen im Spiel (Lautstärke etc. im Debug-Overlay). **Genau zwei Fenster gibt es**: die Statistik-Tafel (Kap. 11) und das Questfenster des Echos (Kap. 5) — beide erscheinen von selbst, beide schließen sich wieder. Jede Information, die früher als Systemmeldung im Chat gelandet wäre, kommt jetzt aus genau einer Quelle: **dem Echo von Leeroy Jenkins** (Kap. 10.1). Kommunikation zwischen Spielern findet auf der LAN statt, wo sie hingehört — im Raum.

---

## 5. Onboarding: Die Quest des Echos & Wiederbelebung

Jeder Spieler erlebt zu seinem individuellen Spielstart dasselbe Onboarding — lokal, während andere längst spielen (der Raid "lief ja bereits"). Es läuft so ab, wie ein MMO einem Spieler etwas beibringt, den es nie gefragt hat: **als Quest** (v2.7, Playtest-Runde 1).

1. Nach der Aufblende steht man als frische Leiche am Friedhof. **Bewegung gesperrt — man kann sich nur um die eigene Achse drehen.** Am Friedhof steht das **Echo von Leeroy Jenkins** (Kap. 10.1), Krieger-Icon, blass, grüner NPC-Name, **goldenes Ausrufezeichen** darüber (Referenz `questgeber-ausrufezeichen.jpg`).
2. Das Echo wartet nicht darauf, angesprochen zu werden: **es chargt heran** — Krieger bleibt Krieger — und drückt die Quest auf. Anklicken geht trotzdem, wer das Fenster wegklickt, holt es damit zurück.
3. **Das Questfenster** (Referenz `quest text beispiel.jpg`): Titelleiste mit Portrait und Namen, Questtitel "Der Fluch des Leeroy Jenkins", der komplette Intro-Text in Questgeber-Manier (Fluch, Gnoll, x-ter Try, verschwundener Vollpfosten-Raid, "wie FLACH hier alles ist"), Abschnitt **Questziele**, darunter das Namensfeld (2–12 Buchstaben, erster automatisch groß; Kollision: "Den gibt's schon. Streng dich an.", Fenster bleibt offen).
4. Unten links **Annehmen**, unten rechts **Ablehnen — ausgegraut und wirkungslos.** Der Knopf, der nichts tut, ist die Pointe: Ablehnen ist keine Option, das ist keine Redewendung. Mit der Annahme ist die Bewegung frei (host-seitig erzwungen), und **die erste angenommene Quest auf dem Realm startet den Raid-Leeroy** (Kap. 10.3).
5. Danach: "Such dir eine Leiche aus. Da vorne, am Ende des Wegs." Der Spieler läuft als Geist den Elwynn-Pfad hinunter zum **Wiederbelebungsfeld** (7.1): Dort, unmittelbar wo der Pfad endet und der Anmarsch auf Hogger beginnt, liegen die **acht Klassenicons** als begehbare Bodenmarker — **sichtbar nur für Geister**. Draufstellen, kurzer Wiederbelebungs-Channel (2 s), der Blaufilter fällt ab, der eigene Pfeil leuchtet wieder golden, die Klassenicons verschwinden aus der eigenen Sicht, und für alle anderen erscheint man ab jetzt als Icon der gewählten Klasse. Ab jetzt gilt der normale Loop.
   **Rasse:** wird bei jeder Wiederbelebung regelkonform ausgewürfelt — man belebt sich schließlich als eine der herumliegenden Leichen wieder. Verteilung: **⅔ Mensch, wo die Klasse es erlaubt**, Rest gleichverteilt auf die gültigen Vanilla-Kombinationen (8.2); Druide ist immer Nachtelf, Jäger immer Zwerg oder Nachtelf. Die Rasse ist **rein kosmetisch** (Portrait im Einheitenfenster, Namenszusatz in Killcam-Zeilen: "Der Gnom [Name] wurde …") — **keine Volksfähigkeiten**, bewusst gestrichen: Steingestalt & Co. würden die Antizufalls-Balance und die Klassenlesbarkeit für null Comedy-Gewinn verkomplizieren.
6. **Rejoin** nach Verbindungsabbruch oder erneutem Start am selben Abend: keine Quest, das Echo sagt nur "Ah. Wieder da." — Name und XP-Stand hängen am Charakternamen (session.json).

**Klassenwechsel** = bei jeder Wiederbelebung frei: einfach auf ein anderes Klassenicon stellen. Die erwartete emergente Raid-Komposition über die Trys hinweg bleibt der versteckte Lerninhalt des Spiels.

Dauer bis zur Questannahme: unter 60 Sekunden bei zügigem Lesen. Kein Wort der Bedienungserklärung — Bewegung, Klicken und sechs beschriftete Bodenicons müssen sich selbst erklären, und der Raum hilft ohnehin.

---

## 6. Kernloop & Try-Struktur

```
Boot → Quest des Echos (einmalig) → Geisterlauf zum Wiederbelebungsfeld → Klassenicon → Wiederbelebung →
kurzer Anmarsch zum Hogger Hill → Kampf → Tod → Geist freilassen → Geisterlauf zum Feld (Klassenwechsel möglich) →
... → Hogger fällt (FLUCHBRUCH, Sieg) oder Try endet (Wipe-Ansage durch Leeroy) → nächster Try
```

- **Ein Try** beginnt mit Leeroys Signal (Kap. 10) und endet mit Hoggers Tod ODER nach **15:00 auf der hochzählenden Uhr** — dann leasht Hogger zurück, heilt voll, Leeroy sagt den Wipe an ("Okay. Das war nichts. Nächster Try."), die Statistik-Tafel erscheint kurz (Kap. 11), der Try-Zähler tickt hoch, weiter geht's. Kein Menü, keine Lobby zwischen Trys — der Fluch macht keine Pausen.
- **Try-Zähler:** persistiert in session.json und startet beim allerersten Host-Start bei einer zufälligen vierstelligen Zahl (Leeroy zählt ja schon ewig). Angezeigt wird er nur in Leeroys Ansagen und auf der Statistik-Tafel.
- **Sekundenloop des Spielers:** hinlaufen → 5–15 s Uptime am Boss → Tod → liegen bleiben bis zur Freigabe (Kap. 11) → Geist → Wiederbelebung. **Die Gesamttodesstrafe bleibt die tragende Balancing-Konstante**, per M1-Sim-Sweep fixiert (Kap. 17, v2.6): Respawn-Timer (N-skalierend, 9.3) + 14 s Laufweg = 24,6 s bei N=5 bis 42,8 s bei N=40 — große Raids warten länger, damit die Welle dicht statt endlos wird. Nie nach Gefühl verändern.
- **N-Skalierung pro Try:** Hoggers Werte skalieren mit der Anzahl verbundener, wiederbelebbarer Spieler beim Try-Start. Wer mitten im Try joint, spielt sofort mit, zählt aber erst ab dem nächsten Try in die Skalierung. Leaver reduzieren nichts. Leeroy zählt nie mit.

---

## 7. Welt, Ambient-Mobs & die Stufe-2-Lüge

### 7.1 Karte

Eine zusammenhängende Karte (~3×2 Bildschirmradien bei mittlerem Zoom), als Datendatei geladen (Vorhalt für Modus 2):

- **Friedhof** (Nordosten): Geistheiler-Icon, Grabsteine, Zaun auf der Zonengrenze und die Standposition des **Echos von Leeroy Jenkins** (Kap. 10.1), das von dort aus zusieht; unantastbare Zone (Hogger betritt sie nie). Hier wird nur gespawnt, nicht wiederbelebt. Der **Geistheiler ist funktionslose Szenerie** — klickt man ihn an, kommentiert Leeroy: "Der funktioniert nicht mehr. Frag nicht."
- **Der Elwynn-Pfad** (Diagonale): der Weg vom Friedhof Richtung Südwesten, offene Fläche mit Baum-Icons als Sichtblocker und Charge-Köder-Geometrie, Fluss-Linie am Südrand.
- **Das Wiederbelebungsfeld** (eigene Unterzone im Zonenbanner): unmittelbar am Ende des Pfads, vor dem Anmarsch auf den Hügel, außerhalb von Hoggers Leash-Zone. Hier liegen die acht Klassenicons (nur für Geister sichtbar, Kap. 5) und ein paar der Deko-Schädel. **Die Feldposition ist ein Balancing-Hebel:** Sie teilt die Todesstrafe in Geisterlauf (Friedhof → Feld, 150 % Tempo) und lebendigen Restanmarsch (Feld → Hogger) auf — die Gesamtstrafe (24,6–42,8 s über N, Kap. 6) bleibt die Konstante, die Feldposition ist der Feinsteller dafür und liegt im Tuning-Panel (v2.6: Geisterlauf 8 s + Restanmarsch 6 s).
- **Hogger Hill** (Südwesten): Plateau mit Rampe, Hoggers Leash-Zone (Radius 600 px um die Hügelmitte; verlässt er sie, resettet er mit voller HP). Rundherum einige Deko-Schädel (Kap. 2).

### 7.2 Ambient-Mobs

Weit verstreut, außerhalb der Leash-Zone, nie auf der direkten Friedhof-Hügel-Achse. `4 + floor(N/5)` Spawn-Slots (N=5→5, N=40→12), Respawn 120 s am festen Punkt, leashen an ihren Spawn, kritten mit Standard-5 %:

| Mob | HP | Schaden | Verhalten | Detail |
|---|---|---|---|---|
| Wildschwein | 12 | 4 / 2,0 s | passiv, flieht bei 25 % HP | |
| Junger Wolf | 10 | 5 / 2,0 s | aggressiv ab 80 px | tötet Nachzügler — "von einem Wolf getötet, während 39 Leute Hogger zergen" ist eine Pflicht-Anekdote |
| Kobold-Arbeiter | 14 | 4 / 2,0 s | passiv | Aggro-Zeile über dem Icon: "Ihr nehmt nicht die Kerze!" |
| Murloc | 12 | 5 / 2,0 s | aggressiv, nur am Fluss | ikonischer Schrei-Sound — teuerster Einzelgag, unverhandelbar |

### 7.3 XP, Plunder, Kupfer

- **1 XP pro Mob-Todesstoß, Stufe 2 bei 400 XP** (Original-Vanilla-Wert). XP hängen am Charakternamen und **persistieren über den ganzen LAN-Abend** (session.json). Rechnung: max. ~100 Mob-Kills pro 15-Minuten-Try für alle zusammen — Stufe 2 ist theoretisch erreichbar (ein Besessener, ein ganzer Abend, jeder Killstoß), praktisch nie. Der Fluch hält Level 1; die XP-Leiste behauptet das Gegenteil.
- **DING-Easter-Egg (fertig im Code, ob es je zündet oder nicht):** Bei 400 XP volle Inszenierung — goldenes Aufleuchten des Icons, Original-Levelup-Sound, Leeroy-Ansage ("… das ist nicht möglich."), Statistik-Titel "der Zweite". Mechanischer Effekt: exakt null. Die Pointe ist, dass sich nichts ändert.
- **Plunder & Kupfer:** Mobs droppen graue Items (Pool ~12: Zerbrochener Eberzahn, Beschädigter Kerzenstummel, Glitschige Murloc-Flosse …) und 1–3 Kupferstücke (fester Wert je Mobtyp). **Kein Inventar** — Loot wird beim Aufheben sofort zu zwei Zählern (Plunder, Kupfer) plus Loot-Toast am Kreisrand. Kaufen kann man nichts; der Reichtum ist so nutzlos wie die Erfahrung, beides landet auf der Statistik-Tafel.
- **Ablenkungs-Leitplanke (testbar):** Mobs sind Beiwerk für Anlaufweg und Wartemomente, keine Alternative zum Boss. Prüfkriterium in Kap. 13.4; Stellhebel bei Verletzung: Spawns/Respawn-Zeit runter, niemals XP rauf.

---

## 8. Die acht Klassen der Allianz

Alle acht Vanilla-Allianz-Klassen sind im Spiel, mit ihren gültigen Rassen-Kombinationen. Jede Klasse hat exakt ihr Vanilla-Level-1-Startkit. Fester Schaden, einzige Zufallsquelle ist der 5-%-Krit.

### 8.1 Basiswerte

| Wert | Zahl | Anmerkung |
|---|---|---|
| Bewegung lebend | 140 px/s | Referenz |
| Bewegung als Geist | 210 px/s (150 %) | verkürzt die Todesstrafe |
| Autohit Nahkampf (weiß) | 2 Schaden alle 2,0 s | Krieger, Paladin, Schurke, Druide |
| Autoschuss (Jäger) | 3 Schaden alle 2,0 s, Reichweite 200 px | ersetzt den Nahkampf-Autohit; stärkste manalose Dauer-Distanz-DPS |
| Autohit Zauberstab | 2 Schaden alle 2,0 s, Reichweite 120 px | Priester, Magier, Hexenmeister — OOM-Caster stochern auf Distanz weiter, müssen aber näher ran als der Jäger und bleiben Charge-gefährdet |
| Nahkampf-Reichweite | 40 px | v2.6 festgeschrieben (Issue #2); Panel-Parameter |
| Global Cooldown | 1,5 s | drosselt Input-Spam |
| Frontbogen | 180° (Panel-Parameter `facing_arc_deg`) | Vanilla-authentisch: Angriffe gehen nur durch, wenn das Ziel **vor** einem liegt; Wegdrehen bricht einen laufenden Zauber ab (wie Bewegung). Die Blickrichtung folgt der Maus (4.1) und war bis zum Playtest 2026-08-16 rein kosmetisch. 360° schaltet die Regel ab |

**Fehlermeldungen** (v2.7): Der Host verwirft einen unmöglichen Versuch stumm — deshalb sagt der Client, woran es lag, als kurz aufblinkende rote Zeile im Ton des Originals: „Zu weit entfernt.", „Ziel ist nicht vor dir.", „Du hast kein Ziel.", „Nicht genug Mana/Wut/Energie.", „Keine Combopunkte.", „Das ist noch nicht bereit." Die Prüfregeln sind dieselben wie in der Sim und werden gegen sie getestet.
| Kritchance | 5 %, ×2 | beide Seiten, fester Multiplikator |

**HP nach Rüstungsklasse:** Platte (Krieger, Paladin) 80 · Leder/Schwer (Jäger, Schurke, Druide) 65 · Stoff (Priester, Magier, Hexenmeister) 50.
**Ressourcen:** Mana 100, voll bei Wiederbelebung, mit **Fünf-Sekunden-Regel** (Vanilla-authentisch): 5 s nach dem letzten Cast beginnt Regeneration mit 10 Mana/s — auch im Kampf. Caster verwalten damit kein endliches Budget mehr, sondern weben Cast-Pausen; OOM ist ein Zustand, kein Endzustand. Wut startet 0, +5 je erlittenem, +3 je ausgeteiltem Autohit. Energie 100, regeneriert 10/s.

### 8.2 Klassenkits

| Klasse | Rassen (Vanilla-Allianz) | Fähigkeit 1 | Fähigkeit 2 | Fähigkeit 3 / Passiv | Rolle im Zerg |
|---|---|---|---|---|---|
| **Krieger** | Mensch, Zwerg, Nachtelf, Gnom | Heroischer Stoß: 6 Schaden, 15 Wut | Schlachtruf: +15 % Schaden für Verbündete im Umkreis, 15 s, 10 Wut (stapelt nicht) | — | Frontlinie, hält 2–3 Hits länger als alle anderen |
| **Paladin** | Mensch, Zwerg | Heiliges Licht: 2,5 s Cast, heilt 25, 35 Mana | Siegel der Rechtschaffenheit: nächste 3 Autohits +3 Heiligschaden, 10 Mana | — | Zweitzäheste Klasse, Notheiler |
| **Jäger** | Zwerg, Nachtelf | Autoschuss (8.1) | Raptorstoß: 7 Schaden Nahkampf, 8 s Cooldown | — | Rückgrat der Dauer-Uptime auf Maximaldistanz |
| **Schurke** | Mensch, Zwerg, Nachtelf, Gnom | Finsterer Stoß: 5 Schaden, 40 Energie, +1 Combopunkt | Ausweiden: 4/8/12/16/20 Schaden bei 1–5 CP, 30 Energie | Verstohlenheit: unsichtbar, 60 % Tempo, Hogger ignoriert; bricht beim Angriff | Einzige Klasse, die sich der Charge entziehen und Fress-Unterbrechungen garantieren kann |
| **Priester** | Mensch, Zwerg, Nachtelf | Göttliche Pein: 1,5 s Cast, 6 Schaden, 15 Mana | Geringes Heilen: 2,0 s Cast, heilt 20, 25 Mana | — | Heilung = Bedrohung (9.4) — der Priester lernt Aggro auf die harte Tour |
| **Magier** | Mensch, Gnom | Feuerball: 2,5 s Cast, **11 Schaden** (höchster Einzelhit), 30 Mana | Frostrüstung: Selbstbuff; trifft Hogger den Magier, ist Hogger 3 s um 25 % verlangsamt | — | Glaskanone; macht den Magiertod strategisch wertvoll |
| **Hexenmeister** | Mensch, Gnom | Schattenblitz: 2,0 s Cast, 8 Schaden, 25 Mana | Wichtel beschwören: 3 s Cast, 30 Mana; Wichtel: 15 HP, Feuerblitz 2 Schaden/2 s, zieht kurz Aggro | — | Pseudo-Tank-Pet kauft Sekunden |
| **Druide** | Nachtelf | Zorn: 1,5 s Cast, 6 Schaden, 20 Mana | Heilende Berührung: 3,0 s Cast, heilt 30, 35 Mana | — | Hybrid: pro Leben entweder Schaden ODER zwei große Heals — nie beides gut |

**Design-Absicht pro Kit (testbar):** Erwartetes Verhalten — Jäger liefern die Grundlast auf Maximaldistanz, Schurken übernehmen Fress-Unterbrechung, Krieger/Paladine bilden die Köderfront, Magier positionieren sich absichtlich als Charge-Ziel für den Slow, Caster verwalten ihr Manabudget pro Leben. **Falsifiziert**, wenn im Playtest ≥6 von 8 Klassen identisch gespielt werden — dann Kit-Unterschiede verschärfen.

---

## 9. Hogger

### 9.1 Statemachine

```
IDLE (Hügel-Patrouille, 2 Wegpunkte)
  → AGGRO (Spieler in 250 px ODER Leeroys Try-Start-Charge trifft)
AGGRO/MELEE → RUSHING CHARGE (CD bereit + Ziel) → FRESSEN (Leiche in 200 px + HP < 90 % + CD)
  → LEASH-RESET (Distanz > 600 px durchgehend für 2 s [Hysterese] → zurück, Full Heal, IDLE; während CHARGE ist die Leash-Prüfung ausgesetzt)
TOD → Fluchbruch-Sequenz (Kap. 11)
```

### 9.2 Werte & Fähigkeiten

| Wert | Formel/Zahl | Anmerkung |
|---|---|---|
| **HP** | 430 × N − 950 (affin, v2.6), mindestens 120 × N | N=5: 1.200 · N=10: 3.350 · N=40: 16.250 — der Sockel bildet den Kleingruppen-Overhead ab; die Untergrenze fängt Wartelobbys unter der Design-Spanne (N<3) ab |
| Autohit | 30 Schaden alle 1,8 s | Stoff stirbt in 2, Platte in 3 Hits |
| Kritchance | 5 %, ×2 (= 60) | oneshottet alles außer voller Platte — der "WAS?!"-Moment |
| Tempo | 155 px/s | Weglaufen verzögert, rettet nicht |
| Leash | 600 px | Kiten unmöglich |

- **Rundumschlag (Cleave, ab v2.6):** Hoggers Autohit trifft zusätzlich bis zu `ceil(N/5) − 1` weitere Ziele mit Bedrohung im Nahkampf (insgesamt `ceil(N/5)` Ziele; bei N ≤ 5 reiner Einzelziel-Autohit — kleine Gruppen behalten den Vanilla-Gnoll). Divisor als Panel-Parameter, justierbar (Standard 5 per M1-Sweep). Grund: Hoggers Droh-Durchsatz muss mit N wachsen, sonst überrollen große Raids ohne Zusammenarbeit (M1-Befund, Issue #3); Fiktion: umzingelt drischt er wild um sich.
- **Vicious Slice** (alle 12 s aufs aktuelle Ziel): 15 Sofortschaden + Blutung 5/2 s über 6 s — garantiert den Tod Angeschlagener, verhindert Heraus-Heilen.
- **Rushing Charge** (CD 10 s, v2.6 — mehr Backline-Druck bei großen N): stürmt auf das am weitesten entfernte Ziel mit Bedrohung **innerhalb des Leash-Radius** (Ziele außerhalb sind nie Charge-Ziel — ein einzelner ungünstig stehender Jäger darf keinen Try ruinieren), 25 Schaden + 120 px Knockback, 0,8 s Anlauf mit blinkender Ziellinie auf der Minimap. **Kein Krit möglich.**
- **Fressen** (CD 20 s, Leiche in 200 px, HP < 90 %): zieht die nächste Leiche mit 1,0-s-Schlepp-Animation heran (schließt den Safe-Death-Exploit, dient als Wind-up), kanalisiert dann 8 s, heilt 1,5 % Max-HP/s (12 % gesamt). **Unterbrechung:** Treffer von `ceil(N/10) + 2` verschiedenen Spielern ODER kumulierter Schaden ≥ 5 % seiner Max-HP während des Kanals (v2.6, Issue #4: die alten Schwellen wurden von beiläufigem Schaden automatisch erfüllt) — die Schadensschwelle skaliert automatisch mit N und verhindert Stalling, wenn nach einem Frontlinien-Wipe kaum noch jemand in Reichweite lebt. **Zählerbalken am Hogger-Icon ("2/4") ist Pflicht-UI** — er lehrt das Wie; dass man während des Fressens angreifen muss, findet die Gruppe selbst heraus (bzw. Leeroy platzt irgendwann der Kragen, Kap. 10). Kein Krit auf Fress-Heilung, keine Krits auf Slice/Charge/DoT-Ticks — Choreo bleibt deterministisch.
- **Gnoll-Welpen:** `floor(N/8)` Adds (20 HP, 10 Schaden/2 s, kein Krit, kein Respawn im Try) am Hügelfuß — dünnen bei großen Gruppen die Wellen aus und geben Nahkämpfern frühe Erfolgserlebnisse.

### 9.3 Skalierung (pro Try-Start)

| Größe | Formel | N=5 | N=10 | N=20 | N=40 |
|---|---|---|---|---|---|
| Hogger HP | max(430 × N − 950; 120 × N) | 1.200 | 3.350 | 7.650 | 16.250 |
| Fress-Heilung/Kanal | 12 % Max-HP | 144 | 402 | 918 | 1.950 |
| Unterbrecher | ceil(N/10)+2 | 3 | 3 | 4 | 6 |
| Cleave-Ziele | ceil(N/5) | 1 | 2 | 4 | 8 |
| Adds | floor(N/8) | 0 | 1 | 2 | 5 |
| Respawn-Timer | clamp(8 + 0,52 × N; 10; 30) s | 10,6 | 13,2 | 18,4 | 28,8 |

**Keine Bots:** Bei kleinem N kompensiert der kurze Respawn-Timer die fehlende Masse — die Welle wird dichter, nicht größer. Der Sieg gehört immer echten Menschen (und Leeroy).

### 9.4 Bedrohung

1 Schaden = 1 Bedrohung, **1 Heilung = 0,75 Bedrohung** (über Vanilla-0,5, damit der Erste-Heilung-zieht-Aggro-Gag früh im Pull lebt, aber ohne dass Heiler nach jedem Spruch verdammt sind; Panel-Parameter). Melee-Ziel = höchste Bedrohung in Reichweite, sonst höchste gesamt. Bedrohung wird beim Tod gelöscht.

---

## 10. Leeroy Jenkins (NPC-Spezifikation)

**Es sind zwei Figuren** (v2.7, Playtest-Runde 1) — und genau das ist der Witz, den der Fluch möglich macht:

### 10.1 Das Echo von Leeroy Jenkins (Friedhof)

Was von Leeroy übrig ist, während sein Körper da vorne schon wieder losrennt. Das Echo steht am Friedhof, greift **nie** in den Kampf ein und muss zusehen, wie seine eigene physische Gestalt Try um Try anstürmt und abgeschlachtet wird. Es ist **Erzähler, Questgeber und Announcer**:

- **Questgeber:** goldenes Ausrufezeichen, grüner NPC-Name. Die Quest liegt mit dem Spielbeitritt an; die Annäherung ist eine **rein lokale Sequenz** (1,3 s), die nur der betroffene Spieler sieht — in der Welt bewegt sich das Echo nie, sonst würde bei 40 Beitritten auf demselben Spawnpunkt dauernd jemand über den Friedhof gechargt (Playtest-Korrektur 2026-08-16).
- **Nur Geister sehen es** (wie die acht Klassen-Bodenicons, 4.1): Lebende sehen und klicken es nicht.
- **Easter Egg:** Wer es als Geist erneut anklickt, bekommt die ganze Geschichte — mehrere durchblätterbare Seiten (Raid, Sturmangriff, Fluch, Erwachen, Teilung, warum es fragt). Null Spielwirkung, keine Belohnung, kein Hinweis darauf. Nur wer es findet.
- **Questlog:** Taste `L` blendet die Quest weg und zurück; nach der Annahme zeigt sie dieselbe Seite als Log (ohne Namensfeld, ohne Knöpfe).
- **Erzähler:** die Quest, kurze Zwischen-Zeilen am Friedhof, "Ah. Wieder da." beim Rejoin.
- **Announcer** (siehe 10.4): alle Kommentare gehören dem Echo — Fress-Alarm, HP-Meilensteine, Todeskommentare, Wipe-Ansage, der Kragen-Platzer. **Einzige Ausnahme: DER Schrei** beim Losrennen gehört dem Raid-Leeroy.
- Der Sieg-Monolog (Kap. 11) gehört ebenfalls dem Echo: es sieht seinen eigenen Körper endlich zur Ruhe kommen.
- Anzeige: Zeilen des Echos werden mit "Echo:" ausgezeichnet, der Schrei mit "Leeroy:".

### 10.2 Der Raid-Leeroy (Kampf)

**Vollwertiger KI-NPC mit eigenem Pathfinding** (Technik in Kap. 14): Try-Starter und Mitkämpfer. Er zieht jeden Try aufs Neue mit den Spielern zu Hogger — läuft los, stirbt, wird zum Geist, läuft zurück, belebt sich wieder, läuft wieder los. Für immer, bis der Fluch bricht. Er redet nicht; er schreit genau einmal pro Try.

1. **Erzähler (jetzt beim Echo, 10.1):** Quest und Zwischen-Zeilen.
2. **Try-Starter:** Jeder Try beginnt damit, dass Leeroy vom Friedhof seinen Pfad Richtung Hügel aufnimmt, dabei seinen ikonischen Schrei ausstößt — **"LEEEEEROY JEEENKINNNS"** (kartenweit hörbar, das akustische Startsignal) — und als Erster in Hogger chargt.
3. **Mitkämpfer (KI-Verhaltensmodell, host-seitig):**
   - **Try-Start-Bedingung:** Der allererste Anmarsch des Abends beginnt erst, wenn **der erste Spieler auf dem Realm die Quest des Echos angenommen hat** (Notbremse: `leeroy_first_march_wait`, 120 s). Losrennen, während das Echo noch redet, zerreißt die Szene (Playtest 2026-08-16). Für alle weiteren Trys gilt wieder die normale kurze Wartezeit am Friedhof.
   - Zustände: `WARTEN_FRIEDHOF` (zwischen Trys, bis Try-Start-Bedingung) → `ANMARSCH` (Pfad zum Hügel, Schrei beim Losrennen) → `KAMPF` (Krieger-Kit: hält Nahkampf, Heroischer Stoß bei Wut, Schlachtruf, wenn ≥ 3 Verbündete im Umkreis — sein einziger echter Gruppenbeitrag) → `TOT/GEIST` (Geisterlauf zum Wiederbelebungsfeld) → `WIEDERBELEBUNG` (immer als Mensch-Krieger, fluchbedingt) → `ANMARSCH` … im Loop bis Try-Ende.
   - Er weicht **nichts** aus: keine Charge-Reaktion, kein Fress-Fokus über das Normale hinaus — Leeroy ist tapfer, nicht klug. Sein Sterben als meist Erster ist der Running Gag und emergent aus dem Verhaltensmodell, nicht geskriptet.
   - Er zählt nie in die N-Skalierung, seine Bedrohung ist halbiert (Comedy, nicht Tank), seine DPS steckt im Sim-Modell (17.2).
   - **Anti-Stuck-Failsafe:** Bewegt er sich 5 s nicht messbar voran, wird er ein kurzes Stück entlang des Pfads versetzt und `leeroy_stuck` geloggt. Ein festgeklemmter Leeroy würde die gesamte Fiktion töten — der Failsafe ist Pflicht, nicht Polish.
4. **Announcer (ersetzt den gestrichenen Chat vollständig):** Alle ehemaligen Systemmeldungen sind Leeroy-Zeilen — als Sprechblase an seinem Icon plus kartenweite Einblendung am oberen Kreisrand:
   - Fress-Alarm: "ER FRISST SCHON WIEDER! MACHT WAS!"
   - HP-Meilensteine (75/50/25/10 %): eskalierende Euphorie.
   - Spielertode kommentiert er stichprobenartig (max. 1 Zeile / 10 s, Pool ~30 kontextsensitive Zeilen: Charge-Tod, Krit-Tod, Wolf-Tod, Heal-Aggro-Tod, Serientod "… zum 7. Mal.").
   - Try-Ende: Wipe-Ansage mit Try-Nummer.
   - Nach 3 Trys ohne einzige Fress-Unterbrechung platzt ihm der Kragen und er sagt die Mechanik einmal klar an ("IHR MÜSST IHN SCHLAGEN, WÄHREND ER FRISST!") — das Sicherheitsnetz für den Aha-Moment, diegetisch verpackt.
5. **Fluchbruch:** Stirbt Hogger, gehört Leeroy die Siegsequenz (Kap. 11).

Die Zeilen sind Text (Sprechblase + Einblendung), gesprochen vom Echo. Einzige Voice-Line ist der Schrei des Raid-Leeroy — Eigenproduktion (selbst einsprechen oder TTS/Suno), da er kartenweit und oft erklingt, muss er sitzen.

---

## 11. Tod, Statistik, Fluchbruch

- **Tod (v2.7, Playtest-Runde 1):** An der Sterbeposition bleibt ein Totenkopf-Icon als Leiche (Fress-Ressource) liegen; für andere kippt das eigene Klassenicon dorthin, man selbst sieht den eigenen Pfeil erblassen, der Totensicht-Filter legt sich über Bild und Audio. **Man ist noch kein Geist — man liegt da.** Oben mittig erscheint das Original-Panel (Referenz `geist freilassen.png`): Überschrift mit Countdown ("12 Sekunden bis zur Freigabe"), darunter der rote Knopf **"Geist freilassen"**. Der Knopf wird erst mit Ablauf des Respawn-Timers scharf — **die Wartezeit IST die Todesstrafe (Kap. 6) und ist nicht wegklickbar**; wer nicht drückt, wird nach einer Nachfrist (`release_grace`, 5 s) automatisch freigegeben. Erst mit der Freigabe steht der Geist am Friedhof — und erst dann setzt der Geister-Wind ein (Kap. 12 Nr. 3). **Killcam-Zeile** (2 s, sarkastischer RECOUNT-9000-Ton, Pool ~30, kontextsensitiv): "Todesursache: Optimismus." / "Der Priester hat dich geheilt. Deshalb bist du tot."
- **Sterbeposition ist eine Abwägung:** Im 200-px-Zugradius sterben = Futter; sich weit zurückziehen = sicher, aber doppelter Weg.
- **Krit-Inszenierung:** Krits beider Seiten mit großem gelbem Floating Text, Screenshake, Punch-Sound. Ein 60er-Hogger-Krit, der volle Platte oneshottet, ist ein Ereignis und wird als solches gefeiert.
- **Statistik-Tafel** (nach jedem Try-Ende und beim Sieg, WoW-Panel-Stil, ~10 s, wegklickbar), zweispaltig:
  - **Hogger:** Gesamtschaden · Spieler getötet · davon kritisch zerschmettert · Leichen gefressen · geheilte HP · Unterbrechungen kassiert · Charges · Rest-HP (bei Wipe groß: "Er hatte noch 4 %.").
  - **Schlachtzug:** Meister Schaden (Name + Wert) · Am häufigsten gestorben · Meiste Zeit als Geist · Am häufigsten gefressen worden · Heal-Aggro-Tode · Meiste Unterbrechungen · Meiste Mob-Kills · Reichster Spieler (Kupfer) · Erster Tod des Trys · Von einem Wildschwein getötet (Name) · Meiste Sprünge (Name + Zahl — "der Zappelphilipp") · ggf. Statistik-Titel ("der Gefressene", "die Geisterstimme", "der Unvorsichtige", "der Zweite").
- **Fluchbruch (Sieg):** Hoggers Icon zerspringt, Sieg-Fanfare. Loot-Fenster: "Thunderfury, Gesegnete Klinge des Windsuchers — Dropchance: 0,0000 %. Nicht gedroppt." plus "Zerfledderter Wams" (2 Kupfer, Zufalls-Roll — folgenloser RNG, erlaubt). Leeroy: letzte Zeilen, der Fluch bricht — **der Glitch läuft rückwärts**, die Minimap zerreißt, und für einen Moment erscheint der echte Login-Screen mit der Zeile "Du kannst dich jetzt ausloggen." Danach die finale Statistik-Tafel mit REVANCHE-Button (startet den nächsten Abend-Durchlauf, Try-Zähler bei 1 — der Fluch ist gebrochen, ab jetzt zergt man freiwillig).

---

## 12. Sound (so viel wie nötig, so wenig wie möglich)

Vollständige Liste — jede Position hat einen Zweck, nichts weiter aufnehmen:

| # | Sound | Zweck |
|---|---|---|
| 1 | Login-Musik-Anriss + Glitch-Static | Boot-Sequenz (Kap. 3) |
| 2 | Elwynn-Tag-Ambience (Loop) | Grundteppich lebend — der friedlich dudelnde Wald über 40 Sterbenden ist der Witz; reagiert nie auf den Kampf |
| 3 | Geister-Wind (Loop) + Audio-Tiefpassfilter | Totensicht-Zustand. Der Tiefpass liegt ab dem Tod über der Welt, **der Wind erst ab der Freigabe** (Kap. 11) — und er wird selbst nicht gedämpft, er ist ja die Welt des Geistes |
| 4 | Schritte auf Gras (1 Loop) | lebende Bewegung; Geister sind lautlos |
| 5 | Nahkampf-Hit (1×) | alle weißen Treffer + Heroischer Stoß/Finsterer Stoß |
| 6 | Zauber-Cast-Loop (1×) + 4 Impacts (Feuer, Schatten, Heilig, Frost-Buff) | alle Casts der drei Casterklassen + Paladin |
| 7 | Zauberstab-Schuss (1×), Bogen-/Gewehrschuss (1×) | OOM-Stochern, Jäger-Autoschuss |
| 8 | Schlachtruf (1×), Stealth-Ein/Aus (1×), Wichtel-Beschwörung (1×) | Klassen-Signaturen mit Spielinformation |
| 9 | Krit-Punch (1×) | beide Seiten |
| 10 | Hogger: Growl (Aggro), Schmatzen (kartenweit — IST die Fress-Telegraphie), Charge-Roar, Todesschrei | Boss-Lesbarkeit |
| 11 | Mob-Aggro: Wolfsknurren, Murloc-Schrei | Ambient-Gefahr; der Murloc-Schrei ist gesetzt |
| 12 | Spieler-Todeslaut (1×) | Tod-Feedback |
| 12b | Sprunglaut + Landung auf Gras (je 1×) | Leertaste-Feel (4.1) — der meistgehörte Sound des Abends |
| 13 | Levelup-DING | Easter-Egg (Kap. 7.3) |
| 14 | Loot-/Münzklimpern (1×), UI-Klick (1×) | Plunder-Feedback, Buttons |
| 15 | Sieg-Fanfare, Wipe-Sting (kurz, Moll — lachen, nicht trauern) | Try-Enden |
| 16 | Leeroy-Schrei (einzige Voice-Line) | Try-Start-Signal |

Beschaffung: Original-Dateien (IP egal) oder Eigenbau/Suno; Entscheidung pro Position in M4. Platzhalter bis dahin: generierte Sinus-Blips (Kap. 17.5).

---

## 13. Balancing & Falsifikation

### 13.1 Attrition-Erwartungsmodell (Hypothese v2.4 — durch M1 validiert und neu kalibriert; gültige Zahlen in 9.3 und im Tuning-Protokoll 17.9)

Mittlere DPS pro lebendem Spieler ≈ 3,5 (8-Klassen-Mix mit Jäger-Grundlast); mittlere Lebensdauer am Boss ≈ 10 s; Totzeit pro Zyklus 25–35 s → effektive Uptime ≈ 25–30 %. Beispiel N=10: ~3 aktive Spieler × 3,5 DPS ≈ 10,5 DPS netto → 1.200 HP ≈ 115 s reine Schadenszeit; mit 2–3 Fress-Heilungen und Anlaufphasen landet der Try im 8–12-Minuten-Fenster. Ob der HP-Koeffizient 120 hält, entscheidet die Sim (F5).

### 13.2 Krit-System

5 % Chance, fest ×2, beide Seiten, auch Heilungen. Ausgeschlossen: Charge, Slice, Fress-Heilung, DoT-Ticks. Alle Würfe nur auf dem Host, Seed pro Try geloggt.

### 13.3 Falsifikationskriterien (Headless-Sim, 1.000 Läufe pro Zelle)

| # | Hypothese | Falsifiziert wenn |
|---|---|---|
| F1 | Koordinierte Gruppen gewinnen zuverlässig | Siegquote < 60 % oder > 90 % bei irgendeinem N |
| F2 | Unkoordinierte verlieren meist | Siegquote unkoordiniert > 35 % |
| F3 | Fressen ist der Hebel | Unkoordinierte Siegquote bei N ≥ 10 ohne Fress-Unterbrechung > 10 % |
| F4 | Krits entscheiden nichts | Δ Siegquote (Krits an/aus) > 5 Prozentpunkte **im Mittel über alle Zellen** (Rob-Entscheid, Issue #6; Einzelzellen dürfen streuen, solange beide Krit-Welten im F1-Band bleiben) |
| F5 | Try-Länge trifft das Fenster | Median-Siegtry < 6 min oder > 13 min |
| F6 | Skalierung ist fair | Siegquoten-Spread zwischen N=5 und N=40 > 15 Prozentpunkte |

Stellhebel: F1/F5 → HP-Koeffizient und DPS-Zahlen; F2/F3 → Fress-Heilrate/Unterbrecher-Formel; F4 → Kritchance (nie den Multiplikator); F6 → Respawn-/Add-Formel. Jede Anpassung ins Tuning-Protokoll (17.9).

### 13.4 Playtest-Kriterien (Menschen, nur Gefühl — Übergabe nach 17.8)

- Erster Tod < 45 s nach Try-Start, und er ist komisch, nicht frustig.
- **Rahmen-Beat zündet:** Beobachtbares "Das ist die MINIMAP?!" in den ersten zwei Minuten neuer Spieler.
- Aha-Moment Fressen: unaufgefordert benannt innerhalb der ersten zwei Trys (Leeroys Kragen-Sicherheitsnetz greift erst ab Try 3).
- Revanche: Die Gruppe spielt freiwillig weiter — beim Wipe UND nach dem Fluchbruch.
- Klassen-Mikrorollen sichtbar (8.2), Quest-Onboarding < 60 s ohne Bedienungsfragen an den Raum.
- **Ablenkungs-Check:** Ab Try 2 im Schnitt < 10 % Lebenszeit mit Mob-Ziel (Event-Log, `target_switch`).
- **Zoom wird benutzt:** Spieler wechseln die Zoomstufe situativ (Log-Event `zoom_change`); falls alle dauerhaft auf einer Stufe kleben, ist die Mechanik toter Ballast → dann eine Stufe streichen statt weiter aufblasen.

---

## 14. Technik: Netcode & Architektur

Unverändert Volley-Dash-Muster: Host-autoritativ, lua-enet, Channel 0 reliable (Events), Channel 1 unreliable (Snapshots). Host-Sim 60 Hz, **Snapshots mit voller Tickrate (60 Hz) als Vollzustand** (ADR-001, Skill §3: der Snapshot ist für alle Clients identisch und wird einmal pro Tick gepackt; je Client nur ein kleiner Kopf mit `ackInputTick`). Client-Input 60 Hz als 1-Byte-Bitmaske mit ~3-Tick-Redundanz. **Keine Interpolation, keine zwei Zeitbasen:** Client-Darstellung per Rebase + Replay der eigenen Eingaben (Skill §3). Bandbreite N=40: ~50 Entitäten × 14 Bytes × 60 Hz ≈ 42 kB/s je Client, Host-Upstream ≈ 13,5 Mbit/s — im Kabel-LAN trivial; der erste reale Engpass wäre die Host-CPU (Sim/Kollision), nicht die Leitung. Revisionsauslöser und Eskalationsleiter in ADR-001 (`docs/adr/001-snapshot-strategie.md`). Icon-Rendering ist billiger als jedes Sprite-Spiel; das Performance-Risiko bleibt Host-seitig (Lua-GC, Kollision): Tabellen-Pooling, **Spieler-Phasing** (Spieler kollidieren nicht miteinander — WoW-authentisch; Kollision nur gegen Hogger/Adds/Wichtel/Geometrie auf Grid-Hash), kein Physik-Modul. Determinismus: alle Zufallswürfe host-seitig mit geloggtem Seed; keine Logik-Abhängigkeit von `pairs()`-Reihenfolge.

**Auto-Host-Discovery (Kap. 3):** UDP-Broadcast-Beacon mit Host-Startzeitstempel; Clients joinen den ältesten Beacon; Instanzen ohne gefundenen Beacon nach 3 s Suchzeit werden selbst Host. Gleichzeitstart-Kollision: jüngerer Host degradiert sich, seine Spieler reconnecten automatisch. Debug-Overlay (F12): manuelle IP, Host erzwingen, Lautstärke, Log-Pfad.

**NPC-Pathfinding (neu ab v2.1, wegen Leeroy als KI-Mitkämpfer):** Die Karte (Datendatei) enthält zusätzlich ein **Begehbarkeits-Grid** (Zellgröße 32 px; die Karte ist bei ~3×2 Bildschirmradien grob 100×70 Zellen — winzig). Pfadsuche per **A\*** auf diesem Grid, host-seitig, mit Pfadglättung (String-Pulling) und einfachem Steering für lokale Ausweichung um bewegliche Entitäten. A\* ist deterministisch (feste Nachbar-Reihenfolge, kein `pairs()`), damit die Determinismus-Teststufe hält. Nutzer des Systems: Leeroy (Anmarsch/Geisterlauf), Hoggers Leash-Rückweg, Mob-Leash — Spieler pathfinden nie (direkte Steuerung). Kosten: Bei einer Handvoll NPC-Pfadanfragen pro Sekunde auf 7.000 Zellen ist A\* im Mikrosekundenbereich — kein Performance-Thema, aber ein Korrektheits-Thema: Das Begehbarkeits-Grid wird aus derselben Kartendatei generiert wie die Kollisionsgeometrie (eine Quelle, kein Drift), und ein Unit-Test beweist, dass vom Friedhof aus jede relevante Position (Hügel, alle Mob-Spawns) erreichbar ist.

**Cross-Platform (Mac + Windows, Pflicht ab M2):** (1) Dateizugriff im Spiel ausschließlich `love.filesystem` (Logs, session.json, Presets im Save-Verzeichnis); CLI-Tools unter `sim/`/`tools/` nutzen Standard-Lua mit `/`-Pfaden. (2) Dateinamen strikt klein, keine Umlaute/Leerzeichen (macOS case-insensitiv, CI case-sensitiv). (3) Firewall-Hinweis im Boot ("Windows fragt gleich nach Freigabe → 'Privates Netzwerk' erlauben" — als Zeile im Ladescreen getarnt). (4) Eine `.love` als Wahrheit, CI packt `.exe` und `.app`. (5) `pairs()`-Regel, siehe oben — Test-Stufe 3 fängt Verstöße.

**Rejoin:** Client verbindet neu → Voll-Snapshot → spawnt als Geist, Charakter über Namen aus session.json. Host-Crash = Try verloren, Disconnect-Dialog (Kap. 3), keine Host-Migration (Overengineering für ein Privatprojekt).

---

## 15. Umfang, Assets, Meilensteine

**Assets (Icon-Look macht es radikal klein):** Alle Grafiken sind Icons im WoW-Stil — 8 Klassenicons (Original), 4 Rassen-Portraits für die Einheitenfenster (Mensch, Zwerg, Nachtelf, Gnom — je eins genügt), Geist-Varianten (Blaufilter per Shader, kein eigenes Asset), Hogger-Icon (größer) + Elite-Drachenrahmen, Leeroy-Marker, Geistheiler-Engel, 4 Mob-Icons, Totenkopf/Leiche, 8 begehbare Klassen-Bodenicons, 4 Buff-Icons (Original), ~18 Fähigkeiten-Buttons (Original-Spellicons), Loot-/Münz-Icons, Baum-/Fluss-/Hügel-Markierungen im Minimap-Kartenstil (Elwynn-Farbwelt: Grün, Wegbraun, Wasserblau). UI: Minimap-Ring, Ringknöpfe, Panel-Template (Statistik, Loot, Dialog, Disconnect), XP-Bogen, Zielrahmen, Werte-Buttons. Ein Icon-Raster (32/48 px) + ein Panel-Template decken alles. Sound: Liste Kap. 12.

**Meilensteine:**

| MS | Inhalt | Gate |
|---|---|---|
| **M1** | Headless-Balancing-Sim gemäß Kap. 17 (6-Klassen-Modell!) | F1–F6 bestanden, Todesstrafen-Wert fixiert |
| **M2** | **Balancing-MVP:** 5 Spieler LAN (Debug-Start ohne Boot/Intro), 3 Klassen (Krieger, Jäger, Priester), Hogger komplett inkl. Fressen/Charge/Zähler, Minimap-Grundpräsentation (Kreis, Zentrierung, Icons, Zoom, Floating Text), generierte Platzhalter-Icons (17.5), Tuning-Panel (17.6), Event-Logging, Test-Suite grün | Pyramide 1–4 bestanden UND echte 5er-Runde mit Revanche-Wunsch |
| **M3** | Alle 8 Klassen (inkl. Rassen-Auswürfelung), Leeroy-KI mit Pathfinding und Kampf-Loop, Adds, Mobs/XP/Plunder (inkl. Session-Persistenz), Klassenicon-Wiederbelebung, Leeroy als Try-Starter + Announcer, Auto-Host-Discovery, vollständiges Ring-UI (Uhr, XP-Bogen, Buffs, Zielrahmen), 40-Client-Stresstest | Host hält 60 Hz bei 40 Verbindungen |
| **M4** | Boot-Sequenz (wow.exe, Ladescreen, Glitch), Leeroy-Intro komplett, Killcam-Zeilen, Krit-Inszenierung, Statistik-Tafel, Fluchbruch-Sequenz, DING, Titel, Disconnect-Dialog, alle finalen Icons und Sounds inkl. Leeroy-Schrei | Playtest-Kriterien 13.4 auf der Ziel-LAN erfüllt |

**Bewusst gestrichen (Scope-Schutz):** Chat, großes Kartenfenster, Realmliste, Charaktererstellungsfenster, Cinematic, Text-Emotes, Talente, Items mit Wirkung, Horde, weitere Bosse, Zuschauermodus (Geister sind der Zuschauermodus), Berufe, Handel, Erfolge über den Abend hinaus.

---

## 16. Offene Designfragen (Playtest)

1. **Charge-Zielregel:** "Weitester mit Bedrohung" bestraft primär Jäger (200 px) und OOM-Stoff-Caster (120 px). Beobachten, ob das lacht oder frustet; Alternative (zufällig aus Top-3-Bedrohung) wäre ein weiterer RNG-Punkt und bleibt in der Hinterhand.
2. **Klassenkonvergenz:** Sim-Metrik Klassenverteilung der Siegläufe — kippt alles auf "alle Jäger", müssen die anderen Kits über Zahlen (nicht neue Fähigkeiten) attraktiver werden.
3. **Zoom-Stufen:** Drei Stufen Startwert; das `zoom_change`-Log entscheidet, ob es zwei oder vier werden.
4. **Leeroy-Frequenz:** Announcer-Dichte (max. 1 Zeile / 10 s Startwert) — nervt er ab Try 5? Drossel-Parameter liegt im Tuning-Panel.

---

## 17. Claude Code — Arbeits- und Messaufträge

**Zweck:** Alles, was gemessen, simuliert oder validiert wird, lebt ausschließlich hier. Design-Zahlen stehen oben; diese Sektion ist der ausführbare Auftrag daran. Künftige Messungen und Tuning-Ergebnisse werden hier angehängt.

### 17.0 GitHub-nativer Workflow (ab dem ersten Commit)

1. `main` geschützt und immer grün; jede Änderung als Branch → PR → CI grün → Merge. Claude Code arbeitet über `git` + `gh` (`gh pr create`, `gh run watch`, `gh pr checks`, `gh issue`) und merged nie auf Verdacht.
2. **CI (`.github/workflows/ci.yml`):** Pyramide-Stufen 1–3 auf Matrix `ubuntu-latest` / `windows-latest` / `macos-latest` (die Matrix IST der Cross-Platform-Beweis); Stufe 4 (fensterloses LÖVE2D, Loopback) auf ubuntu + macos; Stufe 5 nur lokal (CI-Runner sagen nichts über den LAN-Host).
3. **Releases:** Tag `v*` → Action baut `.love`, `.exe`, `.app` als Release-Artefakte; LAN-Verteilung = Release-Link.
4. **Issues als Arbeitsschlange** (Labels `balancing`, `gefühl`, `bug`, `modus2`); das Tuning-Protokoll (17.9) bleibt im GDD als Ergebnisgedächtnis.
5. **Validierungsberichte** als CI-Artefakte plus Kernzahlen als PR-Kommentar (`gh pr comment`).

### 17.1 Repo-Struktur

```
hogger/
├── .github/workflows/    # ci.yml, release.yml
├── .gitattributes        # LF erzwingen
├── sim/                  # Headless-Sim, reines Lua, kein LÖVE2D
│   ├── main.lua          # CLI: lua sim/main.lua --n 10 --runs 1000 --penalty 30 --crits on
│   ├── model.lua         # ALLE Formeln aus Kap. 8, 9, 13 — einzige Quelle, vom Spiel importiert
│   ├── agents.lua        # Agenten "koordiniert"/"unkoordiniert" (17.2)
│   └── report.lua        # Logs → Siegquoten, Try-Längen, Uptime, Klassenverteilung
├── game/                 # LÖVE2D, importiert sim/model.lua unverändert; Karten als Datendateien
├── tools/                # gen_placeholders.lua, check_assets.lua
├── tests/                # run_all.lua + Pyramide-Stufen
├── logs/                 # JSONL (gitignored)
├── presets/              # Tuning-Presets (JSON)
└── docs/                 # dieses GDD, docs/archiv/ mit v1.x, docs/referenzen/ (minimap.webp, totensicht.png, spieleranzeige_und_ziel.png)
```

### 17.2 M1: Headless-Sim

1. Ticks à 0,1 s; räumlich 1D-Distanz zum Boss (Reichweiten als Schwellen), kein Pathing.
2. **Agent "unkoordiniert":** läuft nach Respawn direkt zum Boss, hält Klassenreichweite, drückt Fähigkeiten bei Verfügbarkeit, ignoriert Fressen/Charge, wechselt nie die Klasse; Klassenwahl gleichverteilt über die **acht** Klassen.
3. **Agent "koordiniert":** zusätzlich Fress-Fokus (80 % Unterbrechungs-Erfolg je Kanal), Charge-Ausweichen 60 %, Konvergenz ab Minute 3 zu einer Zielkomposition (v2.6: 50 % Jäger, Heiler `max(2; N/8)`, Schurken `max(2; N/10)`, Rest gemischt — die absolute Startannahme „2 Heiler, 2 Schurken" ließ kleine Raids proportional mehr Support-Overhead tragen; die Sim darf weiterhin eine bessere Verteilung finden, `report.lua` weist die siegreichste aus).
4. **Agent "Turtle" (Anti-Stall-Beweis):** Heil-Maximierer — alle Heilerklassen, minimaler Schaden, nutzt die Fünf-Sekunden-Regel optimal. Muss in jeder Zelle > 95 % seiner Läufe per Zeitlimit verlieren; gewinnt oder überlebt er nennenswert, erzeugt die Mana-Regeneration ein Zermürbungs-Patt → Stellhebel: Vicious-Slice-Werte oder Regen-Rate, nie die Regel selbst streichen.
5. **Leeroy im Modell:** ein zusätzlicher Krieger-Agent, immer unkoordiniert, zählt nicht in N — er ist im Modell, weil er real DPS und eine Dauer-Leiche beisteuert.
5b. **Streuungsmodell (v2.6, Pflicht für alle Agenten):** Je Lauf erhält jeder Agent einen Skill-Faktor (gleichverteilt 0,7–1,3, wirkt multiplikativ auf verursachten Schaden) und die Gruppe einen gemeinsamen Koordinationsfaktor (gleichverteilt 0,75–1,25, multiplikativ obendrauf — die Koordinationsqualität schwankt real stark von Try zu Try; der breite Bereich macht die Siegquoten-Bänder zugleich robust gegen kleine Parameterverschiebungen, s. F4). Beide deterministisch aus dem geloggten Seed. Grund: Deterministisch-homogene Agenten erzeugen Stufenfunktions-Siegquoten — Bänder wie F1 (60–90 %) sind erst mit Streuung eine messbare Größe (M1-Befund, Issue #3). Die Faktoren sind Sim-Modellparameter in `model.lua` (Kapitel 17.2), kein Spielverhalten.
6. Matrix: 1.000 Läufe je Zelle über N ∈ {5, 10, 20, 40} × Todesstrafe ∈ {20, 25, 30, 35 s} × Krits ∈ {an, aus} × Agententyp.
7. F1–F6 (13.3) als automatisches Pass/Fail; Falsifikation → Stellhebel → Wiederholung → Eintrag in 17.9.
8. Zusatzmetriken: Median-Try-Länge, Uptime (Soll 25–30 %), Fress-Kanäle gesamt/unterbrochen, Klassenverteilung der Siegläufe (→ Frage 16.2).

### 17.3 Event-Log-Schema (JSONL, identisch Sim und Live, Pflicht ab M2)

`{"t": <tick>, "ev": "<typ>", "src": "<id>", "dst": "<id|null>", "val": <zahl|null>, "crit": <bool|null>[, "art": "<schadensart>"]}`

`art` steht bei `damage`-Ereignissen und nennt die Schadensart: `autohit`, `ability`, `dot`, `charge`, `slice`, `mob`, `add`. Sie steuert Darstellung (Geschoss/Schlagbogen, 4.1) und Trefferklang (Kap. 12) und macht beides von geratenen Schadenshöhen unabhängig. Im Netz kostet sie nichts: sie teilt sich das Flag-Byte mit dem Krit-Bit.

Typen (abschließend v2.0): `try_start` (val = N, dst = Try-Nr.), `spawn`, `revive` (dst = Klasse, val = Rassen-ID), `death` (ab M4: val = Todesursachen-ID aus `game/gamesim/killcam.lua` — Autohit/Charge/Slice/Blutung/Mob-Typ/Welpe —, crit = tödlicher Krit; speist Killcam und Statistik-Tafel), `damage`, `heal`, `crit_kill`, `eat_start`, `eat_drag`, `eat_tick`, `eat_interrupt` (val = Beteiligte), `eat_complete`, `charge`, `class_change`, `add_death`, `mob_kill` (dst = Typ), `mob_death_by`, `xp_gain`, `loot_pickup` (val = Kupfer), `ding`, `target_switch`, `zoom_change` (val = Stufe), `leeroy_line` (dst = Zeilen-ID — misst Announcer-Dichte), `leeroy_stuck` (Failsafe ausgelöst — jedes Vorkommen ist ein Pathfinding-Bug-Report), `param_change`, `quest_offer` (src = echo, dst = Spieler-ID: das Echo hat die Quest aufgedrückt), `quest_accept` (src = Spieler-ID: angenommen — die erste Annahme startet den Raid-Leeroy), `try_end` (val = 1 Sieg / 0 Wipe, dst = Boss-Rest-HP). Jeder `try_start` loggt zusätzlich den kompletten Parametersatz. Sprünge werden NICHT einzeln geloggt (zu spammig bei 40 Dauerhüpfern), sondern host-seitig pro Spieler gezählt und in `try_end` als Zählerliste mitgeschrieben. Neue Typen nur per GDD-Update hier.

`session.json` (Host, `love.filesystem`): XP/Kupfer je Charaktername, Try-Zähler, Titel. Einzige rundenübergreifende Persistenz; "Neuer Abend" löscht sie (Debug-Overlay).

### 17.4 M3: Stresstest

Headless-Client-Harness (enet-Bots), 40 Verbindungen, 10-min-Lauf, Zufallsbewegung + Fähigkeits-Spam. Gates: Host-Tickdauer p95 < 16,6 ms, GC-Pausen, Upstream. Ergebnis entscheidet über Delta-Kompression. Messwerte → 17.9.

### 17.5 Asset-Kontrakt: Platzhalter → Final ohne Codeänderung

1. Kein Dateipfad im Spielcode — nur logische IDs aus `assets/manifest.lua` (`id → {datei, größe, anker, frames}`).
2. Maß-Kontrakt (v2.7, nach den ersten Finaldateien am 2026-08-16): Platzhalter werden exakt in Manifest-Maßen erzeugt. **Finale Icon-PNGs dürfen größer sein, müssen aber quadratisch sein** — sie werden beim Zeichnen auf die Manifest-Maße normalisiert (`game/assets.lua`), damit hochauflösende Exporte scharf bleiben und trotzdem nirgends eine Bildgröße im Spielcode steht. Bildschirmfüllende Flächen (Splash) tragen `masse = "mindestens"` und werden **vollständig** gezeigt (contain, schwarzer Rand) — beschneiden würde beim 4:3-Original oben und unten Bildteile kosten (Playtest 2026-08-16). Ein nicht quadratischer Export (Icon mit Rand auf breiter Leinwand) ist ein Fehler und wird vom Validator gemeldet — Inhalt quadratisch zuschneiden.
3. `tools/gen_placeholders.lua` **generiert** alle Platzhalter aus dem Manifest: einfarbige Kreise/Formen in Klassenfarbe mit Kürzel-Beschriftung, exakt finale Maße — im Icon-Look ist der Platzhalter dem Final so nah, dass M2/M3 damit voll spielbar sind.
4. Audio analog: Sound-IDs, Platzhalter = generierte Sinus-Blips; `music`/`ambience`-Slots spielen Stille bis eine Datei liegt.
5. `tools/check_assets.lua` validiert jede echte Datei gegen den Kontrakt und läuft in der Test-Suite — ein falsch geliefertes Final-Asset fällt im Test auf, nicht auf der LAN. Er erkennt auch die Windows-Falle **doppelte Dateiendung** (`icon_warrior.png.png`, entsteht beim Speichern mit ausgeblendeten Endungen) und sagt den korrekten Namen an.

### 17.6 Live-Tuning-Panel (ab M2, Host-only, F10)

Alle Parameter als **eine flache Tabelle** in `model.lua` (`M.params`, je `{wert, min, max, schritt, kapitel}`); das Panel generiert sich vollständig daraus — keine Variable wird je von Hand ins UI gebaut. Änderungen wirken live, broadcasten an Clients, loggen als `param_change`.

| Gruppe | Parameter |
|---|---|
| Hogger | HP-Steigung und HP-Sockel (HP = Steigung × N − Sockel), Autohit-Schaden/-Intervall, Cleave-Divisor, Tempo, Slice-Werte, Charge-CD/-Schaden/-Anlauf, Leash |
| Fressen | Heilrate, Kanaldauer, CD, Zugradius, Zugdauer, Unterbrecher-Offset, Schadensschwelle (% Max-HP) |
| Krits | Chance und Multiplikator, je Seite getrennt schaltbar (A/B-Gefühlstests) |
| Spieler | HP je Rüstungsklasse, alle Fähigkeitswerte, Autohit/Zauberstab, Reichweiten, GCD, Tempo lebend/Geist, Fünf-Sekunden-Regel (Wartezeit, Regen-Rate), Bedrohung je Heilung |
| Loop | Respawn-Formel (Basis, Faktor, Min, Max), Try-Zeitlimit, Wiederbelebungsfeld-Position (Distanz zum Hügel) |
| Mobs | Slot-Formel, Respawn, HP/Schaden je Typ, XP, Kupfer |
| Adds | Anzahl-Formel, HP, Schaden |
| Leeroy | Announcer-Drossel (Zeilen/10 s), Bedrohungsfaktor, Kragen-Schwelle (Trys bis Mechanik-Ansage) |
| UI | Zoom-Stufen (Radien), Floating-Text-Dauer |

Presets speichern/laden (JSON), "Zurück auf GDD-Werte".

### 17.7 Autonome Test-Pyramide (ein Befehl, grün/rot)

`lua tests/run_all.lua` (Stufe 4: `love . --headless --test`). Spiellogik lebt engine-unabhängig in `model.lua` — LÖVE2D ist nur Renderer und Transport.

| Stufe | Was | Prüft | Läuft |
|---|---|---|---|
| 1 — Unit | Lua-Asserts auf `model.lua` | Formeln gegen GDD-Tabellen (9.3 als harte Testfälle), Krit-Ausschlüsse, Threat-Löschung bei Tod, XP-Deckel pro Try < 400, 8-Klassen-Vollständigkeit inkl. gültiger Rassen-Kombinationen, Erreichbarkeits-Beweis auf dem Begehbarkeits-Grid (Friedhof → Wiederbelebungsfeld → Hügel → alle Mob-Spawns), Manifest-Validator | < 1 s, jeder Commit |
| 2 — Sim | 17.2 komplett | F1–F6 Pass/Fail, Uptime-Korridor, Klassenverteilung | Minuten, bei Balancing-PRs |
| 3 — Determinismus | Zwei Sim-Läufe, gleicher Seed | Identischer Log-Hash — findet versteckten Zufall und `pairs()`-Sünden vor jedem Netcode | Sekunden, jeder Commit |
| 4 — Integration | Host + N Bot-Clients in-process (Loopback, `t.window = false`) | Voller Try inkl. Try-Übergang; Invarianten je Tick: keine negativen HP, kein Heilen über Max, kein Ziel gleichzeitig tot und am Boss, Snapshot-Budget, Rejoin mitten im Try, session.json konsistent nach Host-Neustart, Quest-Onboarding blockiert Bewegung korrekt (Annahme über das Netz), Leeroy vollendet seinen Loop (Anmarsch → Hogger → Tod → Geisterlauf zum Wiederbelebungsfeld → Wiederbelebung → Anmarsch) ohne `leeroy_stuck`-Event | ~1 min, vor Merge |
| 5 — Stress | 17.4 | Perf-Gates | auf Abruf, vor M3-Abschluss |

Jeder volle Lauf erzeugt `reports/<datum>.md` (Metriken, Siegquoten-Matrix, Delta zum Vorlauf); Kernzahlen → PR-Kommentar und 17.9.

### 17.8 Human-in-the-Loop (nur Gefühl)

Menschen erst bei grüner Pyramide. Übergabe: Validierungsbericht + eine Ein-Satz-Gefühlsfrage pro offenem Punkt ("Sim: Charge trifft alle 19 s — Bedrohung oder Lärm?"). Der Playtest prüft NUR 13.4; Zahlen fallen als Log nebenbei an und werden automatisch gegen die Sim gehalten (Uptime-Abgleich). Befunde → Issues (`gefühl`) → autonome Umsetzung → Pyramide erneut grün. Der Loop: **Claude Code tuned und beweist → Mensch fühlt → Claude Code tuned und beweist.** Menschliche Zeit fließt nur in die Frage, die zählt: Lacht der Raum?

### 17.9 Tuning-Protokoll (fortlaufend, hier anhängen)

| Datum | Änderung | Auslöser (F-Kriterium/Playtest) | Ergebnis |
|---|---|---|---|
| 2026-08-16 | M1-Basis-Sweep, 96 Zellen × 1000 Läufe, GDD-Werte unverändert | Erstvalidierung (17.2) | F1/F2/F5 verletzt (alle N ~100 % Siege; N=40 Median 1,2 min), F3 nur leer bestanden, Turtle-Gate bestanden. Strukturursache: Hoggers Tötungsrate skaliert nicht mit N → Issue #3, #4. Bericht: `reports/2026-08-16-m1-validierung.md` |
| 2026-08-16 | HP-Koeffizient-Sweep 200–240 bei N=5 (nicht angewendet, Wert bleibt 120) | F1/F5 | Bei HP 220 erfüllt N=5 F1 (80 %), F5 (12,7 min), F2 (unkoordiniert 0 %); F4 an der Kante verletzt (Δ 9,7 pp). Anwendung erst nach Skalierungsentscheidung (#3) |
| 2026-08-16 | Todesstrafe vorläufig auf 30 s fixiert (Respawn + Geisterlauf ~12 s + Anmarsch ~10 s) | M1-Gate | Straf-Dimension wirkt monoton, aber schwach gegenüber dem HP-Hebel; endgültige Fixierung nach #3 |
| 2026-08-16 | v2.6-Mechanik (Cleave, Fress-Schwellen, Streuung) + Todesstrafen-Korrektur: Sim modelliert Respawn(N)+Laufweg statt flacher Strafe | Rob-Entscheid zu #3/#4 | Uptime-Spreizung 17–42 % → 25–35 %; Try-Längen-Verhältnis N=5:N=40 von 2,8 auf 1,4 |
| 2026-08-16 | HP-Formel affin: 120×N → 430×N−950 (Sockel = Kleingruppen-Overhead) | F1/F5: Siegquoten-Bänder je N kollabieren im Sweep exakt auf diese Gerade | F1 erstmals bei allen N im Band (72,6/65,4/80,6/85,4 %) |
| 2026-08-16 | Respawn-Formel 8+0,3N→8+0,52N (Max 20→30); Charge-CD 15→10 s; Cleave-Divisor 8→5; Laufweg 14 s | F6 (Spread 20 pp) + F1-Feinlage | Zusammen mit breiter Gruppenstreuung: Spread 5,5 pp |
| 2026-08-16 | Sim-Gruppenfaktor 0,85–1,15 → 0,75–1,25 (17.2) | F4 (Krit-Delta 6–11 pp: zu schmale Ergebnisverteilung macht Ausgang krit-sensitiv) | F4-Deltas 4,3/1,0/4,5/3,7 pp — 5-%-Krit bleibt unangetastet |
| 2026-08-16 | Koordinierte Zielkomposition: Heiler/Schurken absolut „2/2" → max(2; N/8)/max(2; N/10) | F6-Analyse (Support-Overhead-Schieflage kleiner Raids) | Effekt neutral (Heil-Nutzen ≈ DPS-Verlust); als realistischeres Modell beibehalten |
| 2026-08-16 | **Endstand-Verifikation** (600 Läufe/Zelle): koordiniert 72,8/68,7/74,2/74,2 %, Median-Siegtry 9,7–12,1 min, F4 ≤4,5 pp, F6-Spread 5,5 pp, unkoordiniert 0–1,3 %, Turtle 0 % Siege | M1-Gate | **F1–F6 + Turtle-Gate bestanden**; finale 1000er-Matrix: `reports/2026-08-16-m1-final.md` |
| 2026-08-16 | Frontbogen-Regel eingefuehrt (`facing_arc_deg` = 180°): Angriff nur auf Ziele vor einem, Wegdrehen bricht Casts ab | Playtest (Rob, Issue #32): „wenn ich mich wegdrehe, sollten Attacken nicht durchgehen" | Uptime-relevant nur bei Fehlbedienung; die Balancing-Sim (17.2) modelliert keine Blickrichtung und bleibt gueltig (ihre Agenten sehen ihr Ziel per Definition an). Bots und Leeroy drehen sich jetzt zu ihrem Ziel |
| 2026-08-16 | **M3-Stresstest (17.4):** 40 echte ENet-Clients, 10 min, Zufallsbewegung + Fähigkeits-Spam; ENet-Peer-Limit 32 → 48 | M3-Gate | **BESTANDEN:** 40/40 verbunden, Host-Tick Mittel 0,44 ms · p95 0,60 ms · p99 0,77 ms · max 11,9 ms (Gate 16,6 ms), Upstream 20,7 Mbit/s, Lua-Heap stabil ~12 MB. **Delta-Kompression nicht nötig** (ADR-001-Revisionsauslöser geprüft, nicht ausgelöst) |

---

## 18. Backlog: Modus 2 — Kriegshymnenschlucht (10v10 Capture the Flag)

**Status: GESPERRT** bis der Hogger-Modus M4 bestanden hat und auf einer echten LAN abgenommen wurde (13.4 erfüllt, Revanche nachgewiesen). Bis dahin: Issues mit Label `modus2` sammeln, nichts umsetzen.

**Skizze:** Level-1-PvP nach Kriegshymnenschlucht-Vorbild im selben Minimap-Look — zwei Teams à max. 10, Flagge holen, zur eigenen (nur wenn daheim) tragen, 3 Wertungen = Sieg, Zeitlimit als Fallback. Identische Menschenklassen-Kits beide Seiten (Team Blau/Rot; Fiktion — zweiter Fluch? Spiegel-Leeroy? — wird erst bei Freischaltung entschieden). Kurze Respawn-Wellen am eigenen Friedhof.

**Übernommen wird 1:1:** Netcode/Host-Modell (20 Clients ≪ 40er-Stresstest), `model.lua` + Tuning-Panel, Klassenkits, Killcam, Icon-/Asset-Kontrakt, Test-Pyramide, Log-Schema (+ Flag-Events), Auto-Discovery (Modusauswahl im Debug-Overlay oder per Host-Vote — offen).

**Bekannte Risiken (erst bei Freischaltung lösen):** 2–3-Hit-TTK macht PvP burstig → eigenes Parameter-Preset (Panel kann das schon); Verstohlenheit + Flagge = Degenerationsstrategie → Original-Lösung übernehmen (Flagge tragen bricht Stealth); Heiler-Stacking ohne Manaregeneration → die Kein-Regen-Regel ist im PvP womöglich das Feature, das Runden beendet.

**Vorhalte-Entscheidungen, die JETZT im Hogger-Modus umgesetzt sind (je < 1 h):** (1) `team`-Feld im Spielerstatus (konstant "raid"), (2) `mode`-Feld in `try_start`, (3) Karten als Datendateien, (4) Feindlichkeitsrelation vom Boss-Begriff getrennt. Mehr nicht — jede weitere Vorarbeit wäre Spekulation auf einen Modus, dessen Berechtigung erst der Hogger-Erfolg beweist.
