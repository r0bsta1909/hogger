# ADR 004: Balancing-Nachweis — Richtungstest statt Vollmatrix

**Status:** akzeptiert (Rob, 20.08.2026, Issue #175)

## Kontext

Der Nachweis, dass eine Änderung die Falsifikationskriterien F1–F6 und das Turtle-Gate nicht kippt, lief bisher als volle Matrix: `lua sim/main.lua --sweep --runs 1000`, 96 Zellen à 1.000 Läufe, **einprozessig gemessene 2,5 Stunden**. Rob nach Runde 13:

> „diese sweep tests sind gottlos lang, das muss effizienter gestaltet werden oder nur eine gute richtung prüfen und den rest balance ich selbst wenn du mir sagst wodrauf ich achten soll. […] keine X Stunden tests mehr laufen lassen."

Drei Messungen zur Lage (alle auf Robs Rechner, LuaJIT 2.1, 12 logische Kerne):

1. **Ein Lauf kostet 30 ms (N=5) bis 190 ms (N=40).** Die Zeit ist echte Simulationsarbeit, kein Leerlauf: der Profiler zeigt keine JIT-Abbrüche.
2. **Die Sim war single-threaded.** Kein `os.execute`, kein `io.popen`, keine Shard-Option — elf von zwölf Kernen standen still, obwohl jede Zelle vollständig unabhängig ist.
3. **72 der 96 Zellen tragen kein Kriterium.** Die Matrix variiert den Laufweg über {10, 14, 18, 22} s, um daraus den besten Wert zu wählen. Dieser Wert ist seit **Runde 6 (#96) per Rob-Entscheid fest** und wird von `model.lua` ohnehin hergeleitet: `graveyard_to_field_dist/move_speed_ghost + field_to_hill_dist/move_speed_alive` = 8 + 6 = **14 s**, für jedes N. Die Matrix rechnete also drei Viertel ihrer Zeit, um eine Zahl neu zu finden, die das Modell kennt. Übrig bleiben 24 Zellen: koordiniert und unkoordiniert je 4 N × Krits an/aus (F1–F5), plus Turtle 4 N × an/aus (Turtle-Gate); F6 fällt aus den koordinierten Zellen ab.

Dazu ein Präzedenzfall im eigenen Protokoll: GDD 17.9 dokumentiert für Runde 10 (#124), Runde 9 (#117) und Runde 7 (#103) bereits Änderungen, deren Nachweis bewusst ein billiger Vorher-Nachher-Vergleich statt einer Vollmatrix war — jeweils mit benanntem Revisionsauslöser.

## Entscheidung

**Der Standard-Nachweis ist der Richtungstest**: `lua sim/main.lua --quick --jobs 10` — 24 Zellen, 300 Läufe je Zelle, verteilt auf Kindprozesse. **Gemessen 145 Sekunden**, alle sieben Kriterien, F1-Werte 1 pp neben dem Runde-13-Endsweep.

Drei Bausteine tragen das:

- **`--jobs N`** verteilt die Zellen über `io.popen` auf N Kindprozesse und fügt deren Ergebnisse zusammen; `--part k/n` ist der Kindmodus. Reines Lua, gleiche Mechanik unter Windows und POSIX, Interpreter aus dem `arg`-Vektor. Der Zellen-Seed hängt am **Zellindex**, nicht an der Abarbeitungsreihenfolge — seriell und parallel liefern nachweislich bitgleiche Berichte.
- **`--quick`** ist die Teilmenge der vollen Matrix mit festem Laufweg und **behält die Zellindizes der Vollmatrix**, also auch deren Seeds. Richtungstest und Vollmatrix messen dieselben Welten und sind direkt vergleichbar.
- **Jede Siegquote trägt ihren 95-%-Vertrauensbereich.** Bei 300 Läufen sind das rund ±5 pp. Das steht im Bericht, damit niemand — ich eingeschlossen — eine Differenz von 2 pp für ein Ergebnis hält.

**Zeitregel:** Rechenläufe über ~10 Minuten laufen nur nach ausdrücklicher Ansage. Die volle Matrix (`--sweep --runs 1000 --jobs 10`, jetzt ~30 statt ~150 Minuten) bleibt für Releases und für Fälle, in denen die Laufweg-Dimension wirklich zur Debatte steht.

**Rob balanciert selbst weiter.** `docs/balancing-fuer-rob.md` ordnet jedem beobachtbaren Symptom seinen Regler samt Richtung und Nebenwirkung zu; `tools/log_lesen.lua` rechnet einen gespielten Abend aus dem Host-Log (GDD 17.3) nach und nennt den fälligen Regler beim Namen.

## Verworfene Alternativen

- **Nur schneller machen, Matrix behalten.** Parallel wären es immer noch ~30 Minuten je Nachweis — für eine Zeile Code-Änderung absurd, und die 72 Laufweg-Zellen blieben trotzdem sinnlos.
- **Die Sim gründlich optimieren.** Drei verhaltensneutrale Hotspots wurden behoben (Fehlermeldung in `model.p()`, `require` im Rumpf der Agentenfunktionen, Tabellen-Allokation im Blutpakt-Block) — zusammen 18 %. Der Rest ist echte Arbeit; ein größerer Umbau (Leichenliste, Zielwahl) würde Verhalten riskieren, um Sekunden zu sparen, die die Parallelisierung ohnehin bringt.
- **Läufe je Zelle einfach senken, ohne die Matrix zu kürzen.** Verschiebt nur die Ungenauigkeit, statt die überflüssige Dimension zu streichen.
- **Gepaarte Zufallsströme für die Krit-Dimension (Common Random Numbers).** Würde das Rauschen bei F4 (gemessenes Mittel 2,3 pp gegen ein Rauschniveau von ~1,6 pp bei n=1000) fast auslöschen und F4 auch mit wenigen Läufen aussagekräftig machen. **Bewusst verschoben:** ein eigener Krit-Strom verändert den Zufallsverbrauch und damit jede historische Siegquote — die Vergleichbarkeit mit allen bisherigen Protokolleinträgen wäre weg. Kommt frühestens mit einem ohnehin fälligen Neu-Kalibrieren.
- **Die Sim ganz sein lassen und nur noch spielen.** Die Sim ist das einzige Werkzeug, das eine Änderung vor dem LAN-Abend prüft; Playtest-Zeit ist die knappste Ressource im Projekt.

## Revisionsauslöser

Die Entscheidung gehört neu bewertet, sobald **eines** davon eintritt:

- Die **Todesstrafe wird wieder verhandelbar** (Rob will am Laufweg, an `respawn_base`/`respawn_factor` oder an den Weg-Distanzen drehen) — dann trägt die Laufweg-Dimension wieder ein Kriterium und die Vollmatrix ist der richtige Nachweis.
- Ein Richtungstest und die nächste Vollmatrix widersprechen sich in einem Kriterium um **mehr als den Vertrauensbereich** (bei 300 Läufen ±5 pp) — dann ist die Teilmenge nicht mehr repräsentativ.
- **F4 wird knapp** (Krit-Delta-Mittel über 4 pp): dann ist die gepaarte Zufallsvariante fällig, weil 300 Läufe das Rauschen nicht mehr tragen.
- Die Sim bekommt eine **zweite Raumdimension** oder Ambient-Mobs — dann steigen Laufzeit und Varianz, und die Zellzahl muss neu bemessen werden.
- Ein Richtungstest dauert wieder **über zehn Minuten** — dann ist etwas anderes kaputt.
