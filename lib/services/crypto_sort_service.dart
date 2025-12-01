import '../models/crypto_model.dart';

/// Сервис для сортировки криптовалют по различным критериям
class CryptoSortService {
  CryptoSortService._();

  /// Сортировка в зависимости от главной категории и подкатегории
  static void sortByCategory(
    List<CryptoModel> coins,
    String mainCategory,
    String subCategory,
  ) {
    switch (mainCategory) {
      case 'Популярные':
        _sortByTurnover(coins);
        break;
      case 'Новые':
        _sortByVolumeAscending(coins);
        break;
      case 'Активные монеты':
        _sortByVolumeDescending(coins);
        break;
      case 'Лидеры падения':
        _sortByFalling(coins);
        break;
      case 'Оборот':
        _sortByTurnover(coins);
        break;
      default:
        _sortByVolumeDescending(coins);
    }
  }

  /// Сортировка по обороту (по убыванию)
  static void _sortByTurnover(List<CryptoModel> coins) {
    coins.sort((a, b) => b.turnover24h.compareTo(a.turnover24h));
  }

  /// Сортировка по объему (по возрастанию)
  static void _sortByVolumeAscending(List<CryptoModel> coins) {
    coins.sort((a, b) => a.volume24h.compareTo(b.volume24h));
  }

  /// Сортировка по объему (по убыванию)
  static void _sortByVolumeDescending(List<CryptoModel> coins) {
    coins.sort((a, b) => b.volume24h.compareTo(a.volume24h));
  }

  /// Сортировка по падению цены
  static void _sortByFalling(List<CryptoModel> coins) {
    // Фильтруем падающие монеты
    final falling = coins.where((coin) => coin.change24h < 0).toList();
    if (falling.isNotEmpty) {
      falling.sort((a, b) => a.change24h.compareTo(b.change24h));
      coins.clear();
      coins.addAll(falling);
    } else {
      // Если падающих нет, сортируем по изменению (даже положительному)
      coins.sort((a, b) => a.change24h.compareTo(b.change24h));
    }
  }
}

