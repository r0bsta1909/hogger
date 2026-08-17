# ADR 003: CI-Zuschnitt — ein Linux-Schnellgate, Plattform-Matrix daneben

**Status:** akzeptiert (Rob, 17.08.2026) — **erster Revisionsauslöser am
selben Tag eingetreten**, siehe „Nachtrag 17.08.2026" am Ende.

**Kontext:** Das Actions-Freikontingent des privaten Repos war nach einem
einzigen Bautag zu 98 % verbraucht (1.953 von 2.000 Minuten, 15 Tage bis zum
Periodenende). Die Ursache ist keine langsame Suite, sondern der
Abrechnungsmodus: **GitHub rundet pro Job auf die volle Minute auf und
multipliziert erst danach mit dem OS-Faktor** (Linux 1x, Windows 2x,
macOS 3-Core 10x). Ein `ci`-Lauf mit fünf Jobs:

| Job | OS | Faktor | echte Laufzeit | abgerechnet |
|---|---|---|---|---|
| `test (ubuntu-latest)` | Linux | 1x | ~18 s | 1 Min |
| `test (windows-latest)` | Windows | 2x | ~17 s | 2 Min |
| `test (macos-latest)` | macOS | 10x | ~10 s | 10 Min |
| `stufe4 (ubuntu-latest)` | Linux | 1x | ~22 s | 1 Min |
| `stufe4 (macos-latest)` | macOS | 10x | ~11 s | 10 Min |
| | | | **~26 s Wall-Clock** | **24 Min** |

83 CI-Läufe (41 `pull_request` + 42 `push`) ergeben 1.992 abgerechnete
Minuten — die gemessenen 1.953. Die sechs Release-Läufe kosten zusammen
~30 Minuten und sind nicht das Problem. **Die zwei macOS-Jobs allein sind
~1.660 Minuten, also 85 % des Kontingents**, für 21 Sekunden Rechenzeit
pro Lauf. Zweiter Multiplikator: `push: [main]` **und** `pull_request`
bedeuten zwei volle Läufe je gemergtem Feature — 48 Minuten pro PR.

**Entscheidung:**

1. **Ein Job statt fünf im Schnellgate** (`ci.yml`): Stufen 1, 3 und 4
   nacheinander in derselben Ubuntu-Job-Instanz. Weil pro Job aufgerundet
   wird, ist die Job-Anzahl der Hebel, nicht die Testdauer. 24 → 1 Minute.
2. **Cross-Platform-Beweis verschoben, nicht gestrichen** (`ci-plattform.yml`):
   Windows + macOS laufen per `workflow_dispatch` (vor LAN-Abend/Release) und
   bei PRs mit Label `plattform` (Dateipfade, Zeilenenden, `love.filesystem`,
   Netzcode, Binärformate). Bewusst **nicht** bei jedem Tag: bei sechs
   Releases an einem Tag wäre das teurer als der bisherige Zustand.
3. **`concurrency` + `cancel-in-progress`** in beiden Workflows; überholte
   Läufe sterben, statt bezahlt zu Ende zu laufen.
4. **`paths-ignore`** für `docs/**`, `reports/**`, `**.md`. Das
   Tuning-Protokoll (GDD 17.9) und GDD-Änderungen sind in diesem Projekt
   häufige eigene PRs und zogen bisher die volle 24-Minuten-Matrix für eine
   Textänderung.
5. **`push: main` bleibt als Linux-Backstop** (1 Minute) statt gestrichen —
   das Netz gegen Squash-Merge-Überraschungen kostet fast nichts.

Ergebnis: **2 abgerechnete Minuten pro gemergtem Feature statt 48.**

**Verworfene Alternativen:**

1. *Tests beschleunigen / Caching:* wirkungslos. Die Jobs laufen bereits
   10–22 Sekunden; die Rundung auf die volle Minute macht jede weitere
   Sekunde Ersparnis wertlos.
2. *macOS-Jobs ersatzlos streichen:* verliert den Cross-Platform-Beweis
   dauerhaft, obwohl macOS eine Zielplattform ist (Mac + Windows).
3. *`macos-13` (Intel, 10x) statt `macos-latest`:* gleicher Faktor, kein
   Gewinn.
4. *Alles auf `push: main` verlagern und PRs ungetestet lassen:* verletzt
   „`main` ist immer grün" (CLAUDE.md).
5. *Self-hosted Runner auf Robs Mac/Windows-Kiste:* technisch die beste
   Abdeckung (echte Zielhardware, 0 Minuten), aber Einrichtungs- und
   Betriebsaufwand für ein Spaßprojekt; bleibt Rückfalloption.
6. *GitHub Pro kaufen:* Rob-Entscheid (CLAUDE.md), und der Faktor 10 auf
   macOS bliebe — der Umbau lohnt unabhängig davon.

**Nachziehen im GDD:** Kap. 17.0 Punkt 2 beschreibt jetzt beide Workflows.

**Revisionsauslöser:**

- **Das Repo wird öffentlich** (Robs Entscheid vom 17.08.2026, Umstellung
  steht noch aus). Dann sind Actions-Minuten unbegrenzt frei und der einzige
  Kostenfaktor ist Wall-Clock. Sofort zurückzunehmen: in
  `ci-plattform.yml` den `schedule`-Block einkommentieren und die beiden
  `if:`-Bedingungen entfernen, damit die Matrix wieder an jedem PR hängt.
  Das Schnellgate als Ein-Job-Design darf bleiben — es ist auch ohne
  Kostendruck das schnellere Feedback.
- **Ein Plattformfehler entkommt dem Schnellgate** und fällt erst beim
  LAN-Abend oder im Release auf (falscher Pfadtrenner, CRLF, LuaJIT-
  Verhaltensunterschied). Dann ist das Label `plattform` zu schwach: Matrix
  zurück an jeden PR, notfalls über Punkt 1 oder Self-hosted Runner
  finanziert.
- **Das Minutenbudget wird dauerhaft entspannt** (Pro-Abo oder Self-hosted
  Runner) — dann gilt derselbe Rückbau wie bei Punkt 1.
- **Stufe 2 (Sim) oder Stufe 5 wandern in die CI**: dann ist dieser Zuschnitt
  neu zu rechnen, weil dann erstmals echte Laufzeit statt Rundung dominiert.

---

## Nachtrag 17.08.2026: Repo öffentlich — Matrix zurück in die Breite

Rob hat das Repo noch am selben Tag auf **public** gestellt. Damit ist
Revisionsauslöser 1 eingetreten: Actions-Minuten sind unbegrenzt frei, der
einzige verbleibende Kostenfaktor ist Wall-Clock. Umgesetzt:

- **`ci-plattform.yml` hängt wieder an jedem PR und Push auf `main`**, dazu
  `workflow_dispatch` und der wöchentliche `schedule` (montags 04:00 UTC).
  Das Label `plattform` und die `if:`-Gates sind entfallen.
- **Stufe 4 läuft jetzt auch auf Windows.** Vorher nie — Rob entwickelt
  darauf, und Stufe 4 ist die einzige Stufe, die Pfade, Zeilenenden und
  `love.filesystem` echt anfasst. Zwingend `lovec.exe` statt `love.exe`:
  `love.exe` ist ein GUI-Subsystem-Binary ohne angehängte Konsole, die
  Testausgabe wäre unsichtbar.
- **Das Ein-Job-Schnellgate bleibt.** Es ist auch ohne Kostendruck das
  bessere Design: ~40 s bis rot/grün, während `brew install --cask love`
  und der LÖVE-Download in der Matrix Minuten brauchen.
- **`paths-ignore` ist entfallen.** In Kombination mit erzwungenen
  Status-Checks ist es eine Falle: ein reiner Doku-PR wartet ewig auf einen
  Check, der nie startet, und lässt sich nicht mergen. Bei 40 s Laufzeit ist
  Immer-Laufen die einfachere Wahrheit als eine Ausnahmeliste.
- **Sammel-Gate `plattform-gruen`** (ein Job, `needs` auf die Matrix). Ohne
  ihn müsste die Branch-Schutzregel jeden Matrix-Namen einzeln nennen
  (`plattform (macos-latest)` …) und bräche bei jeder Matrix-Änderung.
- **Branch-Schutz auf `main` aktiviert** — auf einem privaten Repo im
  Free-Plan war das gar nicht möglich, CLAUDE.mds „`main` ist geschützt" war
  bis hierher eine Absichtserklärung. Jetzt erzwungen: PR-Pflicht, dazu die
  Checks `test` und `plattform-gruen`. Bewusst **null** erforderliche
  Reviews (das Projekt hat genau einen Menschen) und **kein**
  `enforce_admins`, damit Rob im Notfall durchkommt.

Der Kostenbefund selbst bleibt gültig und ist der eigentliche Wert dieses
ADR: **Job-Anzahl ist der Hebel, nicht Testdauer**, solange pro Job auf die
volle Minute aufgerundet wird. Wird das Repo je wieder privat, ist der
Rückbau der Stand vor diesem Nachtrag.

**Neuer Revisionsauslöser:** Das Repo wird wieder privat, oder die Suite
wächst so weit, dass echte Laufzeit statt Rundung dominiert (Stufe 2/Sim
oder Stufe 5 in der CI) — dann ist der Zuschnitt neu zu rechnen.
