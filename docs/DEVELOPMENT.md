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

## Проверка и восстановление моделей / Model verification and repair

Любое применение патча, включая смену CPU/GPU или Q4/Q8, сначала проверяет активный talker и codec. Неиспользуемые копии других моделей не перекачиваются. Исправная активная модель определяется по SHA-256, а не имени файла: Q4 также находится под именем Q8. При повреждении используется `swyf-model-choice.txt`; для старого патчера без этого файла полный размер Q4 помогает восстановить выбор. Иначе выбирается Q8 с предупреждением. Явные `--model q4|q8` имеют приоритет.

Every patch application, including CPU/GPU and model switches, verifies the active talker and codec first. Unused model copies are not redownloaded. A healthy active model is identified by SHA-256, not its filename: Q4 also occupies the Q8 path. For corruption, `swyf-model-choice.txt` preserves the choice; older installs can identify full-size damaged Q4 by size. Otherwise Q8 is selected with a warning. Explicit `--model q4|q8` takes precedence.

Все нужные загрузки и копии из кэша подготавливаются в собственной временной папке рядом с моделями до изменения DLL/runtime. Размер и SHA-256 обязательны для каждого источника, включая зеркала. Затем перепроверяются исходные файлы, выполняются замены с бэкапами. При сбое откатываются собственные замены, конкурентные изменения сохраняются. Повреждённые оригиналы остаются как `.swyf-before-repair-…`. Исправные уходящие Q8/Q4 сохраняются в кэше; временные бэкапы убираются после успешного переключения. `--restore` модели не меняет.

All required downloads and cache copies are staged beside the models before DLL/runtime changes. Every source, including mirrors, must match the exact size and SHA-256. Original files are rechecked before replacement with backups. Failures roll back owned replacements and preserve concurrent changes. Corrupt originals remain as `.swyf-before-repair-…`. Healthy outgoing Q8/Q4 weights are cached; temporary rollback backups are removed after a successful switch. `--restore` leaves models unchanged.

## Выбор GPU / GPU selection

Игровой запрос `Vulkan0` означает режим GPU. Воркер загружает Vulkan-бэкенд, запрашивает устройства у того же реестра GGML, который использует Qwen, и передаёт выбранное имя (`Vulkan0`, `Vulkan1` и т. д.) через `GGML_BACKEND` до `qt_init`. Типы устройств из закреплённого ggml: `GPU=1`, `IGPU=2`. Приоритет: дискретная карта, затем общий объём памяти; равные варианты сохраняют порядок реестра. Название производителя не используется как эвристика. Переключатели Q4 выставляются до загрузки бэкенда.

The game's `Vulkan0` request means GPU mode. The worker loads the Vulkan backend, enumerates the same GGML registry Qwen uses, and sets `GGML_BACKEND` to the selected name before `qt_init`. The pinned GGML device types are `GPU=1` and `IGPU=2`. Selection prefers discrete graphics, then total memory, retaining registry order on ties. It does not guess from vendor names. Q4 flags are set before backend loading.

`GPU_SELECTED` показывает намеренно выбранный адаптер; строка native `Talker backend` подтверждает фактически инициализированный бэкенд. Рендерер Unity может работать на другой карте. `RTF > 1` в `[Perf] Total` означает, что генерация медленнее воспроизведения.

`GPU_SELECTED` identifies the selected adapter; the native `Talker backend` line confirms initialization. Unity's renderer may use a different card. `RTF > 1` in `[Perf] Total` means synthesis is slower than playback.

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
pwsh -NoProfile -File tests/Test-GpuSelection.ps1
pwsh -NoProfile -File tests/Test-ModelRepair.ps1
pwsh -NoProfile -File tests/Test-AutomaticLogs.ps1
pwsh -NoProfile -File tests/Test-SwyfPatch.ps1 -GameRoot "D:\Games\Scam With Your Friends"
```

После пересборки обновите `RuntimeSpec.PatchedWorker` новым SHA-256. Старые выпущенные хеши должны оставаться в `PreviousWorkers`, чтобы обновление было возможно. Воркер и его запись в манифесте меняются вместе; проверка целостности не отключается.

After rebuilding, update `RuntimeSpec.PatchedWorker` with the new SHA-256. Keep released hashes in `PreviousWorkers` to allow upgrades. The worker and its manifest entry are updated together; integrity checking remains enabled.

Игровые DLL, модели и native runtime не включаются в релиз. Все записи тестов направлены во временные копии. Ограничения проверок: [VALIDATION.md](VALIDATION.md).

Game DLLs, models, and the native runtime are not distributed. Tests mutate temporary fixtures only. Validation limits: [VALIDATION.md](VALIDATION.md).
