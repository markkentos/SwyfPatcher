# Проверки 2.9.2 / Validation

[Русский](../README.md) · [English](../README.en.md)

## Русский

Проверено локально на macOS, 24 октября 2026. Windows-игра здесь не запускалась.

- **422 проверки патчера** в PowerShell 7.4.6: установка, восстановление, смена моделей, миграции DLL 22/24 октября, обновление воркера 2.9.0/2.9.1, все 25 записей манифеста, бэкапы, ошибки записи и конкурентные изменения. Также проверены девять пунктов RU/EN, сбор автоматических логов и WAV, отделение старых сеансов от текущих счётчиков речи. Windows process/registry API подменены; все изменяемые файлы — временные копии. Исходные DLL, воркер и манифест пользовательской игры остались неизменными.
- **16 проверок автологов**: запись без переменных окружения, сохранение первых шести WAV, обновление заголовка WAV до выхода, отключение аудио, недоступная папка, ротация десяти сеансов, сохранение работающего воркера и посторонних файлов. Ошибки записи и закрытия WAV не выходят в синтез.
- **Четыре случая выбора режима Q4**: совместимость включается только для точного хеша Q4 + Vulkan0; Q8 и CPU её не используют.
- **Реальный бинарный протокол итогового PE-воркера 2.9.2** через PowerShell и локальную CPU-сборку соответствующего native runtime. Q4: 74 блока / 5,92 с аудио; Q8: 97 блоков / 7,76 с. Все семплы конечны, генерация и EOF завершаются штатно. WAV включён по умолчанию без `SWYF_QWEN_CAPTURE`; число семплов совпало с потоком в игру. Это длительность аудио, не скорость генерации.

Воркер: .NET Framework 4.7.2, AnyCPU без Prefer32Bit. SHA-256: `3F5236375D4BCB5E90BCC4E4DA51984E7A5BC147A88FF48CABE198A92B735AFB`.

### Что ещё проверить на Windows

Обычный запуск через Steam/EXE, появление ярлыка `SwyfPatcher Logs`, выделение ZIP в Проводнике и качество голоса, особенно Q4/Vulkan и Dark Hater. Windows PowerShell 5.1, WScript COM и NVIDIA/Vulkan здесь не запускались. Текстовые нативные логи содержат callbacks Qwen/GGML, но могут не включать сообщения, записанные библиотекой напрямую в stderr.

В пользовательском отчёте перед 2.9.1 Qwen был отключён из-за несовпадения хеша воркера и манифеста: все семь реплик озвучивал MOSS. Исправление манифеста покрыто регрессионными проверками. Этот отчёт не доказывает качество Qwen для Dark Hater. Отмены онлайн-запросов диалога и ошибка Unity UI из того же отчёта не имеют доказанной связи с патчем и этим релизом не исправляются.

## English

Checked locally on macOS on October 24, 2026. The Windows game was not run here.

- **422 patcher assertions** with PowerShell 7.4.6 cover install/restore, model changes, both game DLL fixtures, upgrades from the 2.9.0/2.9.1 worker, all 25 manifest entries, backups, write failures, and concurrent changes. They also cover the nine-option RU/EN menu, automatic log/audio export, and separation of older worker sessions from current speech counts. Windows process/registry APIs are mocked; writes target temporary copies. The user's game DLL, worker, and manifest remain unchanged.
- **16 automatic logging assertions** cover defaults without environment variables, six-reply WAV capture, live WAV headers, capture opt-out, inaccessible folders, ten-session retention, and preservation of active sessions and unrelated files. WAV write/close errors do not propagate into synthesis.
- **Four Q4 policy cases** confirm that compatibility mode applies only to the verified Q4 hash with Vulkan0, not Q8 or CPU.
- **Actual binary protocol of the final 2.9.2 PE worker**, loaded through PowerShell with a matching native CPU runtime. Q4 produced 74 chunks / 5.92 seconds of audio; Q8 produced 97 chunks / 7.76 seconds. Samples were finite and generation/EOF completed normally. WAV capture worked without `SWYF_QWEN_CAPTURE`; its sample count matched the game-facing stream. These are audio durations, not generation times.

Worker target: .NET Framework 4.7.2, AnyCPU without Prefer32Bit. SHA-256: `3F5236375D4BCB5E90BCC4E4DA51984E7A5BC147A88FF48CABE198A92B735AFB`.

### Still needs Windows testing

Normal Steam/EXE launch, the `SwyfPatcher Logs` shortcut, highlighting the ZIP in File Explorer, and voice quality, particularly Q4/Vulkan and Dark Hater. Windows PowerShell 5.1, WScript COM, and NVIDIA/Vulkan were not exercised locally. Native logs capture Qwen/GGML callbacks but may omit direct library stderr output.

The user report before 2.9.1 showed Qwen disabled by a worker/manifest checksum mismatch; all seven replies used MOSS. Manifest repair now has regression coverage. That report cannot establish Qwen's voice quality for Dark Hater. Separate online dialogue cancellations and a Unity UI exception have no established causal link to this patch and are outside this release.
