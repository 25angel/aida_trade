# Инструкция по публикации на GitHub

## Шаг 1: Создайте репозиторий на GitHub

1. Перейдите на [GitHub](https://github.com)
2. Нажмите кнопку "+" в правом верхнем углу
3. Выберите "New repository"
4. Введите название репозитория (например: `bybit-clone`)
5. Выберите видимость (Public или Private)
6. **НЕ** добавляйте README, .gitignore или лицензию (они уже есть)
7. Нажмите "Create repository"

## Шаг 2: Подключите локальный репозиторий к GitHub

После создания репозитория GitHub покажет инструкции. Выполните команды:

```bash
# Добавьте remote (замените YOUR_USERNAME и YOUR_REPO на свои значения)
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git

# Переименуйте ветку в main (если нужно)
git branch -M main

# Отправьте код на GitHub
git push -u origin main
```

## Альтернативный способ (через SSH)

Если вы используете SSH ключи:

```bash
git remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
git branch -M main
git push -u origin main
```

## Проверка

После успешного push проверьте, что:
- ✅ Все файлы загружены
- ✅ Файлы с секретами НЕ видны в репозитории:
  - `lib/firebase_options.dart` - должен отсутствовать
  - `ios/Runner/GoogleService-Info.plist` - должен отсутствовать
  - `lib/config/api_config.dart` - должен отсутствовать
- ✅ Примеры файлов присутствуют:
  - `lib/firebase_options.example.dart` - должен быть
  - `ios/Runner/GoogleService-Info.example.plist` - должен быть
  - `lib/config/api_config.example.dart` - должен быть

## Если что-то пошло не так

Если случайно закоммитили секреты:

```bash
# Удалите файл из истории (ОСТОРОЖНО!)
git rm --cached lib/firebase_options.dart
git rm --cached ios/Runner/GoogleService-Info.plist
git rm --cached lib/config/api_config.dart

# Создайте новый коммит
git commit -m "Remove sensitive files"

# Отправьте изменения
git push
```

**Важно**: Если секреты уже были отправлены на GitHub, их нужно:
1. Удалить из истории (используя `git filter-branch` или BFG Repo-Cleaner)
2. Изменить все секреты (API ключи, токены и т.д.), так как они скомпрометированы

