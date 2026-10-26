# SwyfPatcher 2.9.6

[![Русский](https://img.shields.io/badge/Русский-выбран-2563eb?style=for-the-badge)](#русский)
[![English](https://img.shields.io/badge/English-switch-555?style=for-the-badge)](#english)

---

## Русский

**SwyfPatcher 2.9.6 — поддержка сборки игры от 2026-10-26 (buildid 26208975)**

Игра снова обновилась — патчер доработан. Новая запись таблицы выведена по фактическим файлам игры: каждая правка сверена по байтам, все варианты патча пересчитаны.

- Проверено на реальных файлах сборки **2026-10-26**; прежние сборки 0.1.91-swyf и 0.1.89-swyf тоже поддерживаются.
- Методы HardwareEligible и проверки модели побайтово идентичны 0.1.91 (кроме токенов метаданных) — подтверждено сравнением IL.
- Все прежние исправления на месте: таймауты 300/120 с, выбор CPU/GPU (Vulkan), обход проверки модели для Q4.
- Воркер и модели не менялись — повторная загрузка не требуется, если модели уже на месте.
- Меню и команды прежние — никаких дополнительных действий.

**Обновление:** распакуйте архив целиком, закройте игру и выберите **2 — применить / обновить патч**. Интернет нужен, только если модели ещё не скачаны (Q8 + кодек — около **1,3 ГБ**).

Неофициальный проект, не связанный с разработчиками игры. Используйте на свой страх и риск.

---

## English

**SwyfPatcher 2.9.6 — Game Build 2026-10-26 (buildid 26208975) Support**

The game updated again — the patcher works again. The new table entry was derived from the actual game files: every edit was verified byte-by-byte and all patch variants were re-computed.

- Checked against real **2026-10-26** files; earlier 0.1.91-swyf and 0.1.89-swyf builds remain supported.
- The HardwareEligible and model-verification methods are byte-identical to 0.1.91 except metadata tokens — confirmed by IL comparison.
- All previous fixes carry over: 300/120 s timeouts, CPU/GPU (Vulkan) selection, and the Q4 model-check bypass.
- Worker and models are unchanged — no re-download is needed when models are already present.
- Same menu and commands as before — no extra steps required.

**Update:** extract the entire archive, close the game, and select **2 — Apply / update patch**. Internet is needed only if the models are not downloaded yet (Q8 + codec: about **1.3 GB**).

This is an unofficial project, not affiliated with the game's developers. Use at your own risk.
