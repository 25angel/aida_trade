import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/crypto_model.dart';
import '../config/app_constants.dart';
import 'crypto_filter_service.dart';
import 'crypto_sort_service.dart';

class CryptoApiService {
  static const String baseUrl = AppConstants.bybitBaseUrl;

  // Генерация подписи для приватных запросов
  static String _generateSignature({
    required String apiSecret,
    required int timestamp,
    required String recvWindow,
    required Map<String, dynamic> params,
  }) {
    // Сортируем параметры по ключу
    final sortedParams = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    // Создаем query string
    final queryString =
        sortedParams.entries.map((e) => '${e.key}=${e.value}').join('&');

    // Создаем строку для подписи
    final signString = '$timestamp$apiSecret$recvWindow$queryString';

    // Генерируем HMAC SHA256
    final key = utf8.encode(apiSecret);
    final bytes = utf8.encode(signString);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);

    return digest.toString();
  }

  // Выполнить приватный запрос к Bybit API
  static Future<Map<String, dynamic>> _privateRequest({
    required String endpoint,
    required String method,
    Map<String, dynamic>? params,
  }) async {
    // API ключи больше не требуются - возвращаем заглушку
    // Для реальных данных нужно будет настроить API ключи в будущем
    throw Exception(
        'Приватные запросы отключены. Используйте публичные данные.');

    // Старый код (закомментирован, так как недостижим после throw):
    /*
    final isConfigured = await ApiConfig.isConfigured;
    if (!isConfigured) {
      throw Exception('API ключи не настроены. Пожалуйста, войдите в аккаунт.');
    }
    final apiKey = await ApiConfig.apiKey;
    final apiSecret = await ApiConfig.apiSecret;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final recvWindow = '5000';

    final requestParams = <String, dynamic>{
      'api_key': apiKey,
      'timestamp': timestamp.toString(),
      'recv_window': recvWindow,
      ...?params,
    };

    final signature = _generateSignature(
      apiSecret: apiSecret,
      timestamp: timestamp,
      recvWindow: recvWindow,
      params: requestParams,
    );

    requestParams['sign'] = signature;

    final url = Uri.parse('$baseUrl$endpoint');
    final response = method == 'GET'
        ? await http.get(
            url.replace(
                queryParameters:
                    requestParams.map((k, v) => MapEntry(k, v.toString()))),
          )
        : await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestParams),
          );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['retCode'] == 0) {
        return data;
      } else {
        throw Exception('Bybit API error: ${data['retMsg']}');
      }
    } else {
      throw Exception('HTTP error: ${response.statusCode}');
    }
    */
  }

  // Получить список криптовалют с ценами через Bybit API
  static Future<List<CryptoModel>> getMarkets({
    String category = 'spot',
    int perPage = AppConstants.defaultPerPage,
  }) async {
    try {
      // Bybit API v5 - получение тикеров для спотовой торговли
      final url = Uri.parse(
        '$baseUrl/v5/market/tickers?category=$category&limit=$perPage',
      );

      final response = await http.get(url).timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['retCode'] == 0 && data['result'] != null) {
          final List<dynamic> list = data['result']['list'] ?? [];
          return list.map((json) => CryptoModel.fromBybitJson(json)).toList();
        } else {
          throw Exception('Bybit API error: ${data['retMsg']}');
        }
      } else {
        throw Exception('Failed to load markets: ${response.statusCode}');
      }
    } catch (e) {
      // В случае ошибки возвращаем моковые данные
      return _getMockData();
    }
  }

  // Универсальный метод для получения данных по категории и подкатегории
  // Каждая комбинация обрабатывается отдельно для правильной фильтрации
  static Future<List<CryptoModel>> getMarketsByCategory({
    required String
        mainCategory, // Популярные, Новые, Активные монеты, Лидеры падения, Оборот
    required String
        subCategory, // Спот, Alpha, Деривативы, TradFi, Фьючерсы, Опцион
    int perPage = 50,
  }) async {
    // Определяем тип рынка для API
    String apiCategory = 'spot';
    if (subCategory == 'Деривативы' || subCategory == 'Фьючерсы') {
      apiCategory = 'linear';
    } else if (subCategory == 'Опцион') {
      apiCategory = 'option';
    } else if (subCategory == 'TradFi') {
      apiCategory = 'spot';
    } else {
      apiCategory = 'spot';
    }

    try {
      // Получаем все тикеры для данного типа рынка
      List<dynamic> list = [];

      if (subCategory == 'Опцион') {
        // Для опционов нужно указать baseCoin для каждого базового актива
        // Получаем опционы для популярных базовых активов ПАРАЛЛЕЛЬНО
        final futures = AppConstants.optionBaseCoins.map((baseCoin) async {
          try {
            final url = Uri.parse(
              '$baseUrl/v5/market/tickers?category=option&baseCoin=$baseCoin',
            );
            final response =
                await http.get(url).timeout(AppConstants.requestTimeout);

            if (response.statusCode == 200) {
              final Map<String, dynamic> data = json.decode(response.body);
              if (data['retCode'] == 0 && data['result'] != null) {
                return data['result']['list'] as List<dynamic>? ?? [];
              }
            }
            return <dynamic>[];
          } catch (e) {
            // Пропускаем ошибки для отдельных базовых активов
            return <dynamic>[];
          }
        });

        // Ждем все запросы параллельно
        final results = await Future.wait(futures);
        for (final result in results) {
          list.addAll(result);
        }
      } else {
        // Для остальных категорий используем обычный запрос
        // Используем оптимизированный лимит для быстрой загрузки
        final url = Uri.parse(
          '$baseUrl/v5/market/tickers?category=$apiCategory&limit=${AppConstants.optimizedPerPage}',
        );
        final response =
            await http.get(url).timeout(AppConstants.requestTimeout);

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = json.decode(response.body);
          if (data['retCode'] == 0 && data['result'] != null) {
            list = data['result']['list'] ?? [];
          } else {
            throw Exception('Bybit API error: ${data['retMsg']}');
          }
        } else {
          throw Exception('Failed to load markets: ${response.statusCode}');
        }
      }

      // Обрабатываем полученные данные
      if (list.isNotEmpty) {
        // Для опционов сначала фильтруем по исходным данным JSON, затем парсим
        List<dynamic> filteredList = list;
        if (subCategory == 'Опцион') {
          // Фильтруем опционы на уровне JSON (до парсинга)
          filteredList = list
              .where((json) => CryptoFilterService.isOptionJson(
                  json as Map<String, dynamic>))
              .toList();
        }

        List<CryptoModel> coins = filteredList.map((json) {
          final coin = CryptoModel.fromBybitJson(json);
          // Для опционов пересчитываем change24h в зависимости от категории
          if (subCategory == 'Опцион' && coin.symbol.contains('-')) {
            final highPrice =
                double.tryParse(json['highPrice24h']?.toString() ?? '0') ?? 0.0;
            final lowPrice =
                double.tryParse(json['lowPrice24h']?.toString() ?? '0') ?? 0.0;

            if (highPrice > 0 && lowPrice > 0) {
              double newChange24h = 0.0;

              if (mainCategory == 'Лидеры падения') {
                // Для "Лидеры падения" - падение от highPrice24h к lowPrice24h
                newChange24h = ((lowPrice - highPrice) / highPrice) * 100;
              } else if (mainCategory == 'Активные монеты') {
                // Для "Активные монеты" - рост от lowPrice24h к highPrice24h
                newChange24h = ((highPrice - lowPrice) / lowPrice) * 100;
              } else {
                // Для остальных категорий используем change24h из API
                newChange24h = coin.change24h;
              }

              // Создаем новый CryptoModel с пересчитанным change24h
              return CryptoModel(
                id: coin.id,
                symbol: coin.symbol,
                name: coin.name,
                price: coin.price,
                change24h: newChange24h,
                volume24h: coin.volume24h,
                turnover24h: coin.turnover24h,
                marketCap: coin.marketCap,
                imageUrl: coin.imageUrl,
              );
            }
          }
          return coin;
        }).toList();

        // Для опционов дополнительно проверяем после парсинга
        if (subCategory == 'Опцион') {
          coins = coins.where((coin) {
            return coin.symbol.contains('-') &&
                coin.volume24h > AppConstants.minVolume24h;
          }).toList();
        }

        // Фильтрация по подкатегории
        var filtered = CryptoFilterService.filterBySubCategory(
          coins,
          subCategory,
        );

        // Для категории "Активные монеты" показываем только положительные монеты
        // (кроме опционов, у них своя логика)
        if (mainCategory == 'Активные монеты' && subCategory != 'Опцион') {
          filtered = filtered.where((coin) => coin.change24h > 0).toList();
        }

        // Сортировка по главной категории
        CryptoSortService.sortByCategory(filtered, mainCategory, subCategory);

        // Ограничиваем результат до perPage ДО возврата (оптимизация памяти)
        return filtered.take(perPage).toList();
      } else {
        // Если список пуст, возвращаем моковые данные
        return _getMockData();
      }
    } catch (e) {
      return _getMockData();
    }
  }

  // Получить монеты для категории Спот (популярные монеты для спотовой торговли)
  static Future<List<CryptoModel>> getSpotMarkets({
    int perPage = AppConstants.defaultPerPage,
  }) async {
    try {
      // Bybit API v5 - спотовые тикеры
      final url = Uri.parse(
        '$baseUrl/v5/market/tickers?category=spot&limit=$perPage',
      );

      final response = await http.get(url).timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['retCode'] == 0 && data['result'] != null) {
          final List<dynamic> list = data['result']['list'] ?? [];
          final List<CryptoModel> coins =
              list.map((json) => CryptoModel.fromBybitJson(json)).toList();

          // Фильтруем: исключаем стабильные монеты, достаточный объем
          return coins
              .where((coin) =>
                  !AppConstants.stablecoinSymbols.contains(coin.symbol) &&
                  coin.volume24h > AppConstants.minVolume24h &&
                  coin.price > 0.01)
              .take(perPage)
              .toList();
        } else {
          throw Exception('Bybit API error: ${data['retMsg']}');
        }
      } else {
        throw Exception('Failed to load spot markets: ${response.statusCode}');
      }
    } catch (e) {
      return _getMockData();
    }
  }

  // Получить монеты для категории Alpha (растущие монеты с высоким потенциалом)
  static Future<List<CryptoModel>> getAlphaMarkets({
    int perPage = AppConstants.defaultPerPage,
  }) async {
    try {
      // Bybit API v5 - получаем все спотовые тикеры и сортируем по росту
      final url = Uri.parse(
        '$baseUrl/v5/market/tickers?category=spot&limit=${AppConstants.maxPerPage}',
      );

      final response = await http.get(url).timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['retCode'] == 0 && data['result'] != null) {
          final List<dynamic> list = data['result']['list'] ?? [];
          final List<CryptoModel> coins =
              list.map((json) => CryptoModel.fromBybitJson(json)).toList();

          // Фильтруем и сортируем: положительный рост, достаточный объем, исключаем стабильные
          final filtered = CryptoFilterService.filterBySubCategory(
            coins,
            'Alpha',
          );

          // Сортируем по проценту роста (по убыванию)
          filtered.sort((a, b) => b.change24h.compareTo(a.change24h));

          return filtered.take(perPage).toList();
        } else {
          throw Exception('Bybit API error: ${data['retMsg']}');
        }
      } else {
        throw Exception('Failed to load alpha markets: ${response.statusCode}');
      }
    } catch (e) {
      return _getAlphaMockData();
    }
  }

  // Получить монеты для категории Деривативы (высоколиквидные монеты для торговли с плечом)
  static Future<List<CryptoModel>> getDerivativesMarkets({
    int perPage = AppConstants.defaultPerPage,
  }) async {
    try {
      // Bybit API v5 - деривативы (линейные контракты)
      final url = Uri.parse(
        '$baseUrl/v5/market/tickers?category=linear&limit=${AppConstants.maxPerPage}',
      );

      final response = await http.get(url).timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['retCode'] == 0 && data['result'] != null) {
          final List<dynamic> list = data['result']['list'] ?? [];
          final List<CryptoModel> coins =
              list.map((json) => CryptoModel.fromBybitJson(json)).toList();

          // Фильтруем: очень высокий объем, исключаем стабильные монеты
          final filtered = coins
              .where((coin) =>
                  !AppConstants.stablecoinSymbols.contains(coin.symbol) &&
                  coin.volume24h > AppConstants.minVolume24hDerivatives)
              .toList();

          // Сортируем по объему (по убыванию)
          filtered.sort((a, b) => b.volume24h.compareTo(a.volume24h));

          return filtered.take(perPage).toList();
        } else {
          throw Exception('Bybit API error: ${data['retMsg']}');
        }
      } else {
        throw Exception(
            'Failed to load derivatives markets: ${response.statusCode}');
      }
    } catch (e) {
      return _getMockData();
    }
  }

  // Получить монеты для категории TradFi (стабильные монеты и традиционные активы)
  static Future<List<CryptoModel>> getTradFiMarkets({
    int perPage = AppConstants.defaultPerPage,
  }) async {
    try {
      // Bybit API v5 - получаем спотовые тикеры и фильтруем стабильные монеты
      final url = Uri.parse(
        '$baseUrl/v5/market/tickers?category=spot&limit=${AppConstants.maxPerPage}',
      );

      final response = await http.get(url).timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['retCode'] == 0 && data['result'] != null) {
          final List<dynamic> list = data['result']['list'] ?? [];
          final List<CryptoModel> coins =
              list.map((json) => CryptoModel.fromBybitJson(json)).toList();

          // Строгий фильтр: ТОЛЬКО стабильные монеты
          final stablecoins = CryptoFilterService.filterBySubCategory(
            coins,
            'TradFi',
          );

          if (stablecoins.isNotEmpty) {
            return stablecoins.take(perPage).toList();
          }

          // Если стабильных монет не найдено, возвращаем моковые данные
          return _getTradFiMockData();
        } else {
          throw Exception('Bybit API error: ${data['retMsg']}');
        }
      } else {
        throw Exception(
            'Failed to load tradfi markets: ${response.statusCode}');
      }
    } catch (e) {
      return _getTradFiMockData();
    }
  }

  // Получить конкретную криптовалюту по ID (публичный endpoint)
  static Future<CryptoModel?> getCoinById(String coinId) async {
    try {
      final url =
          Uri.parse('$baseUrl/v5/market/tickers?category=spot&symbol=$coinId');
      final response = await http.get(url).timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['retCode'] == 0 && data['result'] != null) {
          final List<dynamic> list = data['result']['list'] ?? [];
          if (list.isNotEmpty) {
            return CryptoModel.fromBybitJson(list[0]);
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Получить книгу ордеров (публичный endpoint)
  static Future<Map<String, dynamic>?> getOrderBook({
    required String symbol,
    String category = 'spot',
    int limit = 25,
  }) async {
    try {
      final url = Uri.parse(
        '$baseUrl/v5/market/orderbook?category=$category&symbol=$symbol&limit=$limit',
      );
      final response = await http.get(url).timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['retCode'] == 0 && data['result'] != null) {
          return data['result'] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      // В случае ошибки возвращаем null
      return null;
    }
  }

  // ========== ПРИВАТНЫЕ ENDPOINTS (требуют API ключи) ==========

  // Получить баланс аккаунта
  static Future<Map<String, dynamic>> getAccountBalance({
    String accountType = 'UNIFIED',
  }) async {
    try {
      final response = await _privateRequest(
        endpoint: '/v5/account/wallet-balance',
        method: 'GET',
        params: {'accountType': accountType},
      );
      return response['result'] ?? {};
    } catch (e) {
      throw Exception('Ошибка получения баланса: $e');
    }
  }

  // Получить информацию об аккаунте
  static Future<Map<String, dynamic>> getAccountInfo() async {
    try {
      final response = await _privateRequest(
        endpoint: '/v5/user/query-api',
        method: 'GET',
        params: {},
      );
      return response['result'] ?? {};
    } catch (e) {
      // Если этот endpoint недоступен, возвращаем пустую карту
      return {};
    }
  }

  // Получить баланс Funding аккаунта
  static Future<Map<String, dynamic>> getFundingBalance() async {
    try {
      return await getAccountBalance(accountType: 'FUND');
    } catch (e) {
      throw Exception('Ошибка получения баланса Funding: $e');
    }
  }

  // Получить баланс Unified Trading аккаунта
  static Future<Map<String, dynamic>> getUnifiedTradingBalance() async {
    try {
      return await getAccountBalance(accountType: 'UNIFIED');
    } catch (e) {
      throw Exception('Ошибка получения баланса Unified Trading: $e');
    }
  }

  // Получить общий баланс всех аккаунтов
  static Future<Map<String, dynamic>> getTotalBalance() async {
    try {
      // Получаем балансы всех типов аккаунтов
      final unified = await getAccountBalance(accountType: 'UNIFIED');
      final funding = await getAccountBalance(accountType: 'FUND');

      // Парсим и суммируем балансы
      double totalUsd = 0.0;
      double totalBtc = 0.0;

      // Обрабатываем Unified баланс
      if (unified['list'] != null && (unified['list'] as List).isNotEmpty) {
        final account = unified['list'][0];
        if (account['coin'] != null) {
          for (var coin in account['coin']) {
            final equity =
                double.tryParse(coin['equity']?.toString() ?? '0') ?? 0.0;
            final usdValue =
                double.tryParse(coin['usdValue']?.toString() ?? '0') ?? 0.0;
            totalUsd += usdValue;
            if (coin['coin'] == 'BTC') {
              totalBtc += equity;
            }
          }
        }
      }

      // Обрабатываем Funding баланс
      if (funding['list'] != null && (funding['list'] as List).isNotEmpty) {
        final account = funding['list'][0];
        if (account['coin'] != null) {
          for (var coin in account['coin']) {
            final equity =
                double.tryParse(coin['equity']?.toString() ?? '0') ?? 0.0;
            final usdValue =
                double.tryParse(coin['usdValue']?.toString() ?? '0') ?? 0.0;
            totalUsd += usdValue;
            if (coin['coin'] == 'BTC') {
              totalBtc += equity;
            }
          }
        }
      }

      // Собираем список всех монет с балансами
      final Map<String, Map<String, dynamic>> coins = {};

      // Обрабатываем Unified баланс
      if (unified['list'] != null && (unified['list'] as List).isNotEmpty) {
        final account = unified['list'][0];
        if (account['coin'] != null) {
          for (var coin in account['coin']) {
            final coinName = coin['coin']?.toString() ?? '';
            final equity =
                double.tryParse(coin['equity']?.toString() ?? '0') ?? 0.0;
            final usdValue =
                double.tryParse(coin['usdValue']?.toString() ?? '0') ?? 0.0;

            if (equity > 0 || usdValue > 0) {
              coins[coinName] = {
                'coin': coinName,
                'equity': equity,
                'usdValue': (coins[coinName]?['usdValue'] ?? 0.0) + usdValue,
                'accountType': 'UNIFIED',
              };
            }
          }
        }
      }

      // Обрабатываем Funding баланс
      if (funding['list'] != null && (funding['list'] as List).isNotEmpty) {
        final account = funding['list'][0];
        if (account['coin'] != null) {
          for (var coin in account['coin']) {
            final coinName = coin['coin']?.toString() ?? '';
            final equity =
                double.tryParse(coin['equity']?.toString() ?? '0') ?? 0.0;
            final usdValue =
                double.tryParse(coin['usdValue']?.toString() ?? '0') ?? 0.0;

            if (equity > 0 || usdValue > 0) {
              if (coins.containsKey(coinName)) {
                coins[coinName]!['usdValue'] =
                    (coins[coinName]!['usdValue'] as double) + usdValue;
                coins[coinName]!['equity'] =
                    (coins[coinName]!['equity'] as double) + equity;
              } else {
                coins[coinName] = {
                  'coin': coinName,
                  'equity': equity,
                  'usdValue': usdValue,
                  'accountType': 'FUND',
                };
              }
            }
          }
        }
      }

      return {
        'totalUsd': totalUsd,
        'totalBtc': totalBtc,
        'availableUsd': totalUsd, // Упрощенно, можно вычислить точнее
        'usedUsd': 0.0, // Можно вычислить из открытых позиций
        'coins': coins.values.toList(), // Список всех монет
      };
    } catch (e) {
      throw Exception('Ошибка получения общего баланса: $e');
    }
  }

  // Получить историю сделок
  static Future<List<Map<String, dynamic>>> getTradeHistory({
    String category = 'spot',
    String? symbol,
    int limit = 50,
  }) async {
    try {
      final params = <String, dynamic>{
        'category': category,
        'limit': limit.toString(),
      };
      if (symbol != null) {
        params['symbol'] = symbol;
      }

      final response = await _privateRequest(
        endpoint: '/v5/execution/list',
        method: 'GET',
        params: params,
      );
      return List<Map<String, dynamic>>.from(response['result']?['list'] ?? []);
    } catch (e) {
      throw Exception('Ошибка получения истории сделок: $e');
    }
  }

  // Разместить ордер (market order)
  static Future<Map<String, dynamic>> placeOrder({
    required String category,
    required String symbol,
    required String side, // Buy или Sell
    required String orderType, // Market, Limit
    required String qty,
    String? price, // Для Limit ордеров
  }) async {
    try {
      final params = <String, dynamic>{
        'category': category,
        'symbol': symbol,
        'side': side,
        'orderType': orderType,
        'qty': qty,
      };
      if (price != null) {
        params['price'] = price;
      }

      final response = await _privateRequest(
        endpoint: '/v5/order/create',
        method: 'POST',
        params: params,
      );
      return response['result'] ?? {};
    } catch (e) {
      throw Exception('Ошибка размещения ордера: $e');
    }
  }

  // Отменить ордер
  static Future<Map<String, dynamic>> cancelOrder({
    required String category,
    required String symbol,
    String? orderId,
    String? orderLinkId,
  }) async {
    try {
      final params = <String, dynamic>{
        'category': category,
        'symbol': symbol,
      };
      if (orderId != null) {
        params['orderId'] = orderId;
      }
      if (orderLinkId != null) {
        params['orderLinkId'] = orderLinkId;
      }

      final response = await _privateRequest(
        endpoint: '/v5/order/cancel',
        method: 'POST',
        params: params,
      );
      return response['result'] ?? {};
    } catch (e) {
      throw Exception('Ошибка отмены ордера: $e');
    }
  }

  // Перевод средств между аккаунтами
  static Future<Map<String, dynamic>> transferBetweenAccounts({
    required String coin,
    required String amount,
    required String fromAccountType, // 'FUND' или 'UNIFIED'
    required String toAccountType, // 'FUND' или 'UNIFIED'
  }) async {
    try {
      final params = <String, dynamic>{
        'coin': coin,
        'amount': amount,
        'fromAccountType': fromAccountType,
        'toAccountType': toAccountType,
        'transferId': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      final response = await _privateRequest(
        endpoint: '/v5/asset/transfer/inter-transfer',
        method: 'POST',
        params: params,
      );
      return response['result'] ?? {};
    } catch (e) {
      throw Exception('Ошибка перевода между аккаунтами: $e');
    }
  }

  // Получить открытые ордера
  static Future<List<Map<String, dynamic>>> getOpenOrders({
    String category = 'spot',
    String? symbol,
  }) async {
    try {
      final params = <String, dynamic>{
        'category': category,
      };
      if (symbol != null) {
        params['symbol'] = symbol;
      }

      final response = await _privateRequest(
        endpoint: '/v5/order/realtime',
        method: 'GET',
        params: params,
      );
      return List<Map<String, dynamic>>.from(response['result']?['list'] ?? []);
    } catch (e) {
      throw Exception('Ошибка получения открытых ордеров: $e');
    }
  }

  // Моковые данные на случай если API недоступен
  static List<CryptoModel> _getMockData() {
    return [
      CryptoModel(
        id: 'bitcoin',
        symbol: 'BTC',
        name: 'Bitcoin',
        price: 43250.50,
        change24h: 2.45,
        volume24h: 1250000000,
        turnover24h: 1250000000 * 43250.50,
        marketCap: 850000000000,
      ),
      CryptoModel(
        id: 'ethereum',
        symbol: 'ETH',
        name: 'Ethereum',
        price: 2650.30,
        change24h: -1.23,
        volume24h: 850000000,
        turnover24h: 850000000 * 2650.30,
        marketCap: 320000000000,
      ),
      CryptoModel(
        id: 'binancecoin',
        symbol: 'BNB',
        name: 'BNB',
        price: 315.80,
        change24h: 0.85,
        volume24h: 320000000,
        turnover24h: 320000000 * 315.80,
        marketCap: 48000000000,
      ),
      CryptoModel(
        id: 'solana',
        symbol: 'SOL',
        name: 'Solana',
        price: 98.45,
        change24h: 5.67,
        volume24h: 450000000,
        turnover24h: 450000000 * 98.45,
        marketCap: 45000000000,
      ),
      CryptoModel(
        id: 'ripple',
        symbol: 'XRP',
        name: 'Ripple',
        price: 0.625,
        change24h: -0.45,
        volume24h: 280000000,
        turnover24h: 280000000 * 0.625,
        marketCap: 35000000000,
      ),
    ];
  }

  // Моковые данные для TradFi (стабильные монеты)
  static List<CryptoModel> _getTradFiMockData() {
    return [
      CryptoModel(
        id: 'tether',
        symbol: 'USDT',
        name: 'Tether',
        price: 1.0,
        change24h: 0.01,
        volume24h: 50000000000,
        turnover24h: 50000000000 * 1.0,
        marketCap: 100000000000,
      ),
      CryptoModel(
        id: 'usd-coin',
        symbol: 'USDC',
        name: 'USD Coin',
        price: 1.0,
        change24h: 0.01,
        volume24h: 5000000000,
        turnover24h: 5000000000 * 1.0,
        marketCap: 30000000000,
      ),
      CryptoModel(
        id: 'binance-usd',
        symbol: 'BUSD',
        name: 'Binance USD',
        price: 1.0,
        change24h: 0.01,
        volume24h: 2000000000,
        turnover24h: 2000000000 * 1.0,
        marketCap: 5000000000,
      ),
      CryptoModel(
        id: 'dai',
        symbol: 'DAI',
        name: 'Dai',
        price: 1.0,
        change24h: 0.01,
        volume24h: 500000000,
        turnover24h: 500000000 * 1.0,
        marketCap: 5000000000,
      ),
    ];
  }

  // Моковые данные для Alpha (растущие монеты)
  static List<CryptoModel> _getAlphaMockData() {
    return [
      CryptoModel(
        id: 'solana',
        symbol: 'SOL',
        name: 'Solana',
        price: 98.45,
        change24h: 15.67,
        volume24h: 450000000,
        turnover24h: 450000000 * 98.45,
        marketCap: 45000000000,
      ),
      CryptoModel(
        id: 'cardano',
        symbol: 'ADA',
        name: 'Cardano',
        price: 0.52,
        change24h: 12.34,
        volume24h: 320000000,
        turnover24h: 320000000 * 0.52,
        marketCap: 18000000000,
      ),
      CryptoModel(
        id: 'polygon',
        symbol: 'MATIC',
        name: 'Polygon',
        price: 0.89,
        change24h: 8.90,
        volume24h: 280000000,
        turnover24h: 280000000 * 0.89,
        marketCap: 8500000000,
      ),
      CryptoModel(
        id: 'avalanche',
        symbol: 'AVAX',
        name: 'Avalanche',
        price: 36.78,
        change24h: 7.23,
        volume24h: 190000000,
        turnover24h: 190000000 * 36.78,
        marketCap: 14000000000,
      ),
      CryptoModel(
        id: 'chainlink',
        symbol: 'LINK',
        name: 'Chainlink',
        price: 14.56,
        change24h: 6.45,
        volume24h: 150000000,
        turnover24h: 150000000 * 14.56,
        marketCap: 8500000000,
      ),
    ];
  }

  // Получить исторические данные (candlestick/klines) для графика
  static Future<List<Map<String, dynamic>>> getKlines({
    required String symbol,
    required String interval, // 15, 60, 240, D для 15мин, 1ч, 4ч, 1д
    int limit = 200,
  }) async {
    try {
      // Конвертируем интервал в формат Bybit API
      final apiInterval = AppConstants.intervalMapping[interval] ?? interval;

      // Убираем / из символа для API (BTC/USDT -> BTCUSDT)
      final cleanSymbol = symbol.replaceAll('/', '');

      final url = Uri.parse(
        '$baseUrl/v5/market/kline?category=spot&symbol=$cleanSymbol&interval=$apiInterval&limit=$limit',
      );

      final response = await http.get(url).timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['retCode'] == 0 && data['result'] != null) {
          final List<dynamic> list = data['result']['list'] ?? [];
          // Конвертируем в формат [timestamp, open, high, low, close, volume]
          return list.map((item) {
            return {
              'timestamp': int.parse(item[0].toString()),
              'open': double.parse(item[1].toString()),
              'high': double.parse(item[2].toString()),
              'low': double.parse(item[3].toString()),
              'close': double.parse(item[4].toString()),
              'volume': double.parse(item[5].toString()),
            };
          }).toList();
        } else {
          throw Exception('Bybit API error: ${data['retMsg']}');
        }
      } else {
        throw Exception('Failed to load klines: ${response.statusCode}');
      }
    } catch (e) {
      // Возвращаем моковые данные в случае ошибки
      return _getMockKlines(limit);
    }
  }

  // Моковые данные для klines
  static List<Map<String, dynamic>> _getMockKlines(int limit) {
    final now = DateTime.now();
    final List<Map<String, dynamic>> klines = [];
    double basePrice = 86741.9;

    for (int i = limit - 1; i >= 0; i--) {
      final timestamp =
          now.subtract(Duration(minutes: 15 * i)).millisecondsSinceEpoch;
      final change = (i % 10 - 5) * 50.0; // Волатильность
      final open = basePrice + change;
      final close = open + (i % 3 - 1) * 20.0;
      final high = [open, close].reduce((a, b) => a > b ? a : b) + 30.0;
      final low = [open, close].reduce((a, b) => a < b ? a : b) - 30.0;
      final volume = 38.0 + (i % 10) * 2.0;

      klines.add({
        'timestamp': timestamp,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
      });
    }

    return klines;
  }

  // Получить список доступных торговых пар
  static Future<List<String>> getAvailablePairs() async {
    try {
      final markets = await getMarkets(perPage: 100);
      return markets.map((coin) => '${coin.symbol}/USDT').toList();
    } catch (e) {
      return ['BTC/USDT', 'ETH/USDT', 'BNB/USDT', 'SOL/USDT', 'XRP/USDT'];
    }
  }
}
