# Neon Grid Defense

[English](README.md) | [Español](README.es.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

**Neon Grid Defense** ist ein taktisches 3D-Tower-Defense-Spiel mit festen Pfaden auf Basis von **Godot 4.3+ (`GL Compatibility`)**, mit einer frontalen 58°-Taktikkamera, prozeduralen PBR-Texturen, 20 Kampagnen-Leveln und 7 Sprachen.

* **Live-Web-Demo:** [https://o1egkl.github.io/neon-grid-defense/](https://o1egkl.github.io/neon-grid-defense/)

## Hauptmerkmale
* **20 Kampagnen-Level:** Vorgefertigte feste Gegnerrouten (1 bis 4 Portale), Mauern und Boost-Felder (`+20%` Schaden).
* **6 Türme mit 5 linearen Upgrade-Stufen:** Pulse, Cannon, Cryo, Tesla, Laser und Railgun (`+20%` pro Stufe bis Lv. 5 Overdrive, `75%` Rückerstattung beim Verkauf).
* **7 animierte 3D-Gegnertypen:** Swarm, Trooper, Panzer, Schildträger, Sanitäter, Splitter und Flugdrohne.
* **2-Klick-Bau & sichere Steuerung:** Der 1. Klick zeigt eine 3D-Vorschau Richtung nächster Straße inklusive Reichweite; der 2. Klick baut den Turm. Rechtsklick bricht ab oder schließt den Inspektor (Verkauf nur über das Inspektor-Menü).
* **Zoom & Kamera (PC & Android):** Mausrad / 2-Finger-Zoom, Schwenken per mittlerer Maustaste / WASD / 2 Fingern, `0` zum Zurücksetzen.

## Projektstruktur
* `scenes/main.tscn` — Haupt-3D-Szene.
* `scripts/grid_manager.gd`, `scripts/ui_controller.gd`, `scripts/main.gd`, `scripts/settings_manager.gd`, `scripts/sfx_player.gd` — 3D-Logik, UI, Ökonomie und Audio.
* `data/` — JSON-Konfigurationen für Türme, Gegner, Übersetzungen und 20 Level (`data/levels/`).
* `assets/textures/`, `assets/sprites/` — Prozedurale PBR-Texturen und UI-Icons.
* `play_windows.bat` / `build_windows.bat` — Windows-Skripte mit relativen Pfaden.
* `.github/workflows/release.yml` — CI/CD für Web, Windows, Linux, macOS und Android.

## Schnellstart (Relative Pfade)
Im Stammverzeichnis des Repositories ausführen:

```bash
godot --headless --path . --import --quit
godot --path .
```

Unter Windows (im Stammverzeichnis des Repositories):
```bat
.\play_windows.bat
```
