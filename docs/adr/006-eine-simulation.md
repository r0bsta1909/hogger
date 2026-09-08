# ADR 006: Eine Simulation — die Spielsim ist die Balancing-Wahrheit, die 1D-Sim ist ausgemustert

**Status:** akzeptiert (Rob, 08.09.2026, Runde 20)

## Kontext

Bis Runde 19 beantwortete ein eigenes 1D-Modell (`sim/engine.lua`, `sim/agents.lua`, 0,1-s-Ticks, nur Distanz zum Boss) die Balancing-Fragen; das Spiel (`game/gamesim`) teilte mit ihm ausschließlich die Zahlentabelle `sim/model.lua` (ADR 002: „zwei Simulationen, eine Zahlenquelle"). Die 1D-Sim meldete für den koordinierten Raid 78–82 % Siege bei allen N.

Rob nach einem Abend mit 30+ Bots: *„die Werte, die angeblich über die Sim ermittelt worden sind, sind komplett unrealistisch, auch mit 30+ Bots ist bei Hogger nichts zu holen."* Sein Host-Log (`session-20260907-232458`, Try 4301, 21→31 Bots, 16 min) belegt es: 20.810 Schaden auf Hogger, **20.048 zurückgefressen**, 549 Tode, mittlere Lebensdauer 23,8 s, ein Drittel der Leben unter 10 s, Enrage bei 97 % HP.

Die Ursache war kein Zahlenfehler, sondern ein **anderer Raid**: Der koordinierte Agent der 1D-Sim hatte einen Dienst-Schurken, der nie angriff und jeden Fresskanal nach 0,5 s trat, 50 % Jäger auf Maximaldistanz, 60 % Charge-Ausweichen (im Spiel mechanisch unmöglich — Hogger springt auf die Zielposition), Schlachtruf, Schild, Handauflegung, Totstellen und Caster, die nach dem Anmarsch nie wieder einen Schritt machten. Die Spiel-Bots hatten nichts davon: Klasse fest `pid mod 8`, nur Fähigkeit 1 und 2, sie liefen jedem Schritt Hoggers nach und brachen damit ihre eigenen Casts. Dazu rechnete `model.walk_time()` den 2-s-Wiederbelebungskanal nicht mit. Siebzehn mechanische Abweichungen in Summe (Tuning-Protokoll GDD 17.9, Runde 20 Baustein 1).

**Die Lehre:** Eine Sim, deren Agenten besser spielen als die Bots, gegen die Menschen gemessen werden, misst ein anderes Spiel. Zwei Physiken driften nicht nur in den Zahlen, sondern im Verhalten — und Verhalten steht in keiner Zahlentabelle.

## Entscheidung

1. **Die Spielsimulation `game/gamesim` ist die einzige Balancing-Wahrheit.** `sim/gamerun.lua` treibt sie headless in reinem LuaJIT (kein `love.*`, kein Netz): ein Lauf = ein Zustand bis zum ersten `try_end`. Gemessen: ein voller 16-min-Try kostet N=5 0,9 s, N=40 7,0 s.
2. **Die Bots (`game/gamesim/bot.lua`) sind der Referenz-Raid**, gegen den balanciert wird — dieselben Bots, die als Debug-Bots im Spiel laufen. Drei Profile (GDD 17.2 5c): `typisch` (ein typischer LAN-Raid: hält Reichweite, bricht keine eigenen Casts, nutzt alle drei Fähigkeiten, ein Schurke hält Energie für den Tritt zurück, Tritt mit 1–2 s Reaktion, Klassenwahl nach Bedarf, keine Charge-Ausweiche), `kopflos` (ignoriert das Fressen; F2/F3-Gegenprobe), `turtle` (nur Heilung; Anti-Stall-Gate). Was die Bots können und was nicht, ist damit Balancing-Wahrheit und steht unter Test (`tests/unit_bot.lua`).
3. **Eine Auswertung für Sim und Abend:** `tools/logreport.lua` rechnet Sim-Läufe (`analyse_events`) und Host-Logs (`analyse`) durch dieselbe Funktion. Lebensdauern, Tritt-Latenz, Fress-Bilanz und Klassenwechsel sind in beiden dieselben Zahlen.
4. **Das Streuungsmodell (GDD 17.2 5b) gilt auch in der Spielsim** (`p.skill`, nur vom Runner gesetzt; Menschen und Leeroy 1,0). Ohne Streuung springen Siegquoten zwischen 0 und 100 %. Nebenströme (Streuung, Bot-Gehirne) werden mit `rng.mix` geseedet — der erste Wert eines Lehmer-Generators ist linear im Seed, benachbarte Laufnummern ergaben sonst eine Treppe von Gruppenfaktoren.
5. **Der Richtungstest** ist `lua sim/main.lua --engine spiel --quick --jobs 10`: 16 Zellen (N ∈ {5, 10, 20, 40} × `typisch` mit Krits an/aus, `kopflos` und `turtle` mit Krits an), 50 Läufe je Zelle, ~7 min, ±14 pp je Quote. 100 Läufe (±10 pp) kosten ~14 min und laufen nur auf Ansage (ADR 004 gilt weiter: keine Rechenläufe über ~10 min ungefragt).
6. **Die 1D-Sim ist gelöscht** (`sim/engine.lua`, `sim/agents.lua`, `tests/unit_engine.lua`, der Engine-Zweig in `tests/determinism.lua`). `sim/model.lua`, `rng.lua`, `hash.lua`, `report.lua`, `param_docs.lua` bleiben. Ein Gleichstandsnachweis beider Engines war nicht das Ziel: Die neue Sim reproduziert Robs Abend (0 % Siege, Fress-Heilung ≈ Raidschaden, 20–34 % Kurzleben) — das ist der Beleg, dass sie das Spiel misst.

## Verworfene Alternativen

- **Die 1D-Sim ehrlich machen** (Agenten auf Bot-Verhalten umstellen, Tritt-Latenz, Cast-Abbruch, Todesstrafe korrekt). Billiger, aber zwei Physiken bleiben und driften weiter — die nächste Fähigkeit hätte wieder in beiden Modellen gebaut werden müssen, und die 1D-Sim kann weder Reichweitenhaltung noch Pathing noch Mob-Aggro ausdrücken.
- **Beide parallel** mit Gegenprobe. Doppelter Aufwand für eine Gegenprobe, die genau dann schweigt, wenn beide dieselbe Annahme teilen.
- **Nur noch spielen.** Playtest-Zeit ist die knappste Ressource; die Sim ist das einzige Werkzeug, das eine Änderung vor dem LAN-Abend prüft.

## Revisionsauslöser

- **Ein gespielter Abend widerspricht der Sim um mehr als den Vertrauensbereich** (Log-Leser gegen Richtungstest: Siegquote, Lebensdauer, Fress-Bilanz). Dann spielen die Bots nicht „typisch" — erst die Bots korrigieren, nie die Zahlen.
- **Der Richtungstest dauert über zehn Minuten** — dann ist etwas kaputt oder die Sim braucht Beschleunigung (Parameter-Cache je Tick, Param-Dump nur im ersten Try), nicht weniger Läufe.
- **`game/gamesim` braucht `love.*`** — dann ist die headless-Fähigkeit weg und mit ihr die Sim.
- **Die Bot-Rollenziele ändern sich** (Schurken `max(2; ⌈N/10⌉)`, Heiler `max(2; ⌈N/6⌉)`, Fernkampf `⌈N/3⌉`): gemessen kippt ein Schurke statt zwei N=5 von 89 auf 10 % Siege. Wer die Ziele anfasst, kalibriert neu.
- **Player Agency kommt** (Robs nächstes Thema: Charge ausweichbar, Klassenentscheidungen im Kampf): jede neue Entscheidung, die ein Mensch treffen kann, müssen die Bots „typisch" treffen können — sonst misst die Sim wieder ein anderes Spiel.

## Folgen für ältere ADRs

ADR 002 Punkt 1 („zwei Simulationen, eine Zahlenquelle") ist damit abgelöst; ADR 004 (Richtungstest statt Vollmatrix) gilt weiter, nur mit der Spielsim als Engine und ~7 statt ~2 Minuten. Die Laufweg-Dimension der alten Matrix gibt es nicht mehr — der Laufweg ist echte Kartengeometrie.
