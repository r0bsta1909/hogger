# CLAUDE.md — Hogger muss sterben

LÖVE2D-LAN-Koop-Zerg für 5–40 Spieler. Privates Spaßprojekt, LAN-Party-Zielbetrieb, Mac + Windows.

## Wahrheitsquellen (in dieser Reihenfolge)

1. **`docs/gdd.md`** (v2.6) — das Game Design Document ist die einzige Design-Wahrheit. Alle Zahlen, Formeln, Mechaniken, Meilensteine und Testkriterien stehen dort. Bei Widerspruch zwischen Code und GDD gewinnt das GDD; bei Unklarheit im GDD: Issue mit Label `frage` anlegen und Rob fragen, nicht raten.
2. **`docs/skills/love2d-lan-game.md`** — destillierte Learnings aus einem real durchgezogenen LÖVE2D-LAN-Projekt. **Pflichtlektüre VOR der ersten Architekturentscheidung und vor der ersten Zeile Netzcode.** Die [gemessen]-Punkte darin sind teuer bezahlte Fallen — nicht neu verhandeln.
3. Diese Datei — Arbeitsweise und Betriebsregeln.

Wo GDD und Skill kollidieren (z. B. Snapshot-Strategie: GDD sagt 20 Hz + Interpolation, Skill sagt „volle 60 Hz bei kleinem Zustand" mit Eskalationsleiter §3.1 für größere Welten wie unsere ~50 Entitäten): Entscheidung als ADR dokumentieren (siehe unten) und im GDD Kap. 14 nachziehen — per PR, nicht still.

## Arbeitsweise

- **GitHub-nativ:** `main` ist geschützt und immer grün. Feature-Branch → PR (`gh pr create`) → CI grün (`gh pr checks`) → Merge. Nie auf Verdacht mergen. Issues (`gh issue`) sind die Arbeitsschlange: Labels `balancing`, `gefühl`, `bug`, `frage`, `modus2`.
- **Spec vor Code, ADRs vor Implementierung:** Architekturentscheidungen als `docs/adr/NNN-titel.md` mit Kontext, verworfenen Alternativen und **Revisionsauslöser** („woran erkennt man, dass die Entscheidung neu bewertet gehört").
- **Test-first entlang der Pyramide** (GDD Kap. 17.7): Stufe 1 (Unit, reines Lua) und Stufe 3 (Determinismus, gleicher Seed → gleicher Log-Hash) laufen bei jedem Commit. `lua tests/run_all.lua` ist der eine Befehl. Kein Feature ohne Test seiner Formeln.
- **Autonom testen, Mensch nur fürs Gefühl:** Alles Messbare prüfst du selbst (Sim, Invarianten, Stresstest, Berichte). Rob wird nur für die Gefühls-Kriterien aus GDD 13.4 gerufen — mit fertigem Validierungsbericht und je einer Ein-Satz-Frage pro offenem Punkt.
- **Keine Stundenläufe (ADR 004/006, Rob-Entscheide Runde 14 und 20):** Der Balancing-Nachweis ist der **Richtungstest** `lua sim/main.lua --quick --jobs 10` — die echte Spielsimulation mit den Bots als typischem Raid, 16 Zellen, alle acht Kriterien (F1–F7 + Turtle), 50 Läufe je Zelle, ~7 Minuten, ±14 pp je Quote. `--runs 100` (±10 pp, ~14 min) nur auf ausdrückliche Ansage. **Rechenläufe über ~10 Minuten startest du nicht ungefragt.** Jede Siegquote wird mit ihrem 95-%-Vertrauensbereich berichtet — Unterschiede darunter sind Rauschen, keine Ergebnisse; ein Rasterpunkt mit 20 Läufen (±18 pp) zeigt nur die Richtung. Robs Seite des Balancings steht in `docs/balancing-fuer-rob.md` (Symptom → Regler → Nebenwirkung); einen gespielten Abend rechnet `lua tools/log_lesen.lua <session-*.jsonl>` nach.
- **Eine Wahrheit pro Frage:** `sim/model.lua` ist die EINZIGE Quelle aller Spielzahlen und Formeln. Seit Runde 20 (ADR 006) gibt es auch nur **eine Simulation**: die Balancing-Sim treibt `game/gamesim` selbst (`sim/gamerun.lua`), gespielt von den Bots in `game/gamesim/bot.lua` — dieselben, die als Debug-Bots im Spiel laufen. Die Bots sind der Referenz-Raid; eine Sim, deren Agenten besser spielen als die Bots, misst ein anderes Spiel. Ein Hash, ein Ableitungspfad, eine Physik.
- **Tuning-Protokoll:** Jede Balancing-Änderung mit Auslöser und Ergebnis in GDD Kap. 17.9 anhängen (per PR am GDD).

## Harte Coding-Regeln (aus GDD Kap. 14 + Skill)

- Simulation ist **love-frei** (`sim/` läuft mit purem Lua/LuaJIT): kein `love.*`, kein `os.time`, kein ungeseedetes `math.random`, keine Iteration über nicht-numerische Schlüssel, wenn die Reihenfolge das Ergebnis beeinflusst. Ein Test mit vergiftetem `love`-Global beweist das maschinell.
- Fixer Simulationsschritt (1/60 s) mit Akkumulator (gedeckelt), Rendering interpoliert. `dt` aus `love.update` erreicht die Physik nie.
- Input als 1-Byte-Bitmaske pro Tick, eine Quelle pro Spieler (Tastatur, Bot, Netz, Replay austauschbar). Reservierte Bits müssen 0 sein und werden verworfen, nicht maskiert.
- Logische Weltgröße ist eine Konstante; Fensteranpassung nur als Render-Transformation.
- Zufall: NUR der 5-%-Krit und der Loot-Roll, NUR auf dem Host, Seed pro Try geloggt. Sonst nichts.
- Dateizugriff im Spiel nur `love.filesystem`; Dateinamen strikt klein, keine Umlaute/Leerzeichen; `.gitattributes` erzwingt LF.
- Alle Grafik/Sounds über logische IDs aus `assets/manifest.lua` (GDD 17.5) — nie Pfade im Spielcode. Platzhalter werden generiert (`tools/gen_placeholders.lua`), nie von Hand gemalt.
- Alle Balancing-Werte in `model.lua` als `M.params` mit `{wert, min, max, schritt, kapitel}` — das F10-Tuning-Panel generiert sich daraus (GDD 17.6).

## Meilensteine & Definition of Done

Reihenfolge und Gates stehen in GDD Kap. 15. Kurzform:

- **M0 (erledigt):** Repo initialisiert, CI lauffähig, `model.lua` mit vollständiger Parametertabelle befüllt, Unit-Tests der GDD-Tabellen (9.3) grün. **CI-Stand seit ADR 003:** `ci.yml` ist ein einzelner Ubuntu-Job (Stufen 1, 3, 4 — das schnelle Gate), die Plattform-Matrix Windows/macOS liegt in `ci-plattform.yml` und läuft an jedem PR, bei Push auf `main`, wöchentlich und auf Zuruf. `main` ist per Branch-Schutz gesichert (Pflicht-Checks `test` und `plattform-gruen`, null Reviews). Beim Ändern der Matrix das Sammel-Gate `plattform-gruen` beibehalten — es ist der Name, an dem die Schutzregel hängt.
- **M1:** Headless-Sim komplett (GDD 17.2, inkl. Agenten „koordiniert", „unkoordiniert", „Turtle" und Leeroy-Modell), F1–F6 als Pass/Fail, Parameter-Sweep, Validierungsbericht nach `reports/`. **Gate: alle F-Kriterien bestanden, Todesstrafen-Wert fixiert.** Falsifikationen selbstständig per Stellhebel (GDD 13.3) beheben und protokollieren.
- **M2 (Balancing-MVP):** GDD Kap. 15, Zeile M2. Erst danach Rob für den ersten 5er-LAN-Test rufen.
- **M3, M4:** wie GDD. Modus 2 (Kap. 18) ist GESPERRT — nur `modus2`-Issues sammeln.

## Was du NICHT allein entscheidest

- Änderungen an Design-Absichten, Fiktion, Comedy-Inhalten oder Klassenkits (Vanilla-Authentizität ist gesetzt) → Vorschlag als Issue/PR-Beschreibung, Rob entscheidet.
- Alles, was Geld kostet oder externe Accounts braucht.
- Gefühls-Fragen (GDD 13.4) — die beantwortet nur der Playtest.

## Umgebung & Befehle

- Sprache: Deutsch für Docs, Commits, Issues, Berichte. Code-Bezeichner Englisch, kurz.
- Test alles: `lua tests/run_all.lua` · Stufe 4 (headless): `lovec game --headless --test` · **Stufe 4b (Zeichentest): `lovec game --drawtest`** — führt den Renderer für jede Klasse und jeden Zustand wirklich aus und ist der EINZIGE Test, der Fehler im Zeichencode findet (Stufe 1/3 sind love-frei, Stufe 4 läuft ohne Grafikmodul). Ergebnis steht auch in `drawtest.txt` im Speicherordner. **Nach jeder Änderung an `render.lua` Pflicht.**
- Sim — Rauchtest: `lua sim/main.lua --smoke` (N=10 typisch, 20 Läufe, ~30 s) · Einzelzelle: `lua sim/main.lua --n 10 --runs 100 --agent typisch` · Rasterpunkt für die Kalibrierung: `--quick --only typisch --crits-only --runs 20 --jobs 4 --set k=v` (~2 min, nur Richtung) · Rasterpunkt „typisch ohne Fähigkeit X": dasselbe mit `--skip kick|loh|shout|…` (Schlüssel in `bot.SKIP_KEYS`; misst, was eine Entscheidung am Ausgang ändert — Runde 21). Nachweis-Gate: `lua sim/main.lua --quick --jobs 10` (~7 min). Vollmatrix nur auf Ansage: `--sweep --runs 100 --jobs 10 --out reports/<datum>-sweep.md`.
- Abend nachrechnen: `lua tools/log_lesen.lua <pfad>`. **Zwei Speicherorte:** gepacktes Spiel (`wow.exe`) -> `%APPDATA%\hogger\logs\`, aus dem Repo (`love game`) -> `%APPDATA%\LOVE\hogger\logs\`. LÖVE trennt fusionierte Spiele von der Entwicklungsversion — Robs Logs liegen im ERSTEN Pfad.
- LÖVE-Version: 11.5 pinnen (`conf.lua`), ungenutzte Module abschalten.
- Logs/`session.json`: JSONL-Schema exakt nach GDD 17.3; neue Event-Typen nur per GDD-Update.
