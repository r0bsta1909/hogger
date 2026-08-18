# ADR 002: M2-Spielarchitektur — love-freie Spielsimulation, Input-Format, Snapshot-Inhalt

**Status:** akzeptiert

**Kontext:** M2 baut das erste spielbare Spiel (5er-LAN, 3 Klassen). Die
Balancing-Sim (`sim/engine.lua`, 1D, 0,1-s-Ticks) beantwortet Balancing-Fragen;
das Spiel braucht eine echte 2D-Simulation mit 60 Hz und Spieler-Input. CLAUDE.md
verlangt: Simulation love-frei, `model.lua` als einzige Zahlenquelle, fixer
Zeitschritt, 1-Byte-Input, Determinismus-Tests.

**Entscheidungen:**

1. **Zwei Simulationen, eine Zahlenquelle.** `game/gamesim/` ist die
   Spielsimulation (2D, 1/60 s, echte Inputs) — reines Lua, kein `love.*`,
   importiert `sim/model.lua` unverändert (alle Formeln/Parameter) und
   `sim/rng.lua`/`sim/hash.lua`. `sim/engine.lua` bleibt als 1D-Balancing-
   Modell bestehen (schnelle Sweeps; GDD 17.2 schreibt es so vor). Beide teilen
   ausschließlich `model.lua` — Mechanik-Konstanten existieren nie doppelt.
   Die Stufe-1/3-Tests laden `gamesim` headless mit vergiftetem love-Global.
2. **Schrittfunktion:** `step(state, inputs) → events` ist die einzige Stelle,
   die Spielzustand ändert (Skill §2). Kosmetik (Schadenszahlen, Sounds) kommt
   als Ereignisliste zurück; dieselben Ereignisse speisen das JSONL-Log
   (GDD 17.3) und — über den reliable-Kanal — die Client-Darstellung.
   Eine Quelle für Log UND Präsentation.
3. **Input:** 1 Byte Maske je Tick (bit0 links, 1 rechts, 2 hoch, 3 runter,
   4 springen, 5–7 Fähigkeit 1–3; Zustände, Flankenerkennung in der Sim).
   Reservierte Kombinationen gibt es nicht — alle 8 Bits sind belegt; ein
   Protokollversionssprung ändert `protoVersion` im Header. Das INPUT-Paket
   trägt Client-Tick, die Masken der letzten 3 Ticks (Redundanz, Skill §3)
   und 1 Byte quantisierte Blickrichtung (Maus; nur Kosmetik, andere sehen
   den Richtungspfeil). **Zielwahl (Klick/Tab) ist KEIN Input-Bit**, sondern
   eine reliable Nachricht (`SET_TARGET`, Entity-ID) — niederfrequent,
   verlustfrei, kein Platz in der Maske nötig.
   **Nachtrag Runde 7 (#103):** Die Klick-Heilung aus der Heil-Leiste folgt
   demselben Muster als `HEAL_REQUEST` (1 Byte Ziel-Spieler-ID, reliable,
   Vorbild ENGAGE): der Host validiert autoritativ und startet den Heilzauber
   mit explizit eingefrorenem Ziel, `p.target` bleibt unberührt — dadurch
   existiert kein Ordnungs-Race zwischen reliable- und Input-Kanal.
   Verworfen: ein zweiter Ziel-Slot im Input-Byte (alle 8 Bits belegt) und
   ein clientseitiges "SET_TARGET + verzögerter Fähigkeitsdruck"
   (Kanal-Reihenfolge nicht garantiert, zwei Wahrheiten für ein Klickziel).
4. **Snapshots** (ADR-001: 60 Hz Vollzustand, unreliable): Feldliste wird
   gegen den echten State erhoben und per Test erzwungen (Skill §4).
   Übertragen wird, was der Empfänger zeichnet: je Spieler Position
   (2×u16, logische px), HP/Ressource (u8-Verhältnis + u16 roh für Balken),
   Klasse, Zustandsbits (lebend/Geist/castet/springt/gestohlen), Blickrichtung,
   Ziel-ID, Cast-Fortschritt; Hogger: Position, HP (u16), Zustand,
   Fress-Zählerstand, Charge-Telegraph (Ziel + Restanlauf); global: Uhr,
   Try-Nr., ackInputTick je Client im Paketkopf.
5. **Szenen:** flacher Zustandsautomat in `game/main.lua` (Debug-Start →
   Spiel), Netz-Update läuft IMMER (Skill §7: kein Szenen-Stack, der Sockets
   verhungern lässt). Fixer Akkumulator (gedeckelt 0,25 s), Rendering
   interpoliert; `dt` erreicht die Physik nie.
6. **M2-Verbindung ohne Discovery:** `love game --host` / `--join <ip>`
   (Debug-Start laut GDD 15). Auto-Discovery kommt in M3 (GDD 15) und ist
   durch die Beacon-Spezifikation (Kap. 3/14) bereits festgelegt.

**Verworfene Alternativen:** Eine gemeinsame Engine für Balancing-Sim und
Spiel (1D→2D-Umbau hätte die validierte Sweep-Basis zerstört und GDD 17.2
widersprochen; das Duplikationsrisiko fangen gemeinsame `model.lua`-Zahlen
plus Invarianten-Tests); Zielwahl als Input-Bits (zu wenig Bits, Klick braucht
ohnehin Entity-Adressierung); Facing im Snapshot statt im Input (der Host
kennt die Mausrichtung des Clients nicht — sie MUSS im Input reisen).

**Revisionsauslöser:** Stufe-4-Tests decken Mechanik-Drift zwischen gamesim
und sim/engine auf (gleiche Formelwerte, verschiedene Ergebnisse jenseits der
Modellunterschiede 1D/2D) → dann Konsolidierung neu bewerten. Der 40er-
Stresstest (M3) misst Snapshot-Packkosten → ADR-001-Revisionspfad.
