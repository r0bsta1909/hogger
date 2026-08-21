# ADR 005: Der Enrage — die Frist bekommt ein Gesicht, aber kein Byte

**Status:** akzeptiert (Rob, 21.08.2026, Runde 18)

## Kontext

Seit Runde 17 endet ein Try nach 16 Minuten, und das Zeitlimit ist nicht bloß eine Notbremse: **es ist die eigentliche Schwierigkeit des Spiels.** Ohne es steigt die koordinierte Siegquote auf 99–100 % gegen ein Zielband von 60–90 % (Messung in GDD 17.9, Runde 17).

Nur war es **undiegetisch und unsichtbar**: eine Uhr lief ab, der Try war vorbei, der Grund stand ausschließlich auf einer Tafel. Genau daran ist Rob in Runde 17 hängengeblieben — er stand neben einem lebenden Hogger, sein Raid schlug bis zur letzten Sekunde zu, und er hielt das Ende für einen Reset. Runde 17 hat die Beschriftung repariert; die Ursache — dass **nichts passiert**, wenn die Frist abläuft — blieb.

Robs Entscheid: Hogger langweilt sich. Er sagt es, eine Schockwelle geht über die Karte und löscht den Raid aus, dann steht er wieder auf seinem Hügel.

## Entscheidung

**1. Die Sequenz läuft in der Simulation, nicht im Client.** Neue Phase `state.phase = "enrage"` mit eigener Zeitachse `enrage_t`, gebaut nach dem Vorbild der Fluchbruch-Sequenz (`won_t` / `won_stage`, GDD 11). Die Welt friert ein wie dort; getötet wird nach Entfernung zur Welle.

**2. Sie kostet null Byte im Snapshot.** `state.clock` läuft während der Phase weiter, und der Client leitet seine Zeitachse aus `clock − try_time_limit` ab. Er kennt die Frist ohnehin, er zeichnet die Restzeit daraus.

**3. Die Sequenzzeiten sind lokale Konstanten, keine `model.params`.** 1,6 s bis zur Welle, 2.200 Welt-px/s, 3,8 s Gesamtdauer. Sie sind Inszenierung, kein Stellhebel — genau wie `SHATTER_T` und `LOOT_T` des Fluchbruchs.

**4. Der Grund im Log bleibt `timeout`.** Die Uhr ist die Ursache, der Enrage ist, was man davon sieht. Tafel und Log-Leser zeigen „Enrage", das Protokollfeld nicht.

**5. Die Tode sind echt** (Rob-Entscheid): Freigabe-Panel, Geist, Friedhof, Rückweg. Ein abgelaufener Try kostet den Raid damit zusätzlich den vollen Anmarsch.

## Verworfene Alternativen

**Das Phasen-Byte des Snapshots mitbenutzen (Wert 5 für Enrage).** Naheliegend, weil das Byte nur 0–4 nutzt — und **falsch**: `wire.lua` setzt beim Auspacken `s.won_stage = phase`, und vier Stellen im Client lesen daraus „der Fluchbruch läuft" (`main.lua` zweimal, `names.lua`, `gamemenu.lua`). Ein Wert 5 hätte das ESC-Spielmenü geöffnet, Leeroys Namen geheilt und nach dem nächsten Tick das Spiel beendet. Das Byte ist nicht frei, es ist nur nicht ausgereizt.

**Ein neues Feld im Snapshot** (etwa eines der beiden toten Bytes im Hogger-Datensatz). Hätte funktioniert, wäre aber unnötig gewesen: die Uhr trägt die Information schon. Bei Issue #202 — der Snapshot liegt bei N=40 mit Leichen bereits über der ENet-MTU — ist „kostet nichts" ein Argument, kein Nebensatz.

**Die Sequenz rein im Client abspielen**, ausgelöst vom `try_end`-Ereignis. Am billigsten, aber es wäre eine zweite Zeitbasis neben der Simulation gewesen — genau das, was ADR 001 ausschließt, und die Lehre aus dem klickgebundenen Loot-Fenster (GDD 11, Runde 11): Was nicht die Sim taktet, driftet zwischen vierzig Rechnern auseinander.

**Kein Zeitlimit, dafür „Hogger wieder bei 100 % HP ⇒ Try gescheitert"** (Runde 17 vorgeschlagen und von Rob wie von mir zunächst angenommen). Am Code widerlegt, bevor sie gebaut wurde: Fressen ist Hoggers einzige Heilquelle und **unter 90 % gesperrt** — zwischen 90 und 100 % kann er gar nicht heilen, ein Kanal ab 85 % endet bei 97 % und bleibt dort stehen. Im Turtle-Fall pendelt er endlos. Die Regel konvergiert nicht.

## Revisionsauslöser

- **Die Abendstatistik wird unbrauchbar.** Jeder abgelaufene Try gibt jedem Spieler +1 Tod; `p.deaths` persistiert über Trys. Die Rangfolge „Am häufigsten gestorben" bleibt fair (alle bekommen gleich viel), aber die absolute Zahl misst ab jetzt auch die Uhr. Wenn Rob sie im Log-Bericht nicht mehr lesen kann, gehören die Enrage-Tode aus der Wertung genommen.
- **Der Rückweg wird als Strafe empfunden.** Nach jedem abgelaufenen Try marschiert der ganze Raid neu an. Fühlt sich das nach Bestrafung statt nach Konsequenz an, ist der Hebel: die Enrage-Tode zu Bildern machen (kein `dead_until`) statt zu echten Toden.
- **Der Snapshot bricht.** Gemessen liegt der Enrage-Moment bei N=40 (40 Leichen, sechs Beutestücke) bei **1.412 B gegen 1.400 B MTU** — zwölf Byte darüber. Er ist damit nicht die Ursache von #202, aber sein schärfster Zeuge: bei N=40 reißt die MTU bereits bei rund 37 Leichen, also nach etwa einem Tod pro Spieler. Wird #202 gelöst (Delta-Kompression oder Aufteilung), ist dieser Wert die Probe.
- **Die Frist ändert sich.** `try_time_limit` ist im F10-Panel verstellbar. Die Sequenz hängt daran, nicht an 960 — aber die Balance-Aussage aus Runde 17 (16 Minuten mit `hogger_hp_slope` 640) gilt nur für diesen Wert.

## Folgen für die Tests

Der Determinismus-Hash ändert sich (neue Phase, verschobene Ticks). `tests/determinism.lua` vergleicht relativ und bleibt grün — das ist kein Regressionsfund. Der Ansager zieht im Timeout-Zweig weiterhin **genau einen** Zufallswert, sonst verschöbe sich der Krit- und Loot-Strom des ganzen Abends gegenüber Runde 17.
