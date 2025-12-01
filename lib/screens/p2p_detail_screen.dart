import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/p2p_user.dart';

class P2PDetailScreen extends StatefulWidget {
  final P2PUser user;
  final bool isSelling;

  const P2PDetailScreen({
    super.key,
    required this.user,
    this.isSelling = false,
  });

  @override
  State<P2PDetailScreen> createState() => _P2PDetailScreenState();
}

class _P2PDetailScreenState extends State<P2PDetailScreen> {
  int _countdownSeconds = 60;
  String _selectedTab = 'За фиат';
  final TextEditingController _amountController = TextEditingController();
  double _usdtBalance = 50000.0; // Mock баланс USDT

  @override
  void initState() {
    super.initState();
    _startCountdown();
    // При продаже по умолчанию выбран таб "За криптовалюту"
    if (widget.isSelling) {
      _selectedTab = 'За криптовалюту';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double _calculateReceived() {
    if (_amountController.text.isEmpty) return 0.0;
    // Нормализуем строку: заменяем запятую на точку для парсинга
    final amountText = _amountController.text.replaceAll(',', '.');
    final amount = double.tryParse(amountText) ?? 0.0;
    if (widget.isSelling) {
      // При продаже: USDT -> KZT
      final rate = widget.user.rateKZT * 1.225;
      return amount * rate;
    } else {
      // При покупке: KZT -> USDT
      return amount / widget.user.rateKZT;
    }
  }

  String _getLimitsText() {
    if (widget.isSelling) {
      // При продаже лимиты в USDT
      // Конвертируем лимиты из KZT в USDT
      final limits = widget.user.orderLimits.split(' - ');
      if (limits.length >= 2) {
        try {
          final minKZT = double.parse(limits[0]
              .replaceAll(' KZT', '')
              .replaceAll(',', '')
              .replaceAll(' ', ''));
          final maxKZT = double.parse(limits[1]
              .replaceAll(' KZT', '')
              .replaceAll(',', '')
              .replaceAll(' ', ''));
          final rate = widget.user.rateKZT * 1.225;
          final minUSDT = minKZT / rate;
          final maxUSDT = maxKZT / rate;
          return '${minUSDT.toStringAsFixed(4)} - ${maxUSDT.toStringAsFixed(0)} USDT';
        } catch (e) {
          return '${widget.user.availableUSDT} - 0 USDT';
        }
      }
      return '${widget.user.availableUSDT} - 0 USDT';
    } else {
      return widget.user.orderLimits;
    }
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          if (_countdownSeconds > 0) {
            _countdownSeconds--;
            _startCountdown();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.isSelling ? 'Продажа USDT' : 'Покупка USDT',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Секция с ценой и защитой
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Левая часть - цена
                Row(
                  children: [
                    const Text(
                      'Цена ',
                      style: TextStyle(
                          color: Color.fromARGB(255, 255, 255, 255),
                          fontSize: 10),
                    ),
                    Text(
                      '${(widget.isSelling ? widget.user.rateKZT * 1.225 : widget.user.rateKZT).toStringAsFixed(2).replaceAll('.', ',')} KZT',
                      style: const TextStyle(
                          color: Color(0xFF00D4AA), fontSize: 10),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_countdownSeconds}s',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
                // Правая часть - защита
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF2A2A2A),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00D4AA),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Защита безопасности',
                        style: TextStyle(color: Colors.white, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Общий контейнер с табами, полем ввода, лимитами и расчетом
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Табы За фиат / За криптовалюту
                  Row(
                    children: widget.isSelling
                        ? [
                            _buildTab('За криптовалюту',
                                _selectedTab == 'За криптовалюту', () {
                              setState(() => _selectedTab = 'За криптовалюту');
                            }),
                            const SizedBox(width: 12),
                            _buildTab('За фиат', _selectedTab == 'За фиат', () {
                              setState(() => _selectedTab = 'За фиат');
                            }),
                          ]
                        : [
                            _buildTab('За фиат', _selectedTab == 'За фиат', () {
                              setState(() => _selectedTab = 'За фиат');
                            }),
                            const SizedBox(width: 12),
                            _buildTab('За криптовалюту',
                                _selectedTab == 'За криптовалюту', () {
                              setState(() => _selectedTab = 'За криптовалюту');
                            }),
                          ],
                  ),
                  const SizedBox(height: 16),
                  // Поле ввода суммы
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _amountController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 24),
                          keyboardType:
                              TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            // Заменяем запятую на точку при вводе
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]')),
                            TextInputFormatter.withFunction(
                                (oldValue, newValue) {
                              // Заменяем запятую на точку
                              final text = newValue.text.replaceAll(',', '.');
                              return TextEditingValue(
                                text: text,
                                selection: newValue.selection,
                              );
                            }),
                          ],
                          decoration: const InputDecoration(
                            hintText: '0',
                            hintStyle:
                                TextStyle(color: Colors.white38, fontSize: 24),
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.isSelling ? 'USDT' : 'KZT',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      SizedBox(width: 12),
                      Container(
                        width: 1,
                        height: 16,
                        color: Colors.white24,
                      ),
                      GestureDetector(
                        onTap: () {
                          if (widget.isSelling) {
                            // При продаже устанавливаем баланс USDT
                            _amountController.text =
                                _usdtBalance.toStringAsFixed(4);
                          } else {
                            final maxAmount = widget.user.orderLimits
                                .split(' - ')
                                .last
                                .replaceAll(' KZT', '')
                                .replaceAll(',', '')
                                .replaceAll(' ', '');
                            _amountController.text = maxAmount;
                          }
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: const Text(
                            'Макс.',
                            style: TextStyle(
                                color: Color.fromARGB(255, 255, 165, 0),
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Лимиты: ${_getLimitsText()}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (widget.isSelling) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Баланс: ${_usdtBalance.toStringAsFixed(4)} USDT',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            // TODO: Пополнить баланс
                          },
                          child: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    widget.isSelling
                        ? 'Я получу ${_calculateReceived() > 0 ? _calculateReceived().toStringAsFixed(2).replaceAll('.', ',') : "--"} KZT'
                        : 'Я получу ${_calculateReceived() > 0 ? _calculateReceived().toStringAsFixed(2) : "--"} USDT',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Карточка способа оплаты
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.user.paymentMethods.split(' | ').first,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                            if (widget.isSelling) ...[
                              const SizedBox(width: 4),
                              Text(
                                '4400430245124533', // Mock номер счета
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Text(
                                  '1',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down,
                                color: Colors.white, size: 16),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Длительность оплаты',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                            Text(
                              '${widget.user.timeLimitMinutes}мин.',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Информация о продавце
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade800,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                widget.user.traderInitial ??
                                    widget.user.nickname[0],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      widget.user.nickname,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Ордера ${widget.user.ordersCount} | Процент выполнения ${widget.user.completionRatePercent}%',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.thumb_up,
                            color: Colors.white54, size: 18),
                        const SizedBox(width: 4),
                        const Text(
                          '0%',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!widget.isSelling) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Условия мейкера',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.white54,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                              height: 1.5,
                            ),
                            children: [
                              TextSpan(
                                text:
                                    'Мерчанты могут указывать дополнительные условия в Условиях мейкеров. Внимательно изучите их перед размещением ордера. В случае противоречий приоритет имеют ',
                              ),
                              TextSpan(
                                text: 'Условия использования для владельцев',
                                style: TextStyle(color: Colors.orange),
                              ),
                              TextSpan(
                                text: ' и ',
                              ),
                              TextSpan(
                                text: 'Соглашение о конфиденциальности Р2Р',
                                style: TextStyle(color: Colors.orange),
                              ),
                              TextSpan(
                                text:
                                    '. Защита платформы не распространяется на нарушителей условий.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const Expanded(
            child: SizedBox(),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_amountController.text.isEmpty ? "0" : _amountController.text} ${widget.isSelling ? "USDT" : "KZT"}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Итого к выплате',
                    style: TextStyle(color: Colors.white54, fontSize: 8),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  // TODO: Handle buy action
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 42, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B4513), // Brown color
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    widget.isSelling ? 'Продажа' : 'Покупка',
                    style: const TextStyle(
                      color: Color.fromARGB(255, 0, 0, 0),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
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

  Widget _buildTab(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
