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
