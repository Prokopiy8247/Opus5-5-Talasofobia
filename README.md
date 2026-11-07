# Opus 5.5 · Талассофобия / Thalassophobia

**[🇷🇺 Русский](#-русский)** · **[🇬🇧 English](#-english)**

---

<a name="-русский"></a>
## 🇷🇺 Русский

Три короткие игры от первого лица про **талассофобию**: страх глубокой воды и огромных вещей под водой.
Каждую игру целиком сделала нейросеть **Claude Opus 5.5** (мышление Extra High, режим Ultracode) на движке **Godot 4.7.2**
по большому мастер-промпту. Здесь можно скачать готовые игры и посмотреть исходники.

### Игры

| Папка | Игра | О чём | Длительность |
|---|---|---|---|
| [`1-NADIR`](1-NADIR/) | **NADIR** | Реалистичный спуск по канату от лодки на поверхности до дна океанской впадины: чёрная вода, борт невозможно огромного затонувшего корабля, монстр Bloop | ≈ 9 мин (≈ 5 мин в автопилоте) |
| [`2-PELAGIC`](2-PELAGIC/) | **PELAGIC** | Яркий открытый океан: подводная скала, край обрыва над бездонной синевой и гигантский змей SCP-3000 | ≈ 9 мин (≈ 5 мин в автопилоте) |
| [`3-THE-DROWNED`](3-THE-DROWNED/) | **THE DROWNED** | Спуск в кладбище гигантов: затонувшие корабли растущего размера, лес подводных лодок, безликая статуя, стена-корпус | ≈ 9 мин (≈ 5 мин в автопилоте) |

В играх нет боёв, интерфейса и головоломок. Это путешествие, которое нужно просто смотреть.

### Как запустить (коротко)

Каждая игра запускается **одним файлом `.exe`**. Скачай его на странице
[**Releases**](https://github.com/Prokopiy8247/Opus5-5-Talasofobia/releases/latest) и дважды нажми.
Подробная инструкция «для чайников», шаг за шагом, с решением проблем:
**[HOW_TO_RUN.ru.md](HOW_TO_RUN.ru.md)**

Управление: мышь — смотреть, **W / S** — плыть, **Shift** — быстрее, **C** — автопилот, **Esc** — пауза, **F11** — полный экран.

### Что лежит в репозитории

```
Opus5-5-Talasofobia/
├── README.md                      ← этот файл (RU + EN)
├── HOW_TO_RUN.ru.md               ← как запустить игры (RU)
├── HOW_TO_RUN.md                  ← how to run the games (EN)
├── Blender_MCP_Guide_RU.pdf       ← гайд: как подключить Blender к нейросети (RU)
├── Blender_MCP_Guide_EN.pdf       ← guide: connecting Blender to an AI agent (EN)
├── 1-NADIR/                       ← проект Godot, игра 1
├── 2-PELAGIC/                     ← проект Godot, игра 2
└── 3-THE-DROWNED/                 ← проект Godot, игра 3
```

### Гайд: как подключить Blender к нейросети

Короткий пошаговый гайд по подключению **Blender MCP** к Claude Code или Codex (на примере Unity-проекта; тот же порядок
работает и для других движков):
[Blender_MCP_Guide_RU.pdf](Blender_MCP_Guide_RU.pdf) · [Blender_MCP_Guide_EN.pdf](Blender_MCP_Guide_EN.pdf)

### Как это сделано

- Каждая игра делалась отдельным агентом **Claude Opus 5.5** (Extra High, Ultracode) по одному мастер-промпту.
- Всё, кроме главного существа, **создано кодом**: геометрия, шейдеры, текстуры и звук (звук синтезирован скриптами).
- Главные существа (Bloop и SCP-3000) сгенерированы отдельно: картинка нейросетью, затем 3D-модель в Tripo, затем модель
  дорабатывал сам агент (геометрия, текстуры, шейдеры, анимация плавания).
- Промпты и сопутствующие материалы публикуются в Telegram-канале автора (ссылка в описании видео).

### Благодарности и авторские права

- Существо в PELAGIC основано на **SCP-3000 «Ананташеша»** (авторы: A Random Day, djkaktus, Joreth), SCP Foundation Wiki,
  лицензия [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/): <https://scp-wiki.wikidot.com/scp-3000>.
- «Bloop» в NADIR — вымышленное существо по мотивам загадочного звука «Bloop», записанного в 1997 году (по версии NOAA это был
  треск льда): <https://oceanservice.noaa.gov/facts/bloop.html>.
- Игры сделаны на **Godot Engine** (лицензия MIT): <https://godotengine.org>.

---

<a name="-english"></a>
## 🇬🇧 English

Three short first-person games about **thalassophobia**: the fear of deep water and of huge things under it.
Each game was made entirely by the AI **Claude Opus 5.5** (Extra High thinking, Ultracode mode) in the **Godot 4.7.2** engine
from a big master prompt. Here you can download the finished games and read the source.

### The games

| Folder | Game | What it is | Length |
|---|---|---|---|
| [`1-NADIR`](1-NADIR/) | **NADIR** | A realistic descent along a rope from a boat on the surface to the floor of an ocean trench: black water, the side of an impossibly large sunken ship, the monster Bloop | ≈ 9 min (≈ 5 min on autopilot) |
| [`2-PELAGIC`](2-PELAGIC/) | **PELAGIC** | A bright open ocean: an underwater cliff, the edge over bottomless blue, and the giant serpent SCP-3000 | ≈ 9 min (≈ 5 min on autopilot) |
| [`3-THE-DROWNED`](3-THE-DROWNED/) | **THE DROWNED** | A descent into a graveyard of giants: sunken ships of growing size, a forest of submarines, a faceless statue, a wall of hull | ≈ 9 min (≈ 5 min on autopilot) |

There is no combat, no HUD and no puzzles. It is a journey you simply watch.

### How to run (short)

Each game starts from **one single `.exe` file**. Download it on the
[**Releases**](https://github.com/Prokopiy8247/Opus5-5-Talasofobia/releases/latest) page and double-click it.
A detailed idiot-proof guide with every step and fixes for problems:
**[HOW_TO_RUN.md](HOW_TO_RUN.md)**

Controls: mouse — look, **W / S** — swim, **Shift** — faster, **C** — autopilot, **Esc** — pause, **F11** — fullscreen.

### What is in the repository

```
Opus5-5-Talasofobia/
├── README.md                      ← this file (RU + EN)
├── HOW_TO_RUN.ru.md               ← how to run the games (RU)
├── HOW_TO_RUN.md                  ← how to run the games (EN)
├── Blender_MCP_Guide_RU.pdf       ← guide: connecting Blender to an AI agent (RU)
├── Blender_MCP_Guide_EN.pdf       ← guide: connecting Blender to an AI agent (EN)
├── 1-NADIR/                       ← Godot project, game 1
├── 2-PELAGIC/                     ← Godot project, game 2
└── 3-THE-DROWNED/                 ← Godot project, game 3
```

### Guide: connecting Blender to an AI agent

A short step-by-step guide to connecting **Blender MCP** to Claude Code or Codex (shown on a Unity project; the same order
works for other engines):
[Blender_MCP_Guide_EN.pdf](Blender_MCP_Guide_EN.pdf) · [Blender_MCP_Guide_RU.pdf](Blender_MCP_Guide_RU.pdf)

### How it was made

- Each game was built by a separate **Claude Opus 5.5** agent (Extra High, Ultracode) from one master prompt.
- Everything except the main creature is **generated by code**: geometry, shaders, textures and sound (the sound is synthesized by scripts).
- The main creatures (Bloop and SCP-3000) were generated separately: an image made with AI, then a 3D model in Tripo, then the
  agent finished the model (geometry, textures, shaders, swimming animation).
- The prompts and related materials are published in the author's Telegram channel (link in the video description).

### Credits and copyright

- The creature in PELAGIC is based on **SCP-3000 "Anantashesha"** (by A Random Day, djkaktus, Joreth), SCP Foundation Wiki,
  licensed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/): <https://scp-wiki.wikidot.com/scp-3000>.
- "Bloop" in NADIR is a fictional creature inspired by the mysterious "Bloop" sound recorded in 1997 (NOAA concluded it was
  cracking ice): <https://oceanservice.noaa.gov/facts/bloop.html>.
- The games are built with the **Godot Engine** (MIT license): <https://godotengine.org>.
