# How to run the games (very detailed, step by step)

[Русская версия → HOW_TO_RUN.ru.md](HOW_TO_RUN.ru.md) · [← Back to the README](README.md)

Every game starts from **one single file**: download it → double-click it → play.
There is nothing to install. Read the steps in order and do not skip any of them.

---

## What you need

- A PC with **Windows 10 or Windows 11** (64-bit).
- A graphics card with **DirectX 12 or Vulkan** support. Almost any gaming graphics card from the last
  few years works. The games were tested only on an NVIDIA GeForce RTX 5070, so on weak graphics cards and on
  laptops without a dedicated graphics card they may run slowly.
- Free disk space: about **200 MB per game**.
- The internet is only needed to download the file.

---

## Way 1. The easiest: download one file and run it (recommended)

### Step 1. Open the page with the games
Click this link: **https://github.com/Prokopiy8247/Opus5-5-Talasofobia/releases/latest**

### Step 2. Find the files
Scroll down to the block called **Assets**. Three games are there:

| File | Game |
|---|---|
| `NADIR.exe` | Game 1 — NADIR (descent into the abyss) |
| `PELAGIC.exe` | Game 2 — PELAGIC (open ocean) |
| `THE_DROWNED.exe` | Game 3 — THE DROWNED (graveyard of giants) |

### Step 3. Download the file you want
Click the name of the file, for example `NADIR.exe`. The download starts.
The file is big (120 to 200 MB), so **wait until the download is finished**.

If your browser says the file is "not commonly downloaded" or "may be dangerous", choose **Keep** or **Save**
(in Chrome: the three dots next to the file → "Keep"). This is a normal precaution for new programs without a signature.

### Step 4. Find the downloaded file
Open the **Downloads** folder. The quickest way: click the downloaded file icon in your browser and choose "Show in folder".

### Step 5. Run it
Quickly click the file **twice** with the left mouse button, for example `NADIR.exe`.

### Step 6. If Windows complains
A **blue window "Windows protected your PC"** may appear. This is normal: the game has no paid digital
signature, so Windows is being careful.

1. Click the words **"More info"**.
2. A button **"Run anyway"** appears. Click it.

If your antivirus deletes the file or does not let it start, add the file to the antivirus exceptions and download it again.
In the regular Windows Defender this is: "Windows Security" → "Virus & threat protection" →
"Manage settings" → "Exclusions".

### Step 7. Wait for loading
At first the screen can be **black** for up to a minute. This is normal: the game builds its world at startup.
**Do not press anything and do not close the window.** Then the title of the game appears and the game begins.

### Step 8. Play
The controls are below.

---

## Controls (the same in all three games)

| Press | What happens |
|---|---|
| **Mouse** | look around |
| **W** | swim forward along the path |
| **S** | swim backward |
| **Shift** (hold) | swim faster |
| **C** | **turn the autopilot on or off** (the game leads you by itself, you only watch) |
| **Esc** | pause (you can resume or quit there) |
| **F11** | fullscreen / window |

The simplest way: start the game, press **C** and **just watch**. Any key press gives control back to you.

A game lasts about 9 minutes, or about 5 minutes with Shift held or on autopilot. At the end a final line appears, the screen fades out and the game is over (it may close by itself, that is normal).
To leave earlier: **Esc → Quit** or **Alt + F4**.

---

## If something does not work

| Problem | What to do |
|---|---|
| Black screen for longer than a minute | Update your graphics card driver (NVIDIA, AMD or Intel website), restart the computer and run it again. |
| The game runs slowly | Close your browser and other programs. On a laptop, run the game on the dedicated graphics card: "Windows Settings" → "System" → "Display" → "Graphics" → add the game's `.exe` → "High performance". |
| No sound | Check the Windows volume and that the right sound output device is selected. |
| The file does not start or shows an error | Download the file again: it may not have downloaded completely. |
| Windows does not let it start | See "Step 6" above ("More info" → "Run anyway"). |
| The game closed by itself | That is the end of the game. Start the file again. |

---

## Way 2. Open the project in Godot (for the curious)

You need this if you want to see how everything is made, or to run the game on something other than Windows.

1. Download **Godot 4.7.2** (the standard version, **not** ".NET / Mono") from
   https://godotengine.org/download/archive/ (pick version **4.7.2**). Unpack the archive.
2. Download this repository: on the main page click the green **Code** button → **Download ZIP**.
   Unpack the archive.
3. Run `Godot_v4.7.2-stable_win64.exe` (from the folder where you unpacked Godot).
4. Click **Import** → find the folder of the game you want in the unpacked repository
   (`1-NADIR`, `2-PELAGIC` or `3-THE-DROWNED`) → pick the file **`project.godot`** in it → **Import & Edit**.
5. **Wait**: on the first open Godot spends a few minutes processing the big models.
6. Press **F5** (or the ▶ button at the top right). The game starts.

The games were made and tested on Windows. On Linux and macOS the project opens in Godot 4.7, but that was not tested.
