# ADR 001: Snapshot-Strategie — 60 Hz Vollzustand statt 20 Hz + Interpolation

**Status:** akzeptiert

**Kontext:** GDD v2.4 Kap. 14 sah 20-Hz-Snapshots mit 100 ms Interpolation vor;
der Skill (docs/skills/love2d-lan-game.md §3) empfiehlt bei kleinem Weltzustand
volle Tickrate (60 Hz) als Vollzustand und gibt in §3.1 eine Eskalationsleiter
für größere Welten wie unsere (~50 Entitäten, bis 40 Clients). CLAUDE.md
verlangt: Entscheidung als ADR, GDD Kap. 14 per PR nachziehen.

**Entscheidung:** **60 Hz Vollzustands-Snapshots** (Leiter-Stufe 0), mit
Rebase + Replay der eigenen Eingaben auf dem Client (eine Zeitbasis, Skill §3).
Die Rechnung nach Leiter-Stufe 1 („erst rechnen"):

- Snapshotgröße: ~50 Entitäten × 14 Bytes ≈ 700 B + Header.
- Je Client: 700 B × 60 Hz ≈ 42 kB/s. Host-Upstream bei N=40: ≈ 1,7 MB/s
  ≈ **13,5 Mbit/s** — trivial auf Gigabit, unkritisch selbst auf 100 Mbit
  (Kabelpflicht laut Skill §9 ist ohnehin gesetzt).
- Host-CPU: Der Snapshot ist für alle Clients identisch und wird **einmal pro
  Tick gepackt**; je Client kommt nur ein kleiner Kopf mit `ackInputTick`
  dazu. Packkosten wachsen also nicht mit N — der befürchtete Host-Engpass
  (Skill §3.1) liegt bei Sim + Kollision, nicht beim Netz.

Gewonnen wird genau das, was der Skill teuer bezahlt hat: keine
Interpolation, keine zwei Zeitbasen, kein Puffer-Tuning, keine Lücken-
Behandlung; Desync ist per Konstruktion unmöglich.

**Verworfene Alternativen:**

1. *20 Hz + 100 ms Interpolation (GDD v2.4):* bringt das
   Zwei-Zeitbasen-Problem zurück ([gemessen], Skill §3) und spart Bandbreite,
   die im LAN niemand braucht — Komplexität ohne Problem.
2. *Delta-Kompression:* Leiter-Stufe 4, teuerste Komplexität
   (Baseline-Verwaltung, Resync-Pfade), im LAN fast nie nötig.
3. *Lockstep/Rollback:* cross-platform mit LuaJIT unerreichbar
   ([gemessen], Skill §3) — bleibt in jeder Variante ausgeschlossen.

Ebenfalls angepasst: Client-Input wird pro Tick (60 Hz) als 1-Byte-Bitmaske
mit ~3-Tick-Redundanz gesendet (Skill §3 „Eingaben") statt der bisherigen
30 Hz — Redundanz macht Einzelverluste unsichtbar, Kosten sind Bytes.

---

## Nachtrag 2026-08-20 (Runde 16): die Rechnung oben war überholt

Die Entscheidung bleibt. Die Zahlen, mit der sie begründet wurde, stimmten
nicht mehr — sie sind jetzt **gemessen** statt geschätzt
(`game/test/budget.lua`, Stufe 4, Kosten je Datensatz aus dem echten Packer
abgeleitet):

| Block | angenommen 2026-08-16 | gemessen 2026-08-20 |
|---|---|---|
| je Spieler | 14 B | **25 B** |
| je NPC | 14 B | 8 B |
| je Leiche | 14 B | 4 B |
| je Bodenbeute | 14 B | 5 B |
| fester Teil | im Pauschalwert | 39 B |

Damit ergibt sich für den Rumpf:

| Zustand | Rumpf | Paket (+7 B Kopf) | ENet-MTU 1400 B |
|---|---|---|---|
| N=5, frischer Try | 212 B | 219 B | passt |
| N=40, frischer Try | 1.215 B | 1.222 B | passt, 178 B Luft |
| **N=40, Leichen am 255er-Deckel** | 2.295 B | **2.302 B** | **902 B darüber** |
| N=40, alles am Anschlag | 2.655 B | 2.662 B | 1.262 B darüber |

Upstream entsprechend: **23,3 Mbit/s** bei N=40 im frischen Try (statt der
angenommenen 13,5), **44,1 Mbit/s** im gesättigten Zustand. Auf Gigabit
weiterhin unkritisch; auf 100 Mbit ist der gesättigte Fall nicht mehr trivial.

**Der gesättigte Zustand ist der Normalfall, kein Sonderfall.** Leichen
verschwinden ausschließlich, wenn Hogger eine frisst (`step.lua`), sonst nie;
gelöscht wird die Liste erst beim Try-Start. 255 Leichen sind 6,4 Tode je
Spieler — bei 40 Spielern und 24 s Todesstrafe erreicht ein Try das nach
wenigen Minuten und bleibt dann dort.

**Warum das M3-Gate es nicht gesehen hat:** die 40 Clients des Stresstests
(`game/test/stress.lua`) nehmen nie die Quest an. Unter `quest < 2` wird ihre
Eingabemaske genullt, sie bleiben die vollen zehn Minuten Geister am Friedhof,
sterben nie und hinterlassen keine einzige Leiche. Die dort gemessenen
20,7 Mbit/s gehören zum leichenfreien Snapshot. Das Gate war grün, weil es den
teuren Zustand nie erzeugt hat — und die Budget-Prüfung in `headless.lua`
rechnete zugleich mit 20 B je Spieler und lief nur mit sechs bis acht Spielern.

**Was daraus folgt und was offen bleibt:** Oberhalb der MTU fragmentiert ENet.
Ob ein fragmentiertes Paket auf Kanal 1 unzuverlässig bleibt oder ob ENet auf
zuverlässige Fragmente zurückfällt — und damit genau die Lückenbehandlung
zurückholt, die diese Entscheidung vermeiden wollte —, ist **nicht gemessen**
und wird hier ausdrücklich nicht behauptet. Das ist die offene Frage.

Der naheliegende Hebel ist dabei **nicht** die Eskalationsleiter: der
Leichen-Block ist der einzige unbegrenzt wachsende Teil des Snapshots, und
eine Obergrenze für `state.corpses` wäre ein weit kleinerer Eingriff als eine
neue Snapshot-Strategie. Weil das die Fressmechanik berührt, ist es eine
Design-Entscheidung und keine technische.

**Revisionsauslöser:**

- Der M3-Stresstest (GDD 17.4, 40 Clients) reißt ein Gate: Host-Tickdauer
  p95 > 16,6 ms mit relevantem Anteil im Netz-Packing, oder gemessener
  Upstream wird real zum Problem.
- Die Entitätenzahl wächst deutlich über ~100 (z. B. durch Modus 2 oder
  Designänderungen).
- Zielbetrieb ohne Kabel (WLAN) wird doch Realität.
- **Der Snapshot-Rumpf erreicht die ENet-MTU (1400 B abzüglich 7 B Kopf)**
  — seit dem Nachtrag oben im gesättigten 40er-Try **ausgelöst**; die
  Konsequenz ist noch nicht bewertet. Nachgemessen wird das maschinell in
  `game/test/budget.lua` (Stufe 4), das die Kosten je Datensatz aus dem
  Packer ableitet und nicht mehr veralten kann.

Dann: Leiter-Stufe 2 (Snapshot-Rate auf 20–30 Hz entkoppeln, Interpolation
nur für Entitäten ohne Nahinteraktion, Rebase + Replay bleibt für alles
Eigene) — nie direkt zu Stufe 3/4 springen.
