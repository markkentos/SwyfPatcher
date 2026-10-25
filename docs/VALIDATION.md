# Проверки 2.9.4 / Validation

## Русский

В отчёте от **25 октября 2026, 01:17 МСК** активная Q8 и аудиокодек занимали всего **17 757 и 17 770 байт** вместо 992 615 488 и 291 150 624 байт; их SHA-256 не совпадали с закреплёнными версиями. Qwen завершался при чтении GGUF, после чего игра использовала MOSS. Повреждение файлов подтверждено; что именно содержалось в этих файлах, из отчёта не установлено.

Проверено локально в PowerShell 7.4.6 на macOS, 25 октября 2026:

- **462 проверки патчера:** прежние сценарии установки, отката, меню и диагностики, а также восстановление двух повреждённых моделей через обычный пункт 2. Ошибки загрузки не меняют игровую DLL, воркер, манифест и активные модели. Ошибка установки после замены кодека откатывает модели и файлы игры. Успешное применение проверяет все 25 записей runtime; повторное не скачивает модели заново.
- **66 проверок восстановления моделей:** исправные Q8/Q4 без сети, повреждение кодека, пустой кэш, запомненный выбор Q4, повреждение без изменения размера, использование проверенного кэша и переключение обратно без загрузки. Проверены HTML вместо модели, неверный SHA-256, обрыв загрузки, переход к зеркалу, ошибки замены файлов и конкурентные изменения. Чужие изменения сохраняются; независимые замены при ошибке откатываются.
- Все записи сделаны во временные копии. Загрузки и Windows process/registry API подменены. DLL, воркер, манифест и модели пользовательской игры не изменены.

Воркер и native runtime не менялись: используется воркер **2.9.3**, SHA-256 `25F2FD20B795A60E360FD4D61537D458F3432663EFEA59B91F9E867908B21B8E`. Проверки синтеза из отчёта 2.9.3 ниже относятся к тому же бинарному файлу; заново в 2.9.4 они не выполнялись.

**Ещё требуется:** настоящая загрузка больших файлов и применение патча в Windows PowerShell 5.1, затем обычный запуск игры. Подменённые загрузки проверяют обработку ответов и ошибок, но не доступность Hugging Face и зеркал у конкретного пользователя. Восстановление файлов само по себе не подтверждает исправление всех причин заикания или качества отдельных голосов.

## English

The **October 25, 2026, 01:17 Moscow time** report contained an active Q8 model and codec of only **17,757 and 17,770 bytes**, instead of 992,615,488 and 291,150,624 bytes. Neither SHA-256 matched the pinned version. Qwen failed while reading GGUF, and the game used MOSS. Corrupt files are confirmed; their actual contents cannot be established from the report.

Checked locally with PowerShell 7.4.6 on macOS on October 25, 2026:

- **462 patcher assertions:** existing installation, restore, menu, and diagnostics coverage, plus repairing both corrupt models through ordinary option 2. Download failures leave the game DLL, worker, manifest, and active models unchanged. Installation failure after replacing the codec rolls back models and game files. Successful application validates all 25 runtime entries; reapplying does not download models again.
- **66 model repair assertions:** healthy Q8/Q4 without network access, codec corruption, empty caches, saved Q4 selection, same-size corruption, verified cache reuse, and offline switching back. Cases include HTML responses, incorrect SHA-256, interrupted downloads, mirror fallback, replacement failures, and concurrent changes. External changes are preserved while independent replacements are rolled back.
- All writes target temporary copies. Downloads and Windows process/registry APIs are mocked. The user's game DLL, worker, manifest, and models remain unchanged.

The worker and native runtime are unchanged: this release uses worker **2.9.3**, SHA-256 `25F2FD20B795A60E360FD4D61537D458F3432663EFEA59B91F9E867908B21B8E`. The 2.9.3 synthesis results below concern the same binary; those checks were not rerun for 2.9.4.

**Still needed:** actual large-file downloads and patch application in Windows PowerShell 5.1, followed by a normal game launch. Mocked downloads cover response and failure handling, not Hugging Face or mirror availability on a user's network. File repair alone does not establish a fix for every cause of stuttering or individual voice-quality problems.

---

# Проверки 2.9.3 / Validation

## Русский

В отчёте от **25 октября 2026, 01:14 МСК** подтверждена Q8 и Vulkan, все 25 контрольных сумм runtime совпадают. Шесть запросов Qwen завершились успешно; MOSS и отмен нет. Игра рендерится на RTX 3050 Laptop, но native-журналы озвучки показывают:

```text
ggml_vulkan: 0 = Intel(R) Iris(R) Xe Graphics
ggml_vulkan: 1 = NVIDIA GeForce RTX 3050 Laptop GPU
[Load] Talker backend: Vulkan0
```

Во всех трёх сохранённых сеансах Qwen использовал Intel. Четыре фрагмента имеют RTF 1,672 / 1,708 / 1,660 / 1,792. Например, 8,80 с аудио генерируются за 14,71 с без учёта подготовки голосового образца. Это объясняет риск опустошения буфера при потоковом воспроизведении. WAV корректно читаются: mono PCM16, 24 kHz, длительности 8,80 / 3,60 / 7,04 / 9,52 с; числового клиппинга нет. Это не субъективная оценка звучания и не измерение производительности RTX.

### Проверки изменения

- **424 проверки патчера:** установка и откат, все записи манифеста, обновление с воркера 2.9.2, модели, меню, автологи и вывод выбранного адаптера/RTF в сводке. Записи только во временные копии, исходная игра не изменена.
- **18 проверок выбора GPU:** точная конфигурация Intel Iris Xe `Vulkan0` + RTX 3050 `Vulkan1`, обратный порядок, дискретная Intel Arc, AMD iGPU, объёмы памяти, равные варианты, единственный GPU и отсутствие Vulkan. Тип GPU приоритетнее размера общей памяти встроенной графики.
- **7 случаев режима Q4** и **16 проверок автологов**. Q4-профиль сохраняется для Vulkan с любым числовым индексом; CPU и Q8 его не включают.
- **Три прохода бинарного протокола с native-заглушкой реестра:** реальный PE-воркер выбирает `Vulkan1` и передаёт это значение в native `qt_init` для Q8 и Q4; Q4 сохраняет `use_fa=False` и свои флаги. CPU передаёт `CPU` и не загружает GPU. Заглушка моделирует адаптеры, не выполняет GPU-вычисления.
- **Реальный CPU-синтез итогового PE** на соответствующем native runtime: Q4 — 71 блок / 5,68 с аудио; Q8 — 113 блоков / 9,04 с. Pipe, EOF, конечность семплов и число семплов в WAV проверены. При запросе Vulkan без Vulkan-устройства возвращается ошибка до загрузки модели, без перехода на CPU.
- Новые P/Invoke проверены по заголовку закреплённого ggml и экспортам настоящих игровых `ggml.dll` / `ggml-base.dll`. Подписи используют `UIntPtr` для `size_t`.

Итоговый воркер 2.9.3 SHA-256: `25F2FD20B795A60E360FD4D61537D458F3432663EFEA59B91F9E867908B21B8E`.

**Ещё требуется:** реальная Windows-проверка Q8 на RTX 3050, скорости потока и слышимых заиканий. Наличие выбранного адаптера в тесте с заглушкой не подтверждает качество GPU-синтеза. Параметры Q8 и игровая буферизация этим релизом не менялись.

## English

The **October 25, 2026, 01:14 Moscow time** report confirms Q8/Vulkan and matching checksums for all 25 runtime files. Six Qwen requests completed successfully without MOSS or cancellations. Unity rendered on RTX 3050 Laptop, but all three retained speech worker sessions used `Vulkan0`, identified by GGML as Intel Iris Xe. NVIDIA was `Vulkan1`.

Four fragments had RTF values of 1.672 / 1.708 / 1.660 / 1.792: for example, 8.80 seconds of audio took 14.71 seconds to generate, excluding voice-reference preparation. This explains the risk of streaming buffer underruns. WAV files are readable mono PCM16 at 24 kHz, with no numeric clipping. This is not a listening-quality assessment or an RTX benchmark.

### Validation

- **424 patcher assertions** cover installation, restore, all manifest entries, upgrades from 2.9.2, models, menu, automatic logs, and selected-device/RTF summary output. All writes target temporary fixtures; the original game is unchanged.
- **18 GPU selection assertions** cover the reported Intel `Vulkan0` + RTX `Vulkan1` configuration, reversed order, discrete Intel Arc, AMD integrated graphics, memory sizes, ties, a single GPU, and missing Vulkan. Device type takes priority over integrated shared-memory size.
- **7 Q4 policy cases** and **16 automatic logging assertions** passed. Q4 compatibility accepts any numeric Vulkan index, while Q8/CPU remain unaffected.
- **Three binary protocol checks with a native registry stub:** the actual PE worker passes `Vulkan1` into native `qt_init` for Q8 and Q4, preserving Q4 flags, and passes `CPU` without loading GPU libraries in CPU mode. This simulates adapters, not GPU computation.
- **Actual native CPU synthesis** with the final PE: Q4 produced 71 chunks / 5.68 seconds of audio; Q8 produced 113 chunks / 9.04 seconds. Protocol, EOF, finite samples, and WAV sample counts passed. A Vulkan request without a Vulkan device fails before model initialization, without CPU fallback.
- New P/Invoke declarations were checked against the pinned GGML headers and actual game DLL exports, using `UIntPtr` for `size_t`.

Final 2.9.3 worker SHA-256: `25F2FD20B795A60E360FD4D61537D458F3432663EFEA59B91F9E867908B21B8E`.

**Still needed:** actual Windows testing of Q8 on RTX 3050, synthesis speed, and audible stuttering. Simulated adapter selection does not verify GPU voice quality. This release does not change Q8 synthesis parameters or the game's playback buffering.

---

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
