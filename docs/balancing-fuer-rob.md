# Balancing für Rob — eine Seite, ein Regler nach dem anderen

Diese Seite ist für den Abend gedacht, nicht fürs Archiv: Du siehst etwas im Spiel, schlägst hier nach, drehst **einen** Regler im F10-Panel, spielst weiter. Alles hier gilt live — Änderungen im Panel wirken sofort und gehen an alle Clients.

**Die eine Regel:** immer nur einen Wert auf einmal ändern, und zwar in Schritten, die das Panel vorgibt. Zwei gleichzeitig verstellte Werte kann hinterher niemand mehr auseinanderrechnen — auch ich nicht.

---

## Vorher: die drei Zahlen, an denen alles hängt

| Was | Wo du es siehst | Zielband |
|---|---|---|
| **Siegquote** | über den Abend gezählt: wie viele Trys gingen durch | 6 bis 9 von 10 bei einer Gruppe, die zusammenspielt |
| **Länge eines Siegtrys** | die Uhr unten am Minimap-Ring, wenn Hogger fällt | 6 bis 13 Minuten |
| **Hogger-Rest-HP beim Wipe** | steht auf der Statistik-Tafel: „Er hatte noch X %." | knapp = spannend; über 60 % = zu schwer |

Wenn diese drei stimmen, ist das Spiel im Lot. Alles Weitere ist Geschmack.

---

## Symptom → Regler → Richtung

### Der Kampf geht zu leicht aus / ihr gewinnt fast immer
| Regler | Richtung | Nebenwirkung |
|---|---|---|
| `hogger_hp_slope` | **hoch** (Schritt 10) | der ehrlichste Regler: mehr HP, längerer Kampf. Trifft alle Raidgrößen gleich. |
| `hogger_autohit_dmg` | hoch (Schritt 1) | Nahkämpfer sterben schneller, Heiler kommen unter Druck — dreht Härte, nicht Länge |

**Zuerst immer `hogger_hp_slope`.** Er ist der Hebel, mit dem auch ich rechne.

### Der Kampf ist zu schwer / ihr kommt nie unter 50 % seiner HP
| Regler | Richtung | Nebenwirkung |
|---|---|---|
| `hogger_hp_slope` | **runter** | s. o. |
| `hogger_charge_cd` | hoch | weniger Charges = weniger Zufallstode am Rand |
| `hogger_charge_dodge_px` | runter (z. B. 20) | Ausweichen wird leichter; 0 = die Charge trifft immer wie bis Runde 20. Der Log-Leser zeigt die Ausweichquote eures Abends |
| `hogger_threat_swap_melee` / `_ranged` | hoch (z. B. 1,3 / 1,6) | Hogger klebt länger an seinem Ziel — der Krieger hält ihn, Stoff lebt länger, der Krieger stirbt öfter. 1,0 / 1,0 = ein Punkt kippt wie bis Runde 20 |
| `hogger_charge_threat_loss` | hoch | die Charge lässt die Aggro stärker rotieren; 0 = sie kostet keine Bedrohung |
| `hogger_cleave_divisor` | hoch | er trifft weniger Leute gleichzeitig; entlastet den Nahkampfklumpen |

Vorher aber prüfen, **woran** ihr scheitert: Wipe (alle tot) oder Zeitlimit? Bei Zeitlimit ist es die HP-Zahl, bei Wipes sind es die Schadenswerte oder die Heilung.

### Ein Try zieht sich, obwohl ihr gewinnt
| Regler | Richtung |
|---|---|
| `hogger_hp_slope` | runter |
| `autohit_melee_dmg` / `autoshot_dmg` | hoch (Schritt 1 — Vorsicht, das ist der Grundschaden ALLER Spieler) |

### Hogger frisst euch kaputt (er heilt sich schneller, als ihr Schaden macht)
| Regler | Richtung | Bedeutung |
|---|---|---|
| `eat_heal_rate` | runter (Schritt 0,001) | Anteil seiner Max-HP, den er pro Sekunde frisst |
| `eat_cd` | hoch | längere Pause zwischen zwei Mahlzeiten |
| `eat_channel_duration` | runter | er frisst kürzer — Achtung, während er frisst, **schlägt er nicht**: kürzer heißt auch weniger Verschnaufpause für euch |
| `eat_hp_threshold` | runter | er fängt erst später an zu fressen (nur unter X % seiner HP) |

### Das Fressen wird nie unterbrochen
Erst schauen, **warum**: Ist ein Schurke da? Steht er nah genug? Drückt er die 4?
| Regler | Richtung |
|---|---|
| `rogue_kick_cd` | runter (mehr Tritte pro Minute) |
| `rogue_kick_energy` | runter (der Tritt geht öfter aufs Ziel, auch bei leerer Energie) |

Ist niemand da, der tritt, hilft kein Regler — das ist eine Ansage-Frage. **Der Tritt des Schurken ist die einzige Unterbrechung im Spiel.**

### Die Nahkämpfer sterben im Sekundentakt
| Regler | Richtung |
|---|---|
| `hogger_cleave_divisor` | hoch (er trifft weniger Umstehende) |
| `hogger_slice_bleed_dmg` / `hogger_slice_duration` | runter |
| `hp_plate` / `hp_leather` / `hp_cloth` | hoch (Schritt 5) — trifft alle Klassen dieser Rüstung |

### Die Heiler halten nichts
| Regler | Richtung |
|---|---|
| `priest_heal_amount`, `druid_rejuv_total`, `paladin_holylight_heal` | hoch |
| `mana_regen_rate` | hoch |
| `threat_per_heal` | runter, wenn Heiler dauernd Aggro ziehen und sterben |

### Zu viel Zeit vergeht mit Laufen / der Tod fühlt sich zu hart an
Die Todesstrafe ist **absichtlich konstant** (Respawn-Timer 10 s + 16 s Laufweg inklusive Wiederbelebungskanal = 26 s; wer den Freigabe-Knopf nicht drückt, zahlt 5 s mehr) und seit Runde 6 fest. Wenn du sie doch drehen willst: `respawn_base`, `respawn_factor`. Nebenwirkung: der Laufweg hängt an `graveyard_to_field_dist` und `field_to_hill_dist` — und die 40-Sekunden-Frist `hogger_no_contact_reset` muss länger bleiben als die Zeit, die ein kompletter Wipe zum Zurückkommen braucht (31 s), sonst trabt Hogger heim und der Try ist verloren.

### Alle sterben in zehn Sekunden / man belebt sich nur wieder, um gleich wieder zu sterben
Das ist seit Runde 20 messbar (F7): der Log-Leser nennt die mittlere Lebensdauer nach der Wiederbelebung (Ziel ≥ 30 s) und den Anteil der Leben unter 10 s (Ziel ≤ 20 %).
| Regler | Richtung | Nebenwirkung |
|---|---|---|
| `hogger_cleave_divisor` | hoch | er trifft weniger Umstehende gleichzeitig — der Nahkampfklumpen überlebt länger |
| `hogger_autohit_dmg` | runter (Schritt 1) | Stoff stirbt in 3 statt 2 Hits; macht ihn insgesamt weicher, also danach `hogger_hp_slope` prüfen |

### Das Fressen holt alles zurück (der Log-Leser sagt „X % zurückgeholt")
Auch wenn die Schurken treten: ein Mensch braucht 1 bis 3 Sekunden bis zum Tritt, und in dieser Zeit heilt Hogger bei 30 Spielern schon 300 bis 900 HP je Kanal. Robs Abend vom 7. September: 88 % des gesamten Raidschadens zurückgefressen bei 73 % getretenen Kanälen.
| Regler | Richtung | Bedeutung |
|---|---|---|
| `eat_heal_rate` | runter (Schritt 0,001) | weniger Heilung je Sekunde Kanal — der ehrlichste Regler gegen die Latenz |
| `eat_hp_threshold` | runter | er fängt erst später an zu fressen |
| `eat_cd` | hoch | seltener |

### Die Mobs am Wegesrand lenken zu stark ab
| Regler | Richtung |
|---|---|
| `mob_slot_base` | runter (weniger Mobs auf der Karte) |
| `wolf_aggro_radius` | runter |

---

## Die Fallen

- **`hogger_hp_offset` läuft andersherum.** Die Formel ist `3·N² + slope·N − offset`: **offset hoch = weniger HP.** Wer ihn für einen Härte-Regler hält, dreht in die falsche Richtung. Nimm `hogger_hp_slope`.
- **Der Krit-Multiplikator ist tabu.** Wenn Krits zu viel entscheiden, dreh `crit_chance_player`, nie `crit_mult_player` — ein Krit muss sich wie ein Krit anfühlen.
- **Fressen ist kein reiner Nachteil.** Während Hogger frisst, schlägt er nicht. Bei einer Gruppe, die genug Schaden macht, ist eine Mahlzeit netto ein *Geschenk*. Deshalb kippt „mehr Fressen" nicht automatisch zu seinen Gunsten.
- **Schadenswerte treffen alle N gleichzeitig.** `autohit_melee_dmg` +1 klingt harmlos, ist bei 40 Spielern aber +40 Schaden pro Schwungrunde.
- **Was du im Panel drehst, steht danach in keinem Dokument.** Drück im F10-Panel **[E]**: das schreibt `tuning.csv` mit allen Abweichungen vom GDD-Stand in den Spielordner. Diese Datei schickst du mir, dann ziehe ich sie ins GDD nach.

---

## Was du mir nach einem Abend schickst

1. **Das Host-Log** (nur vom Rechner, der gehostet hat). **Achtung, zwei Orte:**
   - Du spielst das **heruntergeladene Spiel** (`wow.exe`): `%APPDATA%\hogger\logs\session-<datum>.jsonl`
   - Du startest es aus dem Repo (`love game`): `%APPDATA%\LOVE\hogger\logs\session-<datum>.jsonl`

   Der Unterschied kommt von LÖVE selbst: ein fertig gepacktes Spiel legt seinen Ordner direkt unter `%APPDATA%`, die Entwicklungsversion unter `%APPDATA%\LOVE`. Auf dem Mac entsprechend `~/Library/Application Support/hogger/` bzw. `.../LOVE/hogger/`. Im Zweifel: das Debug-Overlay (F12) zeigt den Pfad an.
   Darin steht jeder Treffer, jede Heilung, jeder Fress-Kanal, jeder Tod mit Ursache und jedes Try-Ende. Ich rechne den Abend damit nach:
   ```
   lua tools/log_lesen.lua <pfad-zur-jsonl>
   ```
   Das Werkzeug sagt dir dieselben Dinge auch selbst — Siegquote, Trylängen, ob das Fressen unterbrochen wurde, woran gestorben wurde, und welcher Regler dran wäre.
2. **`tuning.csv`**, falls du im Panel etwas verstellt hast.
3. **`session.json` brauche ich nicht** — darin stehen nur XP, Kupfer, Plunder und der Try-Zähler.

## Was ich vor jeder Änderung selbst laufen lasse

```
lua sim/main.lua --quick --jobs 10
```
Seit Runde 20 heißt das `lua sim/main.lua --engine spiel --quick --jobs 10`: die echte Spielsimulation mit den Bots als typischem Raid, 16 Zellen, alle acht Kriterien (F1–F7 und Turtle), 50 Läufe je Zelle, rund sieben Minuten, ±14 Prozentpunkte je Quote — das ist ein Richtungstest, kein Feinmaß. Der Nachweis mit 100 Läufen (±10 pp) kostet rund 14 Minuten und läuft nur, wenn du ihn willst — siehe `docs/adr/004-richtungstest-statt-vollmatrix.md` und ADR 006.
