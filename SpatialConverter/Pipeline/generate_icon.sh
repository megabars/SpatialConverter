#!/bin/bash

# Скрипт для генерации иконки приложения из SF Symbol или изображения
# Требует: imagemagick (brew install imagemagick)

set -e

# Цвета
BLUE="#007AFF"
GRADIENT_START="#0A84FF"
GRADIENT_END="#5E5CE6"

# Проверка imagemagick
if ! command -v convert &> /dev/null; then
    echo "❌ ImageMagick не установлен. Установите: brew install imagemagick"
    exit 1
fi

ICON_DIR="Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"

echo "🎨 Генерация иконки для Spatial Video Converter..."

# Создаём базовую иконку 1024×1024 с символом видео и 3D эффектом
convert -size 1024x1024 \
    -define gradient:angle=135 \
    gradient:"$GRADIENT_START"-"$GRADIENT_END" \
    -gravity center \
    \( -size 700x700 xc:none \
       -fill white \
       -draw "roundrectangle 0,0 700,700 80,80" \
       -fill none \
       -stroke white \
       -strokewidth 40 \
       -draw "roundrectangle 200,250 500,450 20,20" \
       -draw "polyline 520,290 620,350 520,410" \
       -strokewidth 20 \
       -draw "line 100,200 100,500" \
       -draw "line 300,200 300,500" \
    \) \
    -compose over -composite \
    "$ICON_DIR/icon_1024.png"

# Генерируем все необходимые размеры
declare -a sizes=("16" "32" "64" "128" "256" "512")
declare -a scales=("" "@2x")

for size in "${sizes[@]}"; do
    for scale in "${scales[@]}"; do
        if [ "$scale" == "@2x" ]; then
            pixel_size=$((size * 2))
        else
            pixel_size=$size
        fi
        
        output_name="icon_${size}x${size}${scale}.png"
        
        convert "$ICON_DIR/icon_1024.png" \
            -resize ${pixel_size}x${pixel_size} \
            "$ICON_DIR/$output_name"
        
        echo "✅ Создана иконка: $output_name (${pixel_size}×${pixel_size})"
    done
done

echo ""
echo "🎉 Иконки сгенерированы в $ICON_DIR"
echo ""
echo "📝 Следующие шаги:"
echo "   1. Откройте Assets.xcassets в Xcode"
echo "   2. Перетащите созданные .png файлы в AppIcon"
echo "   3. Или используйте готовую иконку если есть дизайн"
