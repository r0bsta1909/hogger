-- game/gamesim/lines.lua — Leeroys Zeilen-Pool (GDD 10.4).
-- IDs sind stabil (Log: leeroy_line, dst = Zeilen-ID). Kontextgruppen
-- werden vom Announcer gewaehlt; ~30 Zeilen, Erweiterung nur hier.

return {
  -- 1: DER Schrei (Try-Start, einzige Voice-Line spaeter)
  [1] = "LEEEEEROY JEEENKINNNS!",
  -- 2-6: Fressen
  [2] = "ER FRISST SCHON WIEDER! MACHT WAS!",
  [3] = "Der Gnoll macht Brotzeit. UNTERBRECHEN!",
  [4] = "Nicht zugucken! SCHLAGT IHN!",
  [5] = "Er kaut. ER KAUT UNS AUS DEM TRY!",
  [6] = "Mahlzeit. Grossartig. Einfach grossartig.",
  -- 7-10: HP-Meilensteine 75/50/25/10
  [7] = "75 Prozent! Weiter so, ihr Helden!",
  [8] = "HALBZEIT! Der Koeter wackelt!",
  [9] = "25 PROZENT! ICH RIECHE DEN SIEG!",
  [10] = "ZEHN PROZENT! GLEICH! GLEICH! GLEICH!",
  -- 11-20: Spielertode (stichprobenartig, kontextsensitiv)
  [11] = "Autsch. Das sah teuer aus.",
  [12] = "Charge-Opfer Nummer soundso. Klassiker.",
  [13] = "Kritisch zerschmettert. Respekt vor der Physik.",
  [14] = "Von einem WOLF? Waehrend DER da steht?",
  [15] = "Der Heiler hat geheilt. Deshalb ist er jetzt tot.",
  [16] = "... zum wiederholten Male. Ich zaehle nicht mehr mit.",
  [17] = "Steh auf, es sieht albern aus.",
  [18] = "Ein Wildschwein. Ein WILDSCHWEIN.",
  [19] = "Wer heilt eigentlich MICH?",
  [20] = "Elegant gestorben. Fast schon Absicht.",
  -- 21-24: Try-Ende
  [21] = "Okay. Das war nichts. Naechster Try.",
  [22] = "Wipe. Ueberraschung. Aufstehen, weitermachen.",
  [23] = "Er hatte noch Restleben. Ich sage nur: Restleben.",
  [24] = "Das haben wir gleich. Definitiv. Vermutlich.",
  -- 25: Kragen-Mechanik (Sicherheitsnetz, GDD 10.4; Wortlaut neu seit
  -- Runde 12, #140 — unterbrechen kann nur noch der Schurken-Tritt)
  [25] = "EIN SCHURKE MUSS IHN TRETEN, WAEHREND ER FRISST!",
  -- 26-28: Zwischen-Zeilen am Friedhof
  [26] = "Der Geistheiler? Der funktioniert nicht mehr. Frag nicht.",
  [27] = "Frueher war hier mehr Raid. Und weniger Vollpfosten.",
  [28] = "Warum ist hier eigentlich alles so ... flach?",
  -- 29-30: Besonderes
  [29] = "DING? ... das ist nicht moeglich.",
  [30] = "Zeit haben wir. Ewig, genau genommen.",
  -- 31-35: Der letzte Monolog nach dem Fluchbruch (GDD 11), zeitversetzt aus
  -- step.lua. Gesprochen wird er von der verschmolzenen Figur — Koerper und
  -- Echo sind in diesem Moment wieder eins. Zeile 35 bricht mitten im Wort
  -- ab: er loggt aus, waehrend er es ausspricht.
  [31] = "Wir... wir haben es geschafft.",
  [32] = "Der Fluch ist gebrochen. Ich spuere meine Haende wieder.",
  [33] = "Ich kann wieder die Escape-Taste druecken!",
  [34] = "ENDLICH. BIN. ICH. FREI!",
  [35] = "Moment. Haette ich vielleicht auch all die Zeit mit ALT+F...",
}
