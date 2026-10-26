# SwyfPatcher 2.9.6

[![Русский](https://img.shields.io/badge/Русский-переключить-555?style=for-the-badge)](README.md)
[![English](https://img.shields.io/badge/English-selected-2563eb?style=for-the-badge)](README.en.md)

An unofficial patcher for local **Qwen3 TTS** speech in **Scam With Your Friends**. Switch CPU/GPU and Q4/Q8 models, repair startup after an older patch, and save diagnostics. No cloud API or keys required.

> **We are not affiliated with the game's developers or publisher. This project is unofficial and is not endorsed or supported by them. Use at your own risk.**

## Install

1. Download the release archive and extract the **entire folder**, including `src` and `payload`.
2. Close the game, run `SwyfPatch.bat`, and choose **2 — Apply / update patch**. If the game is not found, drag its folder onto the BAT.
3. Close the patcher and start the game **normally through Steam or its EXE**. Logs are saved automatically.

Requires Windows 10/11 x64 and a supported game build. Checked against the **2026-10-26** build (buildid 26208975) as well as **0.1.91-swyf** and **0.1.89-swyf** files; unknown builds are left untouched. Applying the patch checks the active model and codec, restores them from a verified cache or downloads replacements. Internet is needed only for missing files (Q8 + codec: about 1.3 GB). After a game update, check compatibility again with option 1.

## Menu

| Option | Action |
|---|---|
| 1 | Check current status |
| 2 | Apply / update patch |
| 3 | Switch to CPU |
| 4 | Switch to GPU (Vulkan) |
| 5 | Use Q4 |
| 6 | Use Q8 |
| 7 | Collect logs as ZIP |
| 8 | Русский / English |
| 0 | Exit |

Applying the patch preserves a healthy model and your CPU/GPU selection. For a damaged model it uses the remembered choice; if the choice cannot be recovered, it restores Q8 and tells you. Switching models preserves CPU/GPU, and vice versa. GPU mode prefers a discrete graphics card and logs its name. The interface remembers your language.

**Q8** is a good starting point for checking speech. **Q4** uses less memory; its Vulkan compatibility mode may be slower. The fix for distorted Q4 audio on NVIDIA still needs Windows testing.

Corrupt originals are saved beside the models with a `.swyf-before-repair-…` suffix. Downloads must match the expected size and SHA-256 before installation; failures stop the patch. No extra menu options.

## Find logs

Installation adds a **`SwyfPatcher Logs`** shortcut beside the game's EXE. It opens:

```text
%USERPROFILE%\AppData\LocalLow\Jatater Worldwide\Scam With Your Friends
```

- `Player.log` — the latest normal game launch, including errors before Qwen starts; `Player-prev.log` — the previous launch.
- `swyf-qwen-logs/session-…/` — a Qwen log and WAV files for the first **6 replies** per worker launch, up to 30 seconds each. Sessions start when Qwen starts, not when you open the main menu. The latest 10 sessions are kept; active workers are not deleted.

After a problem, **close the game → open the patcher → select 7**. File Explorer will highlight the ZIP in the patcher's `logs/` folder. It includes game logs, three recent worker sessions, a summary, and system information. You do not need to start the game through the patcher or keep the patcher open while playing.

Logs contain dialogue text and local paths; WAV files contain generated speech. The microphone is not recorded, and nothing is uploaded automatically. Share the collected ZIP: the full profile folder also contains models and other game data.

## Restore and details

Close the game and run `SwyfPatch.bat --restore "D:\Games\Scam With Your Friends"`. This restores the game DLL, worker, and manifest; models and voice preferences are preserved. Keep the backup files.

[Release notes](docs/RELEASE_NOTES.md) · [Commands and building](docs/DEVELOPMENT.md) · [Validation and limitations](docs/VALIDATION.md)

**Credits:** original fix by psihozniy, PowerShell patcher by markkentos, C# bindings by lookbe. [Third-party code](worker/THIRD_PARTY_NOTICES.md) · [MIT](LICENSE).
