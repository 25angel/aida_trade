# Настройка Firebase для Bybit App

## Шаги настройки:

1. **Создайте проект в Firebase Console:**
   - Перейдите на https://console.firebase.google.com/
   - Создайте новый проект или выберите существующий

2. **Добавьте iOS приложение:**
   - В настройках проекта нажмите "Add app" → iOS
   - Введите Bundle ID (можно найти в `ios/Runner.xcodeproj`)
   - Скачайте `GoogleService-Info.plist`
   - Поместите файл в `ios/Runner/GoogleService-Info.plist`

3. **Включите Authentication:**
   - В Firebase Console перейдите в Authentication
   - Включите "Google" как метод входа
   - Добавьте email поддержки (опционально)

4. **Создайте Firestore Database:**
   - Перейдите в Firestore Database
   - Создайте базу данных в режиме "Test mode" (для разработки)
   - Выберите регион (например, us-central1)

5. **Установите Firebase CLI (опционально, для автоматической настройки):**
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

6. **Настройте Firebase в Flutter:**
   ```bash
   flutter pub get
   flutterfire configure
   ```
   Это автоматически создаст `firebase_options.dart`

7. **Правила безопасности Firestore (для разработки):**
   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{userId} {
         allow read, write: if request.auth != null && request.auth.uid == userId;
         match /favorites/{document=**} {
           allow read, write: if request.auth != null && request.auth.uid == userId;
         }
         match /portfolio/{document=**} {
           allow read, write: if request.auth != null && request.auth.uid == userId;
         }
       }
     }
   }
   ```

## Структура данных в Firestore:

```
users/
  {userId}/
    email: string
    displayName: string
    photoURL: string
    createdAt: timestamp
    updatedAt: timestamp
    favorites/
      coins/
        Спот: [coin1, coin2, ...]
        Деривативы: [coin1, coin2, ...]
        TradFi: [coin1, coin2, ...]
    portfolio/
      coins/
        coins: [coin1, coin2, ...]
```

## Важные замечания:

- Для продакшена измените правила безопасности Firestore
- Не забудьте настроить правильные права доступа
- GoogleService-Info.plist должен быть добавлен в .gitignore (уже добавлен)

