# SwyfPatcher 2.9.7

[![Русский](https://img.shields.io/badge/Русский-выбран-2563eb?style=for-the-badge)](#русский)
[![English](https://img.shields.io/badge/English-switch-555?style=for-the-badge)](#english)

## Русский

**Исправлено раннее прерывание ожидания Qwen в игре 0.1.92.**

Очередь игры могла отменять озвучку через 30 секунд без первого звука, хотя внутренние таймауты Qwen уже были увеличены. Теперь предел ожидания согласован — 300 секунд. Появление звука, ошибка или завершение звонка по-прежнему прекращают ожидание сразу.

- Обновление с 2.9.6 сохраняет режим CPU/GPU и модель.
- Автовосстановление моделей, логи и привычное меню сохранены.
- Исправные модели скачивать заново не нужно; воркер остаётся версии 2.9.3.

**Установка:** распакуйте архив целиком, закройте игру и выберите **2 — применить / обновить патч**. После теста соберите ZIP пунктом **7**.

Исправление проверено на коде предоставленной игры. Скорость и получение звука на RTX 2070 SUPER ещё требуют Windows-теста; увеличение таймаута не ускоряет генерацию.

Неофициальный проект, не связанный с разработчиками игры. Используйте на свой страх и риск.

## English

**Fixed premature Qwen waiting cancellation in game 0.1.92.**

The game's queue could cancel speech after 30 seconds without first audio, even though Qwen's internal timeouts had already been extended. The queue now uses the same 300-second limit. Available audio, errors, and hanging up still end the wait immediately.

- Updating from 2.9.6 preserves CPU/GPU mode and model choice.
- Automatic model repair, logging, and the existing menu are retained.
- Healthy models need no new download; the worker remains at version 2.9.3.

**Install:** extract the complete archive, close the game, and select **2 — Apply / update patch**. Collect a ZIP with option **7** after testing.

Validated against the supplied game code. Speed and successful audio on RTX 2070 SUPER still need Windows testing; a longer timeout does not accelerate generation.

This is an unofficial project, not affiliated with the game's developers. Use at your own risk.
