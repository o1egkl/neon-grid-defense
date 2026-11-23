# Neon Grid Defense

Тактическая игра Tower Defense с механикой **mazing** (построения лабиринта на открытой сетке) на базе **Godot 4.3+**.

## Структура проекта
* `scenes/main.tscn` — основная игровая сцена с сеткой и базовым HUD.
* `scripts/pathfinding_service.gd` — обёртка над `AStarGrid2D` с проверкой блокировки пути и предпросмотром маршрута.
* `scripts/grid_manager.gd` — управление сеткой, загрузка уровней из JSON, отрисовка стен, зон запрета строительства (`no_build_zones`), площадок усиления (`boost_tiles`) и линий маршрута для нескольких спавнов.
* `scripts/main.gd` — переключение уровней (`[` / `]` или `PageUp` / `PageDown`) и обновление HUD.
* `data/towers.json`, `data/enemies.json` — конфигурации 6 башен и 7 архетипов врагов.
* `data/levels/level_01.json` .. `level_20.json` + `campaign.json` — 20 уровней кампании с прогрессией волн, боссами, воздушными рейдами и валидированными маршрутами.
* `play_windows.bat` — подтягивает свежий код (`git pull`) и сразу запускает игру на Windows.
* `build_windows.bat` — подтягивает свежий код (`git pull`), пересобирает автономный `builds\windows\NeonGridDefense.exe` и запускает его.
* `docs/TZ_Grid_Defense_TD.md` — техническое задание и дизайн-документ.
* `.github/workflows/release.yml` — CI/CD для автосборки Web, Windows, Linux, macOS и Android.

## Быстрый старт на GitHub (PowerShell)
```powershell
Expand-Archive -Path "D:\downloads\neon-grid-defense-repo-all-platforms.zip" -DestinationPath ".\neon-grid-defense" -Force
Set-Location .\neon-grid-defense
git init -b main
git add .
git commit -m "feat: Neon Grid Defense with 20 levels, CI/CD, and Windows batch scripts"
git remote add origin https://github.com/<USERNAME>/neon-grid-defense.git
git push -u origin main
```
* Включите **Settings → Pages → Source: GitHub Actions** для автопубликации Web-версии при пуше в `main`.
* Для выпуска релиза под все 5 платформ отправьте тег: `git tag v0.1.0; git push origin v0.1.0`.
