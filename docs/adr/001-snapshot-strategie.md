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

**Revisionsauslöser:**

- Der M3-Stresstest (GDD 17.4, 40 Clients) reißt ein Gate: Host-Tickdauer
  p95 > 16,6 ms mit relevantem Anteil im Netz-Packing, oder gemessener
  Upstream wird real zum Problem.
- Die Entitätenzahl wächst deutlich über ~100 (z. B. durch Modus 2 oder
  Designänderungen).
- Zielbetrieb ohne Kabel (WLAN) wird doch Realität.

Dann: Leiter-Stufe 2 (Snapshot-Rate auf 20–30 Hz entkoppeln, Interpolation
nur für Entitäten ohne Nahinteraktion, Rebase + Replay bleibt für alles
Eigene) — nie direkt zu Stufe 3/4 springen.
