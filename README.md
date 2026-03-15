# SpatialConverter

macOS-приложение для конвертации Apple Spatial Video (MV-HEVC, iPhone 15 Pro/16) в Side-by-Side стереовидео (3840×1080) для VR-плееров: DeoVR, Skybox VR и других.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue) ![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)

## Возможности

- Конвертация MV-HEVC Spatial Video в SBS формат 3840×1080
- Два пути декодирования: AVFoundation (основной) → ffmpeg (автоматический fallback)
- GPU-ускоренный композитинг через Metal / CoreImage
- H.264 и H.265 выходной кодек
- Три пресета качества (высокое / среднее / компактное)
- Аудио passthrough без перекодирования
- Пакетная обработка, drag & drop, иконка в доке
- Автоматическое именование `{имя}_SBS_LR.mp4` — DeoVR распознаёт формат автоматически

## Требования

- macOS 14.0+ (Sonoma)
- Xcode 15+ (для сборки)
- ffmpeg — опционально, используется как запасной путь декодирования

```bash
brew install ffmpeg
```

## Сборка и запуск

Откройте `SpatialConverter.xcodeproj` в Xcode и нажмите ⌘R.

## Использование

1. Перетащите `.mov` / `.mp4` файлы в окно или на иконку в доке
2. Настройте параметры в правой панели
3. Нажмите «Конвертировать»

### Настройки

| Параметр | Варианты |
|---|---|
| Выходная папка | Рядом с исходным файлом / своя папка |
| Кодек | H.264 (совместимость) / H.265 (меньший размер) |
| Качество | Высокое · Среднее · Компактное |

**Битрейты:**

| Качество | H.264 | H.265 |
|---|---|---|
| Высокое | 35 Мбит/с | 20 Мбит/с |
| Среднее | 20 Мбит/с | 12 Мбит/с |
| Компактное | 10 Мбит/с | 6 Мбит/с |

## Индикаторы состояния

| Бейдж | Значение |
|---|---|
| 🔵 AVFoundation + ✅ | Конвертировано через AVFoundation |
| 🟠 ffmpeg + ✅ | Использован резервный путь ffmpeg |
| ❌ | Ошибка (наведите курсор для деталей) |

## Архитектура

```
ContentView (SwiftUI)
    └── ConversionQueue (serial, @MainActor)
            └── ConversionPipeline (actor)
                    ├── SpatialVideoValidator   — проверка MV-HEVC
                    ├── SpatialVideoDecoder     — извлечение стереовидов (AVFoundation)
                    ├── FFmpegFallback          — запасной путь
                    ├── SBSCompositor           — Metal/CoreImage композитинг
                    └── SBSEncoder              — H.264/H.265 → MP4
```

## Решение проблем

**«Не пространственное видео»** — убедитесь, что видео снято на iPhone 15 Pro или новее в режиме Spatial Video (Настройки → Камера → Форматы → Apple Vision Pro).

**ffmpeg не найден** — установите через Homebrew: `brew install ffmpeg`. Без ffmpeg конвертация возможна только если AVFoundation успешно извлекает стереовиды.

## Лицензия

MIT
