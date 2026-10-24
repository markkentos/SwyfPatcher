# SwyfPatcher v2.9.2

## Русский

Логи больше не требуют запуска игры через патчер. После установки запускайте игру обычным способом — через Steam или EXE.

- Qwen автоматически сохраняет журнал и WAV первых шести реплик каждого запуска воркера. Хранятся десять последних сеансов; работающие воркеры и посторонние файлы не удаляются.
- Рядом с игрой создаётся ярлык **SwyfPatcher Logs** к профилю с `Player.log` и папкой `swyf-qwen-logs`. Ошибки до запуска Qwen остаются в игровом `Player.log`.
- **Пункт 7 — собрать логи в ZIP**: после игры собирает игровые логи, три последних сеанса воркера, сводку и сведения о системе. Проводник выделяет готовый архив. Меню остаётся плоским, из девяти пунктов.
- Ошибка записи аудио не останавливает синтез. WAV можно отключить через `SWYF_QWEN_CAPTURE=0`. Записывается выход синтезатора, не микрофон; автоматической отправки нет.
- README разделён на короткие русскую и английскую версии с кнопками языка и предупреждением о неофициальном статусе и использовании на свой риск.
- Воркер обновлён до 2.9.2; манифест обновляется вместе с ним. Настройки синтеза и режим Q4/Vulkan не изменены.

**Обновление:** распакуйте весь архив, закройте игру и выберите **2 — применить / обновить патч**. Затем закройте патчер и играйте как обычно. После проблемы закройте игру и нажмите **7** в патчере; пришлите ZIP из `logs/`.

Локальные проверки пройдены; обычный запуск Windows-игры, ярлык и Проводник требуют пользовательского теста. Этот релиз не подтверждает исправление качества конкретного голоса или Q4/Vulkan.

## English

Logs no longer require starting the game through the patcher. After installation, launch normally through Steam or the game's EXE.

- Qwen automatically saves a log and WAV files for the first six replies per worker launch. The latest ten sessions are retained, preserving active workers and unrelated files.
- A **SwyfPatcher Logs** shortcut beside the game opens the profile containing `Player.log` and `swyf-qwen-logs`. Errors before Qwen starts remain in the game's `Player.log`.
- **Option 7 — Collect logs as ZIP** collects game logs, three recent worker sessions, a summary, and system information after playing. File Explorer highlights the archive. The menu still has nine options and no submenus.
- Audio recording errors cannot interrupt synthesis. `SWYF_QWEN_CAPTURE=0` disables WAV capture. Only generated speech is recorded, not the microphone; nothing is uploaded automatically.
- Short Russian and English READMEs have language buttons and an explicit unofficial / use-at-your-own-risk notice.
- Worker version is now 2.9.2; its manifest entry is updated with it. Synthesis settings and the Q4/Vulkan profile are unchanged.

**Update:** extract the complete archive, close the game, and select **2 — Apply / update patch**. Close the patcher and play normally. After a problem, close the game and select **7**; share the ZIP from `logs/`.

Local checks passed. Normal Windows game launch, the shortcut, and File Explorer still require user testing. This release does not confirm a voice-quality or Q4/Vulkan fix.

---

# SwyfPatcher v2.9.1

## Русский

Исправлено отключение Qwen после установки нового воркера в 2.9.0 и ранее выданной тестовой сборке. Патчер заменял `QwenTtsWorker.exe`, но оставлял в `runtime-manifest.json` хеш оригинала. Игра сообщала `Qwen runtime checksum mismatch: QwenTtsWorker.exe` и на весь сеанс переходила на MOSS. Поэтому наличие установленной Q8/Q4 ещё не означало, что она озвучивала реплики.

- Воркер и его запись в манифесте теперь обновляются согласованно. Проверка целостности игры остаётся включённой; меняется только хеш известного воркера.
- Проверяются все 25 файлов runtime. Изменённый сторонним инструментом манифест не перезаписывается.
- Добавлен оригинальный бэкап `runtime-manifest.json.swyf.original`. При ошибке установки откатываются собственные изменения воркера и манифеста; `--restore` восстанавливает их вместе с игровой DLL.
- Повторное применение исправляет манифест даже при уже установленном актуальном воркере. Поддержано обновление с прежней тестовой сборки.
- Проверка состояния показывает несоответствие контрольных сумм, а тестовый запуск останавливается с предложением применить исправление.
- В сводке отдельно указаны Qwen, MOSS, причина отключения Qwen и откаты генерации диалога. После теста с MOSS патчер показывает предупреждение.

**Обновление:** распакуйте `SwyfPatcher-2.9.1.zip` целиком, закройте игру, запустите BAT и выберите **2 → применить / обновить**, затем **7 → запуск с логами**. Модель и CPU/GPU сохраняются. После теста закройте игру и дождитесь `logs/test-*.zip`.

Воркер и параметры синтеза остаются от 2.9.0; его версия в нативном журнале по-прежнему 2.9.0. Это исправление установки и диагностики. Качество конкретных голосов и Q4/Vulkan требует повторного Windows-теста с действительно работающим Qwen. Отмена онлайн-запросов диалога и ошибка Unity UI из пользовательского лога этим изменением не исправляются.

## English

Fixed Qwen being disabled after installing the replacement worker in 2.9.0 and the earlier test build. The installer changed `QwenTtsWorker.exe` without updating its hash in `runtime-manifest.json`, so the game rejected it and switched to MOSS for the session.

- The worker and its manifest entry are updated together; integrity checking remains enabled.
- All 25 runtime files are checked. Unrecognized manifests are preserved.
- The original manifest is backed up. Installation failures roll back owned changes, and `--restore` restores the worker, manifest and game DLL.
- Reapplying repairs the manifest even when the current worker is already installed.
- Status and launch checks detect checksum mismatches. Diagnostic summaries distinguish Qwen, MOSS, Qwen shutdown reasons and online dialogue fallbacks.

**Update:** extract the complete `SwyfPatcher-2.9.1.zip`, close the game, run the BAT, choose **2 → Apply / update**, then **7 → Launch + logs**. The model/backend are preserved. Collect `logs/test-*.zip` after exiting the game.

The worker binary and synthesis settings are unchanged from 2.9.0. Windows voice quality still needs a fresh test with Qwen actually running; separate game dialogue cancellations and Unity UI errors are outside this fix.

---

# SwyfPatcher v2.9.0

## Русский

Обновление патчера Qwen3 TTS для поддерживаемых Windows-сборок **Scam With Your Friends**. Исправляет зависание после старого патча, возвращает штатный образец голоса и добавляет отдельный режим совместимости Q4/Vulkan. Интерфейс доступен на русском и английском.

### Изменения

- Исправлен некорректный переход в `VerifyAsync`, вызывавший зависание запуска после патча 2.8. Добавлено обновление с ранее выданных локальных исправлений.
- Для поддерживаемых DLL 24 и 22 октября восстановлен штатный 10-секундный образец голоса; исправлен выбор CPU/Vulkan для таблицы 22 октября.
- Новый Qwen-воркер включает режим совместимости только для проверенной **Q4 + Vulkan0**: отключает FP16 и ряд ускоренных вычислительных путей старого runtime. Модель остаётся Q4, выбранный GPU сохраняется. Q8 и CPU используют прежние параметры синтеза.
- Параметры бэкенда и GGML передаются в нативное окружение CRT до загрузки моделей.
- Главное меню состоит из **9 пунктов**, включая выход: проверка, применение патча, CPU, GPU, Q4, Q8, запуск с логами, язык и выход. Подменю отсутствуют.
- Переключение **Русский / English** сохраняется между запусками. Доступен флаг `--lang ru|en`.
- Обновление патча сохраняет модель и бэкенд. Смена CPU/GPU сохраняет модель, а смена Q4/Q8 — бэкенд.
- Тестовый запуск собирает текущий лог игры, нативные журналы Qwen/GGML, сведения о системе и WAV первых шести сгенерированных реплик. Старые логи не смешиваются с результатами текущего теста. Файлы остаются на компьютере пользователя.
- Установка проверяет SHA-256 моделей, игровой DLL, воркера и необходимых нативных библиотек. Неизвестные версии не перезаписываются. Оригинальный воркер сохраняется в резервной копии; `--restore` восстанавливает его вместе с игровой DLL.
- Поддержано обновление воркера из ранее выданной тестовой сборки при наличии проверенной оригинальной резервной копии.

### Установка и обновление

1. Скачайте `SwyfPatcher-2.9.0.zip` и распакуйте **всю папку**, включая `src` и `payload`.
2. Закройте игру и запустите `SwyfPatch.bat`. Если игра не найдена автоматически, перетащите её папку на BAT.
3. Выберите **2 — применить / обновить патч**. Текущие модель и бэкенд сохранятся.

Для проверки Q4 на GPU выберите **5 → 4 → 7**. После выхода из игры архив диагностики появится в `logs/test-*.zip`; окно патчера должно оставаться открытым до завершения сбора.

### Проверка и ограничения

Логика патчера проверена на временных файлах, включая установку, миграции, откат, модели, меню и диагностику. Новый воркер прошёл бинарный протокол и генерацию Q4/Q8 с CPU-сборкой соответствующего нативного runtime на Mac. Подробности: [VALIDATION.md](VALIDATION.md).

**Качество речи Q4 на Windows/Vulkan после изменения ещё не подтверждено.** Это режим совместимости для проверки проблемы искажённого звука; он может снизить скорость. Наличие завершённой генерации в журнале само по себе не подтверждает нормальное звучание. Игра и NVIDIA/Vulkan на Mac не запускались.

Поддержка ограничена точными версиями файлов, которые распознаёт патчер. Новая версия игры или другой нативный runtime могут потребовать обновления таблиц. Архив не содержит игровых DLL, моделей или нативных библиотек; Python и SDK для использования не нужны.

## English

This update repairs the startup hang introduced by the older patch, restores the original voice-reference duration, adds a Q4/Vulkan compatibility mode and provides a flat Russian/English interface for supported Windows builds of **Scam With Your Friends**.

### Changes

- Fixed the invalid `VerifyAsync` branch from patch 2.8 and corrected CPU/Vulkan selection for the 22 October DLL table. Supported builds use the original 10-second voice reference by default.
- Added a replacement Qwen worker with a conservative GPU path for the verified **Q4 + Vulkan0** combination. It disables FP16 and selected fast paths in the older runtime. Q4 weights and GPU selection are preserved; Q8 and CPU retain their synthesis defaults.
- Backend and GGML options are written to the native CRT environment before model initialization.
- Added a flat **9-option menu**, including Exit, with persistent Russian/English language selection and `--lang ru|en` support.
- Applying the patch preserves the current model/backend. Switching the backend preserves the model; switching the model preserves the backend.
- Test launches collect the current game log, native Qwen/GGML logs, system details and WAV audio for the first six generated replies. Nothing is uploaded automatically.
- Exact SHA-256 checks protect installation and model switching. The original worker is backed up, and `--restore` restores it alongside the game DLL. Upgrades from the previously distributed test worker are supported when its verified original backup is present.

### Install or update

Extract the complete `SwyfPatcher-2.9.0.zip`, close the game, run `SwyfPatch.bat` and choose **2 — Apply / update patch**. Drag the game folder onto the BAT if automatic discovery fails. To test Q4 on GPU, choose **5 → 4 → 7** and collect `logs/test-*.zip` after exiting the game.

### Validation and known limitation

Patcher checks, worker protocol and Q4/Q8 CPU synthesis were tested locally. **Q4 audio quality on Windows/Vulkan remains unverified after this change**, and the compatibility mode may be slower. See [VALIDATION.md](VALIDATION.md) for the evidence and test limits. Only recognized game/native-runtime versions are supported. Game DLLs, models and native libraries are not included; no Python or SDK installation is required to use the patcher.
