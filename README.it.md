# Neon Grid Defense

[English](README.md) | [Español](README.es.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

**Neon Grid Defense** è un gioco tattico Tower Defense in 3D a percorsi fissi realizzato con **Godot 4.3+ (`GL Compatibility`)**, con telecamera tattica frontale a 58°, texture PBR procedurali, 20 livelli campagna e 7 lingue.

* **Demo Web dal vivo:** [https://o1egkl.github.io/neon-grid-defense/](https://o1egkl.github.io/neon-grid-defense/)

## Caratteristiche Principali
* **20 Livelli Campagna:** Percorsi nemici fissi predefiniti (da 1 a 4 portali), muri e caselle Boost (`+20%` danno).
* **6 Torri con 5 Livelli di Potenziamento Lineare:** Pulse, Cannon, Cryo, Tesla, Laser e Railgun (`+20%` per livello fino al Lv. 5 Overdrive, rimborso del `75%` alla vendita).
* **7 Nemici 3D Animati:** Swarm, Trooper, Carro Armato, Scudato, Medico, Splitter e Drone Aereo.
* **Costruzione in 2 Clic e Controllo Sicuro:** Il 1° clic mostra un'anteprima 3D orientata verso la strada più vicina con il raggio d'azione; il 2° clic costruisce. Il tasto destro annulla o chiude l'ispettore (vendita solo dal menu ispettore).
* **Zoom e Panoramica (PC e Android):** Rotellina / pizzico a 2 dita, spostamento tasto centrale / WASD / 2 dita, `0` per reimpostare la telecamera.

## Struttura del Progetto
* `scenes/main.tscn` — Scena 3D principale.
* `scripts/grid_manager.gd`, `scripts/ui_controller.gd`, `scripts/main.gd`, `scripts/settings_manager.gd`, `scripts/sfx_player.gd` — Logica 3D, UI, economia e audio.
* `data/` — File JSON di torri, nemici, localizzazione e 20 livelli (`data/levels/`).
* `assets/textures/`, `assets/sprites/` — Texture PBR procedurali e icone UI.
* `play_windows.bat` / `build_windows.bat` — Script Windows con percorsi relativi.
* `.github/workflows/release.yml` — CI/CD per Web, Windows, Linux, macOS e Android.

## Avvio Rapido (Percorsi Relativi)
Eseguire dalla cartella principale del repository:

```bash
godot --headless --path . --import --quit
godot --path .
```

Su Windows (dalla radice del repository):
```bat
.\play_windows.bat
```
