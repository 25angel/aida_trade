#!/bin/bash

# Скрипт для безопасной выгрузки проекта на GitHub
# Убедитесь, что все секретные файлы не закоммичены!

echo "🔍 Проверка секретных файлов..."

# Проверяем, что секретные файлы игнорируются
if git check-ignore lib/config/api_config.dart lib/firebase_options.dart ios/Runner/GoogleService-Info.plist > /dev/null 2>&1; then
    echo "✅ Секретные файлы правильно игнорируются"
else
    echo "❌ ОШИБКА: Секретные файлы не игнорируются!"
    echo "Проверьте .gitignore файл"
    exit 1
fi

# Проверяем, что секретные файлы не в индексе
if git ls-files | grep -E "(api_config\.dart|firebase_options\.dart|GoogleService-Info\.plist)" > /dev/null; then
    echo "❌ ОШИБКА: Секретные файлы уже закоммичены!"
    echo "Используйте: git rm --cached <файл> для удаления из индекса"
    exit 1
else
    echo "✅ Секретные файлы не закоммичены"
fi

# Проверяем наличие примеров файлов
if [ ! -f "lib/config/api_config.example.dart" ] || \
   [ ! -f "lib/firebase_options.example.dart" ] || \
   [ ! -f "ios/Runner/GoogleService-Info.example.plist" ]; then
    echo "⚠️  Предупреждение: Некоторые примеры файлов отсутствуют"
else
    echo "✅ Примеры файлов присутствуют"
fi

echo ""
echo "📦 Подготовка к выгрузке..."

# Проверяем наличие remote
if git remote | grep -q origin; then
    echo "✅ Remote 'origin' уже настроен"
    git remote -v
else
    echo "⚠️  Remote 'origin' не настроен"
    echo "Используйте: git remote add origin <URL>"
fi

echo ""
echo "🚀 Готово к выгрузке!"
echo ""
echo "Для выгрузки выполните:"
echo "  git add ."
echo "  git commit -m 'Initial commit'"
echo "  git push -u origin main"
echo ""
echo "Или если ветка называется master:"
echo "  git branch -M main"
echo "  git push -u origin main"

