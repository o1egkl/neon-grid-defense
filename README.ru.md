# Neon Grid Defense

[English](README.md) | [Español](README.es.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

**Neon Grid Defense** — тактическая 3D-игра в жанре Tower Defense с фиксированными маршрутами на движке **Godot 4.3+ (`GL Compatibility`)**, фронтальной 58° тактической камерой, процедурными PBR-текстурами, 20 уровнями кампании и поддержкой 7 языков.

* **Онлайн-демо (Web):** [https://o1egkl.github.io/neon-grid-defense/](https://o1egkl.github.io/neon-grid-defense/)

## Основные возможности
* **20 уровней кампании:** фиксированные маршруты врагов (от 1 до 4 спавн-порталов), стены и Boost-клетки (`+20%` к урону).
* **6 типов башен с линейным апгрейдом до 5 уровней:** Pulse, Cannon, Cryo, Tesla, Laser и Railgun (`+20%` к параметрам за уровень + Overdrive на 5 уровне, возврат `75%` кредитов при продаже).
* **7 анимированных 3D-типов врагов:** Swarm, Trooper, Armored Tank, Shielded, Medic, Splitter и Flyer Drone.
* **Установка в 2 клика и безопасное управление:** 1-й клик/тап показывает 3D-призрак башни (развёрнутой к ближайшей дороге) и её радиус; 2-й клик подтверждает постройку. Правый клик отменяет предпросмотр или закрывает инспектор (продажа — только через кнопку в инспекторе).
* **Зум и навигация (ПК и Android):** колесо мыши / щипок двумя пальцами, перемещение СКМ / WASD / двумя пальцами, клавиша `0` для сброса камеры.
* **7 языков:** English, Español, Русский, Português, Français, Deutsch, Italiano.

## Структура проекта
* `scenes/main.tscn` — основная 3D-сцена.
* `scripts/grid_manager.gd` — фронтальная 58° камера, PBR-доска, Bezier-маршруты, боёвка и визуал апгрейдов.
* `scripts/ui_controller.gd` — цветной HUD, нижний магазин башен, плашка подтверждения, инспектор башни и настройки.
* `scripts/main.gd`, `scripts/settings_manager.gd`, `scripts/sfx_player.gd` — игровой цикл, локализация и процедурный звук.
* `data/` — JSON-конфиги башен, врагов, локализации и 20 уровней (`data/levels/`).
* `assets/textures/`, `assets/sprites/` — процедурные PBR-текстуры и иконки UI.
* `play_windows.bat` / `build_windows.bat` — скрипты запуска и сборки для Windows с относительными путями.
* `.github/workflows/release.yml` — CI/CD для Web (GitHub Pages), Windows, Linux, macOS и Android.

## Быстрый запуск (относительные пути)
Выполняйте команды из корневой папки репозитория:

```bash
godot --headless --path . --import --quit
godot --path .
```

На Windows (из корня репозитория):
```bat
.\play_windows.bat
```
Для сборки автономного `.exe` (`builds/windows/NeonGridDefense.exe`):
```bat
.\build_windows.bat
```
