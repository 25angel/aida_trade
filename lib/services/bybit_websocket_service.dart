import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class BybitWebSocketService {
  static const String _publicSpotUrl = 'wss://stream.bybit.com/v5/public/spot';
  static const String _publicLinearUrl =
      'wss://stream.bybit.com/v5/public/linear';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  String? _currentCategory;
  String? _currentSymbol;
  String? _currentInterval;

  // Подключиться к WebSocket
  Future<void> connect({
    required String category, // 'spot' или 'linear'
    required String symbol, // 'BTCUSDT'
    required String interval, // '15', '60', '240', 'D' и т.д.
    required void Function(Map<String, dynamic>) onKlineUpdate,
  }) async {
    // Если уже подключены к тому же символу и интервалу, не переподключаемся
    if (_isConnected &&
        _currentCategory == category &&
        _currentSymbol == symbol &&
        _currentInterval == interval) {
      return;
    }

    // Отключаемся от предыдущего подключения
    await disconnect();

    _currentCategory = category;
    _currentSymbol = symbol;
    _currentInterval = interval;
    final url = category == 'spot' ? _publicSpotUrl : _publicLinearUrl;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;

      // Подписываемся только на нужный интервал (Bybit ограничивает до 10 подписок за раз)
      // Формат: kline.{interval}.{symbol}
      final topic = 'kline.$interval.$symbol';
      final subscribeMessage = {
        'op': 'subscribe',
        'args': [topic],
      };

      print('WebSocket: Subscribing to kline topic: $topic for $symbol');
      _channel!.sink.add(jsonEncode(subscribeMessage));

      // Слушаем сообщения
      _subscription = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString());

            // Обрабатываем kline обновления
            if (data['topic'] != null &&
                data['topic'].toString().startsWith('kline.')) {
              // Передаем весь объект data, включая topic и data
              print(
                  'WebSocket: Received kline update for topic: ${data['topic']}');
              onKlineUpdate(data);
            } else {
              // Логируем другие сообщения для отладки
              if (data['op'] == 'subscribe' && data['success'] == true) {
                print('WebSocket: Successfully subscribed to topics');
              } else if (data['op'] != null) {
                print('WebSocket: Received message: ${data.toString()}');
              }
            }
          } catch (e) {
            print('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isConnected = false;
          // Не переподключаемся автоматически - пользователь может переключить период
        },
        onDone: () {
          print('WebSocket connection closed');
          _isConnected = false;
        },
      );
    } catch (e) {
      print('Error connecting to WebSocket: $e');
      _isConnected = false;
      rethrow;
    }
  }

  // Отключиться от WebSocket
  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _subscription = null;
    _isConnected = false;
    _currentCategory = null;
    _currentSymbol = null;
    _currentInterval = null;
  }

  bool get isConnected => _isConnected;
}
