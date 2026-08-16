# CLAUDE.md — Hogger muss sterben

LÖVE2D-LAN-Koop-Zerg für 5–40 Spieler. Privates Spaßprojekt, LAN-Party-Zielbetrieb, Mac + Windows.

## Wahrheitsquellen (in dieser Reihenfolge)

1. **`docs/gdd.md`** (v2.5) — das Game Design Document ist die einzige Design-Wahrheit. Alle Zahlen, Formeln, Mechaniken, Meilensteine und Testkriterien stehen dort. Bei Widerspruch zwischen Code und GDD gewinnt das GDD; bei Unklarheit im GDD: Issue mit Label `frage` anlegen und Rob fragen, nicht raten.
2. **`docs/skills/love2d-lan-game.md`** — destillierte Learnings aus einem real durchgezogenen LÖVE2D-LAN-Projekt. **Pflichtlektüre VOR der ersten Architekturentscheidung und vor der ersten Zeile Netzcode.** Die [gemessen]-Punkte darin sind teuer bezahlte Fallen — nicht neu verhandeln.
3. Diese Datei — Arbeitsweise und Betriebsregeln.

Wo GDD und Skill kollidieren (z. B. Snapshot-Strategie: GDD sagt 20 Hz + Interpolation, Skill sagt „volle 60 Hz bei kleinem Zustand" mit Eskalationsleiter §3.1 für größere Welten wie unsere ~50 Entitäten): Entscheidung als ADR dokumentieren (siehe unten) und im GDD Kap. 14 nachziehen — per PR, nicht still.

## Arbeitsweise

- **GitHub-nativ:** `main` ist geschützt und immer grün. Feature-Branch → PR (`gh pr create`) → CI grün (`gh pr checks`) → Merge. Nie auf Verdacht mergen. Issues (`gh issue`) sind die Arbeitsschlange: Labels `balancing`, `gefühl`, `bug`, `frage`, `modus2`.
- **Spec vor Code, ADRs vor Implementierung:** Architekturentscheidungen als `docs/adr/NNN-titel.md` mit Kontext, verworfenen Alternativen und **Revisionsauslöser** („woran erkennt man, dass die Entscheidung neu bewertet gehört").
- **Test-first entlang der Pyramide** (GDD Kap. 17.7): Stufe 1 (Unit, reines Lua) und Stufe 3 (Determinismus, gleicher Seed → gleicher Log-Hash) laufen bei jedem Commit. `lua tests/run_all.lua` ist der eine Befehl. Kein Feature ohne Test seiner Formeln.
- **Autonom testen, Mensch nur fürs Gefühl:** Alles Messbare prüfst du selbst (Sim, Invarianten, Stresstest, Berichte). Rob wird nur für die Gefühls-Kriterien aus GDD 13.4 gerufen — mit fertigem Validierungsbericht und je einer Ein-Satz-Frage pro offenem Punkt.
- **Eine Wahrheit pro Frage:** `sim/model.lua` ist die EINZIGE Quelle aller Spielzahlen und Formeln; Sim und Spiel importieren dieselbe Datei. Ein Hash, ein Ableitungspfad, eine Physik.
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

- **M0 (zuerst):** Repo initialisieren, CI-Workflow lauffähig machen (`.github/workflows/ci.yml` ist ein Skelett — zum Laufen bringen, ggf. Lua-Setup-Action tauschen; Matrix ubuntu/windows/macos für Stufen 1+3 ist Pflicht), `model.lua` mit vollständiger Parametertabelle aus dem GDD befüllen, Unit-Tests der GDD-Tabellen (9.3 als harte Testfälle) grün.
- **M1:** Headless-Sim komplett (GDD 17.2, inkl. Agenten „koordiniert", „unkoordiniert", „Turtle" und Leeroy-Modell), F1–F6 als Pass/Fail, Parameter-Sweep, Validierungsbericht nach `reports/`. **Gate: alle F-Kriterien bestanden, Todesstrafen-Wert fixiert.** Falsifikationen selbstständig per Stellhebel (GDD 13.3) beheben und protokollieren.
- **M2 (Balancing-MVP):** GDD Kap. 15, Zeile M2. Erst danach Rob für den ersten 5er-LAN-Test rufen.
- **M3, M4:** wie GDD. Modus 2 (Kap. 18) ist GESPERRT — nur `modus2`-Issues sammeln.

## Was du NICHT allein entscheidest

- Änderungen an Design-Absichten, Fiktion, Comedy-Inhalten oder Klassenkits (Vanilla-Authentizität ist gesetzt) → Vorschlag als Issue/PR-Beschreibung, Rob entscheidet.
- Alles, was Geld kostet oder externe Accounts braucht.
- Gefühls-Fragen (GDD 13.4) — die beantwortet nur der Playtest.

## Umgebung & Befehle

- Sprache: Deutsch für Docs, Commits, Issues, Berichte. Code-Bezeichner Englisch, kurz.
- Test alles: `lua tests/run_all.lua` (Stufe 4 separat: `love . --headless --test` aus `game/`).
- Sim: `lua sim/main.lua --n 10 --runs 1000 --penalty 30 --crits on`
- LÖVE-Version: 11.5 pinnen (`conf.lua`), ungenutzte Module abschalten.
- Logs/`session.json`: JSONL-Schema exakt nach GDD 17.3; neue Event-Typen nur per GDD-Update.
