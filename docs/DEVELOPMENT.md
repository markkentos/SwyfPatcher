# Команды и разработка / Commands and development

[Русский](../README.md) · [English](../README.en.md)

## Команды / Commands

```bat
SwyfPatch.bat --lang ru "D:\Games\Scam With Your Friends"
SwyfPatch.bat --lang en "D:\Games\Scam With Your Friends"
SwyfPatch.bat --check "D:\Games\Scam With Your Friends"
SwyfPatch.bat --backend vulkan --model q4 "D:\Games\Scam With Your Friends"
SwyfPatch.bat --backend cpu --model q8 "D:\Games\Scam With Your Friends"
SwyfPatch.bat --logs "D:\Games\Scam With Your Friends"
SwyfPatch.bat --restore "D:\Games\Scam With Your Friends"
```

`--check` ничего не меняет. `--logs` собирает уже записанные логи и аудио. `--restore` восстанавливает DLL, воркер и манифест, но не меняет модели и настройки голоса. `--reference 3|10` — ручной выбор длины образца; штатное значение — 10 секунд.

`--check` is read-only. `--logs` collects existing logs and audio. `--restore` restores the DLL, worker, and manifest, preserving models and voice preferences. `--reference 3|10` overrides the voice reference duration; the default is 10 seconds.

## Дополнительный тест / Isolated test

`SwyfPatch.bat --launch "D:\Games\Scam With Your Friends"` по-прежнему доступен: запускает игру с отдельным `Player.log` и собирает ZIP после её закрытия. Только в этом режиме окно патчера нужно оставлять открытым. Для обычных тестов достаточно запустить игру через Steam и собрать логи пунктом 7.

`--launch` still starts an isolated test with a dedicated `Player.log` and collects a ZIP on exit. Only this optional mode requires keeping the patcher open. Normal play through Steam followed by option 7 is sufficient for ordinary reports.

## Автоматические логи / Automatic logging

Воркер по умолчанию пишет в `swyf-qwen-logs/session-…` внутри профиля Unity. Один журнал ограничен примерно 8 MiB, WAV — первыми шестью репликами по 30 секунд. Хранятся 10 последних сеансов; активные и посторонние файлы не удаляются. Старые плоские журналы версий 2.9.0/2.9.1 не очищаются автоматически. Игра отдельно ведёт `Player.log` / `Player-prev.log` независимо от запуска воркера.

The worker defaults to `swyf-qwen-logs/session-…` inside the Unity profile. Each log is capped at approximately 8 MiB; WAV capture is limited to six replies of up to 30 seconds. The latest 10 sessions are retained, preserving active workers and unrelated files. Old flat logs from 2.9.0/2.9.1 are not automatically removed. The game maintains its own `Player.log` / `Player-prev.log`, independently of the worker.

- `SWYF_QWEN_CAPTURE=0`: отключить WAV / disable WAV capture. Текстовые логи остаются / text logs stay enabled.
- `SWYF_QWEN_LOG_DIR`: отдельная папка для отладки / an explicit debug folder. Ротация отключена / no automatic pruning. При ошибке записи используется стандартная папка / an inaccessible override falls back to the standard folder.

Переменные должны быть унаследованы игрой при запуске. В обычной установке задавать их не нужно. ZIP содержит только выбранные логи и WAV, а не кэш моделей или сохранения. Сеансы воркера могут относиться к разным запускам игры — сверяйте время; они не включаются в счётчики текущего `Player.log`.

The game must inherit environment overrides when it starts; none are needed for normal use. Exported ZIPs include selected logs and WAV files, not models or saves. Recent worker sessions may belong to different game launches: match timestamps; they are excluded from current `Player.log` counts.

## Сборка и тесты / Build and tests

Обычному пользователю сборка не нужна: `payload/QwenTtsWorker.exe` уже готов. Для разработки нужны PowerShell 7 с Roslyn и reference assemblies .NET Framework 4.7.2.

Users do not need build tools: the worker is included. Developers need PowerShell 7 with Roslyn and .NET Framework 4.7.2 reference assemblies.

```powershell
pwsh -NoProfile -File worker/Build-Worker.ps1 -ReferenceDirectory "path\to\net472"
pwsh -NoProfile -File tests/Test-WorkerPolicy.ps1
pwsh -NoProfile -File tests/Test-AutomaticLogs.ps1
pwsh -NoProfile -File tests/Test-SwyfPatch.ps1 -GameRoot "D:\Games\Scam With Your Friends"
```

После пересборки обновите `RuntimeSpec.PatchedWorker` новым SHA-256. Старые выпущенные хеши должны оставаться в `PreviousWorkers`, чтобы обновление было возможно. Воркер и его запись в манифесте меняются вместе; проверка целостности не отключается.

After rebuilding, update `RuntimeSpec.PatchedWorker` with the new SHA-256. Keep released hashes in `PreviousWorkers` to allow upgrades. The worker and its manifest entry are updated together; integrity checking remains enabled.

Игровые DLL, модели и native runtime не включаются в релиз. Все записи тестов направлены во временные копии. Ограничения проверок: [VALIDATION.md](VALIDATION.md).

Game DLLs, models, and the native runtime are not distributed. Tests mutate temporary fixtures only. Validation limits: [VALIDATION.md](VALIDATION.md).
