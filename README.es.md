# Neon Grid Defense

[English](README.md) | [Español](README.es.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

**Neon Grid Defense** es un juego táctico de Tower Defense en 3D con rutas fijas desarrollado en **Godot 4.3+ (`GL Compatibility`)**, con cámara táctica frontal a 58°, texturas PBR procedurales, 20 niveles de campaña y 7 idiomas.

* **Demo Web en vivo:** [https://o1egkl.github.io/neon-grid-defense/](https://o1egkl.github.io/neon-grid-defense/)

## Características Principales
* **20 Niveles de Campaña:** Rutas enemigas fijas predefinidas (1 a 4 portales), muros y casillas Boost (`+20%` de daño).
* **6 Torres con 5 Niveles de Mejora Lineal:** Pulse, Cannon, Cryo, Tesla, Laser y Railgun (`+20%` por nivel hasta Nv. 5 Overdrive, reembolso del `75%` al vender).
* **7 Enemigos 3D Animados:** Swarm, Trooper, Tanque Blindado, Escudado, Médico, Splitter y Dron Aéreo.
* **Construcción en 2 Clics y Control Seguro:** El primer clic muestra una vista previa 3D orientada al camino más cercano y su alcance; el segundo clic confirma la construcción. El clic derecho cancela o cierra el inspector (la venta solo se hace desde el menú del inspector).
* **Zoom y Paneo (PC y Android):** Rueda del ratón / pellizco con 2 dedos, paneo con botón central / WASD / 2 dedos, `0` para restablecer la cámara.
* **7 Idiomas:** English, Español, Русский, Português, Français, Deutsch, Italiano.

## Estructura del Proyecto
* `scenes/main.tscn` — Escena principal 3D.
* `scripts/grid_manager.gd` — Cámara frontal 58°, tablero PBR, rutas Bezier, combate y mejoras visuales.
* `scripts/ui_controller.gd` — HUD en colores, tienda inferior, barra de confirmación, inspector de torres y menús.
* `scripts/main.gd`, `scripts/settings_manager.gd`, `scripts/sfx_player.gd` — Lógica principal, idiomas y audio procedural.
* `data/` — Configuraciones JSON de torres, enemigos, localización y 20 niveles (`data/levels/`).
* `assets/textures/`, `assets/sprites/` — Texturas PBR e iconos de interfaz.
* `play_windows.bat` / `build_windows.bat` — Scripts locales para Windows con rutas relativas.
* `.github/workflows/release.yml` — Compilación automática para Web, Windows, Linux, macOS y Android.

## Inicio Rápido (Rutas Relativas)
Ejecutar desde la carpeta raíz del repositorio:

```bash
godot --headless --path . --import --quit
godot --path .
```

En Windows (desde la raíz del repositorio):
```bat
.\play_windows.bat
```
