# Neon Grid Defense

[English](README.md) | [Español](README.es.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

**Neon Grid Defense** is a 3D tactical fixed-path Tower Defense game built with **Godot 4.3+ (`GL Compatibility`)**, featuring a frontal 58° tactical camera, procedural PBR textures, 20 campaign levels, and 7 in-game languages.

* **Live Web Demo:** [https://o1egkl.github.io/neon-grid-defense/](https://o1egkl.github.io/neon-grid-defense/)

## Key Features
* **20 Campaign Levels:** Fixed pre-designed enemy routes (1 to 4 spawn gates), obstacle walls, and `+20%` damage Boost pads.
* **6 Towers with 5-Level Linear Upgrades:** Pulse, Cannon, Cryo, Tesla, Laser, and Railgun (`+20%` stats per level up to Lv. 5 Overdrive, `75%` credit refund on sell).
* **7 Animated 3D Enemy Types:** Swarm, Trooper, Armored Tank, Shielded, Medic, Splitter, and Flying Drone.
* **2-Click Ghost Placement & Safe Controls:** First click previews the 3D tower aimed toward the nearest road and shows its attack range; second click confirms build. Right-click cancels preview or closes the inspector (selling is only via the Inspector menu).
* **Desktop & Android Camera Controls:** Mouse wheel / pinch-to-zoom, MMB / WASD / two-finger pan, `0` to reset camera.
* **7 Languages:** English, Español, Русский, Português, Français, Deutsch, Italiano.

## Project Structure
* `scenes/main.tscn` — Main 3D game scene.
* `scripts/grid_manager.gd` — Frontal 58° 3D camera, PBR board, Bezier-smoothed routes, combat, and 5-level upgrade visuals.
* `scripts/ui_controller.gd` — Colored HUD, bottom tower shop, 2-click build bar, tower inspector, and settings/guide overlays.
* `scripts/main.gd` — Game loop, economy, wave & level management.
* `scripts/settings_manager.gd` — Persistent settings and 7-language localization.
* `scripts/sfx_player.gd` — Procedural synthesized sound effects.
* `data/towers.json`, `data/enemies.json`, `data/localization.json` — Tower, enemy, and localization data.
* `data/levels/level_01.json` .. `level_20.json` + `campaign.json` — 20 campaign levels.
* `assets/textures/`, `assets/sprites/` — Procedural PBR textures and 2.5D UI icons.
* `play_windows.bat` / `build_windows.bat` — Relative-path Windows helper scripts.
* `.github/workflows/release.yml` — CI/CD for Web (GitHub Pages), Windows, Linux, macOS, and Android.

## Quick Start (Relative Paths)
Run from the repository root directory:

```bash
# Import assets and launch with Godot 4.3+
godot --headless --path . --import --quit
godot --path .
```

On Windows (from the repository root):
```bat
.\play_windows.bat
```
To build a standalone Windows executable (`builds/windows/NeonGridDefense.exe`):
```bat
.\build_windows.bat
```

## CI/CD & Releases
* Enable **Settings -> Pages -> Source: GitHub Actions** to auto-publish the Web build on push to `main`.
* Tag a release to build all 5 platforms (Web, Windows, Linux, macOS, Android):
```bash
git tag v0.1.0 && git push origin v0.1.0
```
