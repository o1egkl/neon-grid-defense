# Neon Grid Defense

[English](README.md) | [Español](README.es.md) | [Русский](README.ru.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

**Neon Grid Defense** é um jogo tático de Tower Defense em 3D com rotas fixas desenvolvido em **Godot 4.3+ (`GL Compatibility`)**, com câmera tática frontal de 58°, texturas PBR procedurais, 20 níveis de campanha e 7 idiomas.

* **Demo Web ao vivo:** [https://o1egkl.github.io/neon-grid-defense/](https://o1egkl.github.io/neon-grid-defense/)

## Principais Recursos
* **20 Níveis de Campanha:** Rotas fixas pré-desenhadas (1 a 4 portais), paredes e células Boost (`+20%` de dano).
* **6 Torres com 5 Níveis de Melhoria Linear:** Pulse, Cannon, Cryo, Tesla, Laser e Railgun (`+20%` por nível até Nv. 5 Overdrive, reembolso de `75%` na venda).
* **7 Inimigos 3D Animados:** Swarm, Trooper, Tanque Blindado, Escudado, Médico, Splitter e Drone Aéreo.
* **Construção em 2 Cliques:** O 1º clique exibe uma prévia 3D apontada para a estrada mais próxima e seu alcance; o 2º clique confirma. O botão direito apenas cancela a prévia ou fecha o inspetor (venda apenas pelo menu do inspetor).
* **Zoom e Panorâmica (PC e Android):** Roda do mouse / pinça com 2 dedos, movimento com botão do meio / WASD / 2 dedos, `0` para redefinir a câmera.

## Estrutura do Projeto
* `scenes/main.tscn` — Cena principal 3D.
* `scripts/grid_manager.gd`, `scripts/ui_controller.gd`, `scripts/main.gd`, `scripts/settings_manager.gd`, `scripts/sfx_player.gd` — Lógica 3D, UI, economia e áudio.
* `data/` — JSONs de torres, inimigos, traduções e 20 níveis (`data/levels/`).
* `assets/textures/`, `assets/sprites/` — Texturas PBR e ícones.
* `play_windows.bat` / `build_windows.bat` — Scripts Windows com caminhos relativos.
* `.github/workflows/release.yml` — CI/CD para Web, Windows, Linux, macOS e Android.

## Início Rápido (Caminhos Relativos)
Execute na pasta raiz do repositório:

```bash
godot --headless --path . --import --quit
godot --path .
```

No Windows (na raiz do repositório):
```bat
.\play_windows.bat
```
