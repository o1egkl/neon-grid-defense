# Neon Grid Defense

[English](README.md) | [Español](README.es.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

**Neon Grid Defense** est un jeu de Tower Defense tactique en 3D à trajectoires fixes conçu avec **Godot 4.3+ (`GL Compatibility`)**, doté d'une caméra tactique frontale à 58°, de textures PBR procédurales, de 20 niveaux et de 7 langues.

* **Démo Web en ligne :** [https://o1egkl.github.io/neon-grid-defense/](https://o1egkl.github.io/neon-grid-defense/)

## Fonctionnalités Clés
* **20 Niveaux de Campagne :** Routes fixes prédéfinies (1 à 4 portails), murs et dalles Boost (`+20%` de dégâts).
* **6 Tourelles avec 5 Niveaux d'Amélioration Linéaire :** Pulse, Cannon, Cryo, Tesla, Laser et Railgun (`+20%` par niveau jusqu'au Niv. 5 Overdrive, remboursement de `75%` à la vente).
* **7 Ennemis 3D Animés :** Swarm, Trooper, Char Blindé, Bouclier, Médecin, Splitter et Drone Aérien.
* **Construction en 2 Clics :** Le 1er clic affiche un aperçu 3D orienté vers la route la plus proche avec sa portée ; le 2e clic confirme. Le clic droit annule l'aperçu ou ferme l'inspecteur (vente uniquement via le menu inspecteur).
* **Zoom et Déplacement (PC et Android) :** Molette / pincement à 2 doigts, déplacement clic molette / WASD / 2 doigts, `0` pour réinitialiser la caméra.

## Structure du Projet
* `scenes/main.tscn` — Scène 3D principale.
* `scripts/grid_manager.gd`, `scripts/ui_controller.gd`, `scripts/main.gd`, `scripts/settings_manager.gd`, `scripts/sfx_player.gd` — Moteur 3D, interface, économie et audio.
* `data/` — Données JSON des tourelles, ennemis, traductions et 20 niveaux (`data/levels/`).
* `assets/textures/`, `assets/sprites/` — Textures PBR et icônes.
* `play_windows.bat` / `build_windows.bat` — Scripts Windows à chemins relatifs.
* `.github/workflows/release.yml` — CI/CD pour Web, Windows, Linux, macOS et Android.

## Démarrage Rapide (Chemins Relatifs)
Exécutez depuis la racine du dépôt :

```bash
godot --headless --path . --import --quit
godot --path .
```

Sous Windows (depuis la racine du dépôt) :
```bat
.\play_windows.bat
```
