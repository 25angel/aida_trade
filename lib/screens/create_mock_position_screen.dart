import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/mock_portfolio_service.dart';

class CreateMockPositionScreen extends StatefulWidget {
  const CreateMockPositionScreen({super.key});

  @override
  State<CreateMockPositionScreen> createState() =>
      _CreateMockPositionScreenState();
}

class _CreateMockPositionScreenState extends State<CreateMockPositionScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _symbolController;
  late TextEditingController _pairController;
  late TextEditingController _entryPriceController;
  late TextEditingController _sizeController;
  late TextEditingController _usdtAmountController;
  late TextEditingController _leverageController;

  String _side = 'Long';
  String _marginMode = 'Isolated';
  bool _useUsdtAmount = false;
  bool _isLoading = false;

  final List<String> _availablePairs = [
    'BTC/USDT',
    'ETH/USDT',
    'SOL/USDT',
    'LTC/USDT',
    'BNB/USDT',
    'XRP/USDT',
    'ADA/USDT',
    'DOGE/USDT',
  ];

  @override
  void initState() {
    super.initState();
    _symbolController = TextEditingController();
    _pairController = TextEditingController(text: 'SOL/USDT');
    _entryPriceController = TextEditingController();
    _sizeController = TextEditingController();
    _usdtAmountController = TextEditingController();
    _leverageController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _pairController.dispose();
    _entryPriceController.dispose();
    _sizeController.dispose();
    _usdtAmountController.dispose();
    _leverageController.dispose();
    super.dispose();
  }

  void _updateSizeFromUsdt() {
    if (_useUsdtAmount && _usdtAmountController.text.isNotEmpty) {
      final usdtAmount = double.tryParse(_usdtAmountController.text);
      final entryPrice = double.tryParse(_entryPriceController.text);
      if (usdtAmount != null && entryPrice != null && entryPrice > 0) {
        final size = usdtAmount / entryPrice;
        _sizeController.text = size.toStringAsFixed(8);
      }
    }
  }

  void _updateUsdtFromSize() {
    if (!_useUsdtAmount && _sizeController.text.isNotEmpty) {
      final size = double.tryParse(_sizeController.text);
      final entryPrice = double.tryParse(_entryPriceController.text);
      if (size != null && entryPrice != null) {
        final usdtAmount = size * entryPrice;
        _usdtAmountController.text = usdtAmount.toStringAsFixed(2);
      }
    }
  }

  void _onPairChanged(String? value) {
    if (value != null) {
      setState(() {
        _pairController.text = value;
        _symbolController.text = value.replaceAll('/', '');
      });
    }
  }

  void _createPosition() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final pair = _pairController.text.trim();
      final symbol = pair.replaceAll('/', '');
      final entryPrice = double.parse(_entryPriceController.text);
      final leverage = int.parse(_leverageController.text);

      // Вычисляем размер позиции
      double size;
      if (_useUsdtAmount) {
        final usdtAmount = double.parse(_usdtAmountController.text);
        size = usdtAmount / entryPrice;
      } else {
        size = double.parse(_sizeController.text);
      }

      // Создаем позицию
      final position = {
        'id': 'mock_${DateTime.now().millisecondsSinceEpoch}',
        'symbol': symbol,
        'pair': pair,
        'side': _side,
        'size': size,
        'entryPrice': entryPrice,
        'markPrice': entryPrice, // Начальная маркировочная цена = цене входа
        'leverage': leverage,
        'marginMode': _marginMode,
        'unrealizedPnl': 0.0,
        'unrealizedPnlPercent': 0.0,
        'liquidationPrice': 0.0,
        'tpPrice': null,
        'slPrice': null,
        'partialSize': 0.0,
        'createdAt': DateTime.now(),
      };

      // Добавляем позицию в глобальное хранилище
      MockPortfolioService.addPosition(position);

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Моковая позиция успешно создана'),
          backgroundColor: AppTheme.primaryGreen,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка создания позиции: $e'),
          backgroundColor: AppTheme.primaryRed,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
          'Создать моковую позицию',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Создайте моковую позицию с указанием даты создания задним числом',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              // Пара
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 0, 0, 0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Пара',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _pairController.text.isEmpty
                          ? null
                          : _pairController.text,
                      decoration: InputDecoration(
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
                      dropdownColor: AppTheme.backgroundCard,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      items: _availablePairs.map((pair) {
                        return DropdownMenuItem(
                          value: pair,
                          child: Text(pair),
                        );
                      }).toList(),
                      onChanged: _onPairChanged,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Выберите пару';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Сторона (Long/Short)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 0, 0, 0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Сторона',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _side = 'Long';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _side == 'Long'
                                    ? AppTheme.primaryGreen.withOpacity(0.2)
                                    : AppTheme.backgroundDark,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _side == 'Long'
                                      ? AppTheme.primaryGreen
                                      : AppTheme.textSecondary,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Long',
                                  style: TextStyle(
                                    color: _side == 'Long'
                                        ? AppTheme.primaryGreen
                                        : AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _side = 'Short';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _side == 'Short'
                                    ? AppTheme.primaryRed.withOpacity(0.2)
                                    : AppTheme.backgroundDark,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _side == 'Short'
                                      ? AppTheme.primaryRed
                                      : AppTheme.textSecondary,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Short',
                                  style: TextStyle(
                                    color: _side == 'Short'
                                        ? AppTheme.primaryRed
                                        : AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Цена входа
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 0, 0, 0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Цена входа (USDT)',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _entryPriceController,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          var text = newValue.text;
                          // Заменяем запятую на точку
                          text = text.replaceAll(',', '.');
                          // Убираем лишние точки (оставляем только первую)
                          final parts = text.split('.');
                          if (parts.length > 2) {
                            text = parts[0] + '.' + parts.sublist(1).join('');
                          }
                          // Вычисляем новую позицию курсора
                          int selectionOffset = newValue.selection.baseOffset;
                          final lengthDiff = text.length - newValue.text.length;
                          selectionOffset += lengthDiff;
                          if (selectionOffset < 0) selectionOffset = 0;
                          if (selectionOffset > text.length) {
                            selectionOffset = text.length;
                          }
                          return TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                              offset: selectionOffset,
                            ),
                          );
                        }),
                      ],
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
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
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите цену входа';
                        }
                        final price =
                            double.tryParse(value.replaceAll(',', '.'));
                        if (price == null || price <= 0) {
                          return 'Введите корректную цену';
                        }
                        return null;
                      },
                      onChanged: (_) {
                        if (_useUsdtAmount) {
                          _updateSizeFromUsdt();
                        } else {
                          _updateUsdtFromSize();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Переключатель размера/суммы
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 0, 0, 0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Размер позиции',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: _useUsdtAmount,
                      onChanged: (value) {
                        setState(() {
                          _useUsdtAmount = value;
                        });
                      },
                      activeColor: AppTheme.primaryGreen,
                    ),
                    const Text(
                      'Сумма в USDT',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Размер или сумма
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 0, 0, 0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _useUsdtAmount ? 'Сумма (USDT)' : 'Размер позиции',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _useUsdtAmount
                          ? _usdtAmountController
                          : _sizeController,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          var text = newValue.text;
                          // Заменяем запятую на точку
                          text = text.replaceAll(',', '.');
                          // Убираем лишние точки (оставляем только первую)
                          final parts = text.split('.');
                          if (parts.length > 2) {
                            text = parts[0] + '.' + parts.sublist(1).join('');
                          }
                          // Вычисляем новую позицию курсора
                          int selectionOffset = newValue.selection.baseOffset;
                          final lengthDiff = text.length - newValue.text.length;
                          selectionOffset += lengthDiff;
                          if (selectionOffset < 0) selectionOffset = 0;
                          if (selectionOffset > text.length) {
                            selectionOffset = text.length;
                          }
                          return TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                              offset: selectionOffset,
                            ),
                          );
                        }),
                      ],
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
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
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return _useUsdtAmount
                              ? 'Введите сумму'
                              : 'Введите размер позиции';
                        }
                        final num = double.tryParse(value.replaceAll(',', '.'));
                        if (num == null || num <= 0) {
                          return 'Введите корректное значение';
                        }
                        return null;
                      },
                      onChanged: (_) {
                        if (_useUsdtAmount) {
                          _updateSizeFromUsdt();
                        } else {
                          _updateUsdtFromSize();
                        }
                      },
                    ),
                    if (!_useUsdtAmount) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Сумма: ${_usdtAmountController.text.isEmpty ? "0.00" : _usdtAmountController.text} USDT',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Плечо
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 0, 0, 0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Плечо',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _leverageController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
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
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите плечо';
                        }
                        final leverage = int.tryParse(value);
                        if (leverage == null || leverage < 1) {
                          return 'Плечо должно быть >= 1';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Режим маржи
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 0, 0, 0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Режим маржи',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _marginMode = 'Cross';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _marginMode == 'Cross'
                                    ? AppTheme.primaryGreen.withOpacity(0.2)
                                    : AppTheme.backgroundDark,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _marginMode == 'Cross'
                                      ? AppTheme.primaryGreen
                                      : AppTheme.textSecondary,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Cross',
                                  style: TextStyle(
                                    color: _marginMode == 'Cross'
                                        ? AppTheme.primaryGreen
                                        : AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _marginMode = 'Isolated';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _marginMode == 'Isolated'
                                    ? AppTheme.primaryGreen.withOpacity(0.2)
                                    : AppTheme.backgroundDark,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _marginMode == 'Isolated'
                                      ? AppTheme.primaryGreen
                                      : AppTheme.textSecondary,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Isolated',
                                  style: TextStyle(
                                    color: _marginMode == 'Isolated'
                                        ? AppTheme.primaryGreen
                                        : AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Кнопка создания
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createPosition,
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
                          'Создать позицию',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
