# Hogger muss sterben

LÖVE2D-LAN-Koop-Zerg für 5–40 Spieler. Ein verfluchter Leeroy Jenkins, ein unbesiegbarer Gnoll,
und das ganze Spiel ist eine bildschirmfüllende WoW-Minimap. Privates Spaßprojekt.

- **Design:** `docs/gdd.md` (einzige Design-Wahrheit)
- **Arbeitsanweisung für Claude Code:** `CLAUDE.md`
- **Netcode-Learnings (Pflichtlektüre):** `docs/skills/love2d-lan-game.md`
- **Referenzbilder:** `docs/referenzen/`

**Start (M2-Debug):** Host: `love game --name rob` · Mitspielen: `love game --join <host-ip> --name gast`
· Solo mit Bots: `love game --bots 4` · Steuerung: WASD/Pfeile, Leertaste springen, 1/2 Fähigkeiten,
Klick/Tab Ziel, Mausrad/+/- Zoom, F10 Tuning-Panel (Host)

Sim: `lua sim/main.lua --n 10 --runs 1000` · Tests: `lua tests/run_all.lua` ·
Integration: `love game --headless --test`
