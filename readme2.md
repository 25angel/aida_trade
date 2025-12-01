# Как работает CoinGecko API

## Что такое CoinGecko API?

**CoinGecko API** - это публичный бесплатный API, который предоставляет данные о криптовалютах. Он **не требует регистрации или API ключа** для базовых запросов.

## Как это работает?

### 1. Как делается запрос

В нашем приложении мы используем HTTP GET запрос:

```dart
// Формируем URL с параметрами
final url = Uri.parse(
  'https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=50&page=1'
);

// Отправляем HTTP GET запрос
final response = await http.get(url);
```

**Параметры запроса:**
- `vs_currency=usd` - валюта для отображения цен (USD)
- `order=market_cap_desc` - сортировка по рыночной капитализации (по убыванию)
- `per_page=50` - количество монет на странице
- `page=1` - номер страницы
- `sparkline=false` - не включать мини-графики

### 2. Что возвращает API

API возвращает JSON массив с данными о криптовалютах. Пример ответа:

```json
[
  {
    "id": "bitcoin",
    "symbol": "btc",
    "name": "Bitcoin",
    "image": "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png",
    "current_price": 86199,
    "price_change_percentage_24h": 2.12544,
    "total_volume": 43630646471,
    "market_cap": 1719590933320,
    "market_cap_rank": 1,
    "high_24h": 86221,
    "low_24h": 83540,
    "last_updated": "2025-11-23T02:53:33.194Z"
  },
  {
    "id": "ethereum",
    "symbol": "eth",
    "name": "Ethereum",
    "current_price": 2827.64,
    "price_change_percentage_24h": 3.0733,
    ...
  }
]
```

### 3. Как парсим данные

После получения ответа от API, мы декодируем JSON и преобразуем его в наши модели:

```dart
// Проверяем успешность запроса
if (response.statusCode == 200) {
  // Декодируем JSON строку в объект Dart
  final List<dynamic> data = json.decode(response.body);
  
  // Преобразуем каждый элемент в CryptoModel
  return data.map((json) => CryptoModel.fromJson(json)).toList();
} else {
  throw Exception('Failed to load markets: ${response.statusCode}');
}
```

### 4. Структура модели CryptoModel

Модель `CryptoModel` имеет метод `fromJson`, который извлекает нужные поля из JSON:

```dart
factory CryptoModel.fromJson(Map<String, dynamic> json) {
  return CryptoModel(
    id: json['id'],                    // "bitcoin"
    symbol: (json['symbol'] ?? '').toUpperCase(),  // "btc" -> "BTC"
    name: json['name'],                // "Bitcoin"
    price: (json['current_price'] ?? 0.0).toDouble(),  // 86199
    change24h: (json['price_change_percentage_24h'] ?? 0.0).toDouble(), // 2.12544
    volume24h: (json['total_volume'] ?? 0.0).toDouble(),  // 43630646471
    marketCap: json['market_cap']?.toDouble(),  // 1719590933320
    imageUrl: json['image'],           // URL картинки
  );
}
```

### 5. Использование в приложении

Когда экран загружается:

1. **Вызывается метод** `CryptoApiService.getMarkets()`
2. **Отправляется HTTP запрос** к CoinGecko API
3. **Получаем JSON ответ** с данными о криптовалютах
4. **Парсим данные** в список объектов `CryptoModel`
5. **Отображаем в UI** - список криптовалют с ценами и изменениями

**Пример использования:**

```dart
@override
void initState() {
  super.initState();
  _loadCryptoData();
}

Future<void> _loadCryptoData() async {
  setState(() {
    _isLoading = true;
  });
  
  try {
    final data = await CryptoApiService.getMarkets(perPage: 20);
    setState(() {
      _cryptoList = data;
      _isLoading = false;
    });
  } catch (e) {
    setState(() {
      _isLoading = false;
    });
  }
}
```

## Преимущества CoinGecko API

✅ **Бесплатный** - не требует регистрации  
✅ **Публичный** - не нужен API ключ для базовых запросов  
✅ **Актуальные данные** - обновляются в реальном времени  
✅ **Большой выбор** - более 19,000 криптовалют  
✅ **Лимиты**: 10-50 запросов в минуту (бесплатный план)

## Документация

Полная документация API доступна по адресу:
**https://www.coingecko.com/en/api/documentation**

## Тестирование API

Вы можете протестировать API прямо в браузере, открыв эту ссылку:

```
https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=5
```

Или через curl в терминале:

```bash
curl "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=3&page=1&sparkline=false"
```

## Как это работает технически?

Это стандартный **REST API** - просто HTTP запросы, как открытие веб-страницы, только вместо HTML получаем JSON с данными.

**Процесс:**
1. Приложение формирует URL с параметрами
2. Отправляет HTTP GET запрос на сервер CoinGecko
3. Сервер обрабатывает запрос и возвращает JSON
4. Приложение получает ответ и парсит его
5. Данные отображаются в интерфейсе

**Обработка ошибок:**

Если API недоступен или произошла ошибка, приложение использует моковые данные (заглушки), чтобы пользователь всегда видел какой-то контент:

```dart
catch (e) {
  // В случае ошибки возвращаем моковые данные
  return _getMockData();
}
```

## Дополнительные возможности API

CoinGecko API предоставляет множество других endpoints:

- `/coins/{id}` - детальная информация о конкретной монете
- `/coins/{id}/history` - исторические данные
- `/coins/{id}/market_chart` - данные для графиков
- `/simple/price` - простые цены без лишних данных
- `/trending` - трендовые монеты
- И многое другое...

Все это можно использовать для расширения функциональности приложения!

