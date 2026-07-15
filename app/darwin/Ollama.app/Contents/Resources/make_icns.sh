#!/bin/bash

# Проверка, передан ли аргумент
if [ -z "$1" ]; then
    echo "Использование: $0 <путь_к_изображению.jpg>"
    echo "Пример: $0 icon.jpg"
    exit 1
fi

INPUT_FILE="$1"
BASENAME=$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')
OUTPUT_ICNS="${BASENAME}.icns"
ICONSET="${BASENAME}.iconset"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Ошибка: Файл '$INPUT_FILE' не найден!"
    exit 1
fi

echo "Начинаем конвертацию '$INPUT_FILE' в '$OUTPUT_ICNS'..."

# Удаляем временную папку, если она осталась от прошлой ошибки
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Добавлено -s format png, чтобы sips не ругался на расширение
sips -z 16 16     "$INPUT_FILE" --out "$ICONSET/icon_16x16.png" -s format png > /dev/null
sips -z 32 32     "$INPUT_FILE" --out "$ICONSET/icon_16x16@2x.png" -s format png > /dev/null
sips -z 32 32     "$INPUT_FILE" --out "$ICONSET/icon_32x32.png" -s format png > /dev/null
sips -z 64 64     "$INPUT_FILE" --out "$ICONSET/icon_32x32@2x.png" -s format png > /dev/null
sips -z 128 128   "$INPUT_FILE" --out "$ICONSET/icon_128x128.png" -s format png > /dev/null
sips -z 256 256   "$INPUT_FILE" --out "$ICONSET/icon_128x128@2x.png" -s format png > /dev/null
sips -z 256 256   "$INPUT_FILE" --out "$ICONSET/icon_256x256.png" -s format png > /dev/null
sips -z 512 512   "$INPUT_FILE" --out "$ICONSET/icon_256x256@2x.png" -s format png > /dev/null
sips -z 512 512   "$INPUT_FILE" --out "$ICONSET/icon_512x512.png" -s format png > /dev/null
sips -z 1024 1024 "$INPUT_FILE" --out "$ICONSET/icon_512x512@2x.png" -s format png > /dev/null

# Конвертируем папку .iconset в файл .icns
iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"

if [ -f "$OUTPUT_ICNS" ]; then
    rm -rf "$ICONSET"
    echo "✅ Готово! Иконка успешно сохранена как '$OUTPUT_ICNS'."
else
    echo "❌ Ошибка при создании .icns файла."
    echo "Убедитесь, что исходное изображение имеет соотношение сторон 1:1 (например, 1024x1024 пикселей)."
    exit 1
fi