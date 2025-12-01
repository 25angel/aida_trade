# Переключение между моковыми и реальными данными

## Способ 1: Быстрое переключение в коде (для разработки)

В файле `lib/services/mock_portfolio_service.dart` измените значение:

```dart
static bool _useMockData = false; // Изменить на false для реальных данных
```

**Важно:** Если вы изменили значение в коде, оно имеет приоритет над сохраненным в SharedPreferences. 
Если нужно очистить сохраненное значение, вызовите:
```dart
await MockPortfolioService.reset();
```

## Способ 2: Программное переключение (рекомендуется)

Используйте метод `setUseMockData()` для переключения во время выполнения:

```dart
// Включить моковые данные
await MockPortfolioService.setUseMockData(true);

// Включить реальные данные
await MockPortfolioService.setUseMockData(false);
```

Настройка автоматически сохраняется в SharedPreferences и будет использоваться при следующем запуске приложения.

## Способ 3: Добавить переключатель в настройки приложения

Можно добавить переключатель в настройки, чтобы пользователь мог выбирать:

```dart
SwitchListTile(
  title: Text('Использовать тестовые данные'),
  value: MockPortfolioService.useMockData,
  onChanged: (value) async {
    await MockPortfolioService.setUseMockData(value);
    setState(() {}); // Обновить UI
  },
)
```

## Текущее состояние

По умолчанию используется `true` (моковые данные). При первом запуске приложения настройка загружается из SharedPreferences, если там ничего нет - используется значение по умолчанию `true`.

## Где используются моковые данные

- `HomeScreen` - баланс и P&L за сегодня
- `WalletScreen` - все балансы портфеля
- `AnalysisScreen` - все графики и метрики

При переключении на реальные данные (`useMockData = false`), все экраны автоматически начнут использовать реальные API вызовы из `CryptoApiService`.

