// Пример файла конфигурации API
// Скопируйте этот файл в api_config.dart и вставьте свои API ключи

class ApiConfig {
  // API ключи Bybit
  // ВАЖНО: В продакшене используйте переменные окружения или secure storage
  static const String apiKey = '8x8bFtA2VXpHKedQu6';
  static const String apiSecret = 'c9uYDH549bNgPUDvLORYg57F6MLOYuYIAmqm';

  // Проверка, настроены ли API ключи
  static bool get isConfigured =>
      apiKey != '8x8bFtA2VXpHKedQu6' &&
      apiSecret != 'c9uYDH549bNgPUDvLORYg57F6MLOYuYIAmqm';
}
