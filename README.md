# SwyfPatcher 2.9.0

**Русский / English.** Патчер Qwen3 TTS для предоставленной Windows-сборки **Scam With Your Friends 0.1.89-swyf**. Один экран, **9 пунктов вместе с выходом**, без вложенных меню. Windows PowerShell 5.1; Python и SDK для использования не нужны.

Описание релиза: [SwyfPatcher v2.9.0](docs/RELEASE_NOTES.md).

## Быстрый тест Q4 / Quick Q4 test

1. Распакуйте всю папку, включая `src` и `payload`. Закройте игру и `QwenTtsWorker`.
2. Запустите `SwyfPatch.bat`. Если игра не найдена, перетащите её папку на BAT.
3. **5 → Q4**, затем **4 → GPU**, затем **7 → запуск с логами**. Переключение модели и обработки также применяет актуальный патч и устанавливает обновлённый воркер.
4. Проверьте голос. После выхода из игры архив появится в `logs/test-*.zip`. Оставьте окно патчера открытым.

Extract the complete folder, close the game and its Qwen worker, then run `SwyfPatch.bat`. Select **5 (Q4) → 4 (GPU) → 7 (launch + logs)**. Keep the patcher open until the game exits; collect `logs/test-*.zip`. Drag the game folder onto the BAT if automatic discovery fails.

**Устранение рычания на NVIDIA ещё требует пользовательского теста.** На Mac проверены синтез Q4/Q8 через совместимый CPU runtime и протокол нового воркера; Windows/Vulkan на RTX 3050 здесь не запускался. Это сборка с изменением вычислительного режима Q4 для проверки, а не подтверждение исправленного звука на этой видеокарте.

**The NVIDIA audio fix still needs a Windows test.** CPU synthesis, the worker protocol and patcher logic were tested locally. RTX 3050/Vulkan audio has not been verified here.

## Меню / Menu

| Пункт | Русский | English |
|---|---|---|
| 1 | Проверить текущее состояние | Check current status |
| 2 | Применить / обновить патч | Apply / update patch |
| 3 | Переключить на CPU | Switch to CPU |
| 4 | Переключить на GPU (Vulkan) | Switch to GPU (Vulkan) |
| 5 | Включить Q4 | Use Q4 |
| 6 | Включить Q8 | Use Q8 |
| 7 | Запустить игру + логи | Launch game + logs |
| 8 | Русский / English | Русский / English |
| 0 | Выход | Exit |

Язык выбирается по языку Windows, меняется пунктом 8 и сохраняется в `language.txt`. Можно явно запустить `SwyfPatch.bat --lang ru` или `--lang en`. Технические журналы сохраняются на английском.

The UI follows the Windows language on first launch. Option 8 switches and remembers the language in `language.txt`; `--lang ru` / `--lang en` overrides it for the session. Diagnostic logs remain in English.

Пункт 2 сохраняет выбранные модель и бэкенд. CPU/GPU не переключают модель, а Q4/Q8 сохраняют бэкенд. При применении используется штатный 10-секундный образец голоса для сборок 24/22 октября. Пункт 1 только читает файлы, пункт 7 только запускает игру и собирает логи. В главном меню Enter ничего не устанавливает.

Apply preserves the selected model/backend. CPU/GPU switches preserve the model; Q4/Q8 switches preserve the backend. Patching uses the original 10-second voice reference for the supported 24/22 October DLL tables. Check is read-only; launch does not install a patch.

## Изменение для Q4 / Q4 change

Q4 больше не спрятана и не заменяется Q8. Её исходные GGUF-веса остаются **без изменений**, с тем же SHA-256. Новый `QwenTtsWorker.exe` распознаёт проверенную Q4 и **только при Vulkan0** включает совместимый вычислительный режим:

- отключает FP16-вычисления, специализированный quantized mat-vec и cooperative-matrix пути;
- отключает оптимизацию графа, слияние операций и flash attention;
- передаёт выбор бэкенда и переключатели непосредственно в нативное окружение CRT, которое читает GGML.

Выбранный бэкенд остаётся **Vulkan0**, автоматической подмены на CPU нет. При отсутствии выбранного GPU возвращается явная ошибка. Вычисления могут стать медленнее. Q8 и CPU сохраняют исходные параметры синтеза; формат запросов, лимиты, поток аудио и обработка голосового образца совместимы с исходным воркером.

Q4 weights stay byte-for-byte unchanged. For the verified Q4 + Vulkan0 combination, the replacement worker disables the older runtime's FP16, specialized quantized mat-vec, cooperative-matrix, graph optimization/fusion and flash-attention paths. It writes environment options to both .NET/Win32 and the native CRT. GPU selection stays Vulkan0, with no silent CPU fallback. This trades speed for a more conservative GPU path; Q8 and CPU retain their synthesis defaults.

В исходных пользовательских тестах Q8 работала нормально, Q4 на Vulkan давала рычание; Q4 на CPU пользователем ещё не проверялась. Локальный контрольный синтез исходной Q4 на CPU воспроизвёл полную фразу, которую распознаватель восстановил почти дословно. Точный дефект NVIDIA/Vulkan пока не локализован; новый режим и нативные логи позволяют проверить этот участок отдельно.

## Логи / Logs

После пункта 7 ZIP содержит:

- `Player.log` — лог текущего запуска игры;
- `qwen-worker/qwen-*.log` — версия воркера, хеш модели, выбранный режим, нативные сообщения Qwen/GGML, устройство, начало и завершение запросов, ошибки и статистика аудио;
- `qwen-worker/audio-*.wav` — озвучка **первых шести реплик**, максимум 30 секунд каждая. Это выход синтезатора, не запись микрофона. WAV обновляется по мере генерации и остаётся доступным после досрочного выхода;
- `system-and-dll.txt` — DLL, модели, runtime и оборудование; известная локальная замена воркера отмечается отдельно от оригинального манифеста;
- `speech-summary.txt` — текущие события речи и воркера. Старые `before-/after-/prev` логи не смешиваются с текущими;
- журнал патчера и код завершения игры.

Ничего не отправляется автоматически. В журнале воркера сохраняется текст синтезируемых реплик. При обычном запуске игры через Steam записывается только журнал в `%USERPROFILE%\AppData\LocalLow\Jatater Worldwide\Scam With Your Friends\swyf-qwen-logs`, без WAV. Журнал ограничен 8 МБ на процесс. Часть прямых сообщений native stderr может отсутствовать: перехватываются callback-журналы Qwen/GGML, а не весь stderr.

Option 7 saves the current Unity log, native Qwen/GGML logs and WAV audio of the first six generated replies (up to 30 seconds each). It records synthesized output, not microphone audio. Nothing is uploaded automatically. Ordinary game launches write only worker logs under the game's LocalLow profile; audio capture is enabled only for patcher test launches.

## Совместимость и откат / Compatibility and restore

Патчер проверяет точные хеши DLL и нативного runtime. Неизвестные версии не перезаписываются. В архив включён только новый управляемый воркер и его исходники; DLL игры, нативные библиотеки и модели не распространяются. Оригинальный воркер сохраняется рядом как `QwenTtsWorker.exe.swyf.original`; оригинальная игровая DLL — в проверенной резервной копии.

Таблицы патчей игровой DLL 24/22 октября сохранены: исправление `VerifyAsync`, таймауты, выбор CPU/Vulkan и 3/10 секунд. Установка нового воркера требует точного runtime из предоставленной игры; это дополнительная проверка к хешу игровой DLL. Старые DLL-таблицы сами по себе не означают совместимость другого runtime.

`--restore` восстанавливает **игровую DLL и исходный Qwen-воркер**. Модель и настройки голоса не откатываются. При необходимости Q8 выбирается отдельно.

Exact file hashes gate installation. Unknown game/native versions are preserved. The original worker and game DLL are backed up. `--restore` restores both executables, leaving models and voice preferences unchanged.

```bat
SwyfPatch.bat --lang en "D:\Games\Scam With Your Friends"
SwyfPatch.bat --check "D:\Games\Scam With Your Friends"
SwyfPatch.bat --backend vulkan --model q4 "D:\Games\Scam With Your Friends"
SwyfPatch.bat --backend cpu --model q4 "D:\Games\Scam With Your Friends"
SwyfPatch.bat --model q8 "D:\Games\Scam With Your Friends"
SwyfPatch.bat --launch "D:\Games\Scam With Your Friends"
SwyfPatch.bat --logs "D:\Games\Scam With Your Friends"
SwyfPatch.bat --restore "D:\Games\Scam With Your Friends"
```

Модели закреплены на ревизии [`b7ee2e8…`](https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF/tree/b7ee2e8c7459c3bea99da23e3d178125a7d1713c). Все загрузки и переключения проверяются по SHA-256. Если кэша моделей ещё нет, сначала дайте игре скачать штатные модели.

## Проверка / Validation

Пройдены 284 автоматические проверки в PowerShell 7.4.6 на временных файлах с дополнительными фикстурами DLL 22 октября и предыдущего воркера: совместимость DLL, миграции, бэкапы и откат воркера, несовместимый runtime, модели, плоское меню RU/EN и логи. Windows API в этих тестах подменены. Дополнительно новый скомпилированный воркер прошёл реальный бинарный протокол и синтез Q4/Q8 через локально собранную CPU-версию того же Qwen runtime. Подробности: [docs/VALIDATION.md](docs/VALIDATION.md).

```powershell
pwsh -NoProfile -File tests/Test-SwyfPatch.ps1 -GameRoot "D:\Games\Scam With Your Friends"
```

Сборка воркера — только для разработки: [worker/Build-Worker.ps1](worker/Build-Worker.ps1). Использует Roslyn из PowerShell 7 и reference assemblies .NET Framework 4.7.2. Для обычного использования `payload/QwenTtsWorker.exe` уже собран.

## Авторы / Credits

Оригинальный аппаратный/таймаутный фикс — **psihozniy**, исходный PowerShell-патчер — **markkentos**; идеи переключения моделей использованы из SwyfPatcher-2.6.0. C# bindings — **lookbe**, см. [worker/THIRD_PARTY_NOTICES.md](worker/THIRD_PARTY_NOTICES.md). Локальная доработка, не официальный релиз игры или авторов. [MIT](LICENSE).
