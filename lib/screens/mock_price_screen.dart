import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/mock_portfolio_service.dart';

class MockPriceScreen extends StatefulWidget {
  const MockPriceScreen({super.key});

  @override
  State<MockPriceScreen> createState() => _MockPriceScreenState();
}

class _MockPriceScreenState extends State<MockPriceScreen> {
  late TextEditingController _solPriceController;
  late TextEditingController _ltcPriceController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _solPriceController = TextEditingController(
      text: MockPortfolioService.solEntryPrice.toStringAsFixed(2),
    );
    _ltcPriceController = TextEditingController(
      text: MockPortfolioService.ltcEntryPrice.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _solPriceController.dispose();
    _ltcPriceController.dispose();
    super.dispose();
  }

  void _savePrices() {
    // Нормализуем строку: заменяем запятую на точку для парсинга
    final solText = _solPriceController.text.replaceAll(',', '.');
    final ltcText = _ltcPriceController.text.replaceAll(',', '.');
    final solEntryPrice = double.tryParse(solText);
    final ltcEntryPrice = double.tryParse(ltcText);

    if (solEntryPrice == null || solEntryPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите корректную цену входа для Solana'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
      return;
    }

    if (ltcEntryPrice == null || ltcEntryPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите корректную цену входа для Litecoin'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Устанавливаем цены входа
    MockPortfolioService.setSolEntryPrice(solEntryPrice);
    MockPortfolioService.setLtcEntryPrice(ltcEntryPrice);

    setState(() {
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Цены входа успешно обновлены'),
        backgroundColor: AppTheme.primaryGreen,
        duration: Duration(seconds: 2),
      ),
    );

    // Возвращаем результат для обновления позиций в TradeScreen
    Navigator.pop(context, {
      'solEntryPrice': solEntryPrice,
      'ltcEntryPrice': ltcEntryPrice,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Смена цен входа моковых позиций',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Измените цены входа (entryPrice) для моковых позиций Solana и Litecoin',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            // Solana цена
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'SOL',
                            style: TextStyle(
                              color: AppTheme.primaryGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Solana (SOL)',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _solPriceController,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      // Заменяем запятую на точку при вводе
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        // Заменяем запятую на точку
                        final text = newValue.text.replaceAll(',', '.');
                        return TextEditingValue(
                          text: text,
                          selection: newValue.selection,
                        );
                      }),
                    ],
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Цена входа SOL (USDT)',
                      labelStyle: const TextStyle(
                        color: AppTheme.textSecondary,
                      ),
                      hintText: 'Введите цену входа',
                      hintStyle: const TextStyle(
                        color: AppTheme.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppTheme.backgroundDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryGreen,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Текущая цена входа: ${MockPortfolioService.solEntryPrice.toStringAsFixed(2)} USDT',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Litecoin цена
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'LTC',
                            style: TextStyle(
                              color: AppTheme.primaryGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Litecoin (LTC)',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ltcPriceController,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      // Заменяем запятую на точку при вводе
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        // Заменяем запятую на точку
                        final text = newValue.text.replaceAll(',', '.');
                        return TextEditingValue(
                          text: text,
                          selection: newValue.selection,
                        );
                      }),
                    ],
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Цена входа LTC (USDT)',
                      labelStyle: const TextStyle(
                        color: AppTheme.textSecondary,
                      ),
                      hintText: 'Введите цену входа',
                      hintStyle: const TextStyle(
                        color: AppTheme.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppTheme.backgroundDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryGreen,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Текущая цена входа: ${MockPortfolioService.ltcEntryPrice.toStringAsFixed(2)} USDT',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Кнопка сохранения
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _savePrices,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Сохранить цены входа',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.textSecondary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Изменение цен входа повлияет на расчет P&L и пересчет TP/SL для моковых позиций Solana и Litecoin',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
