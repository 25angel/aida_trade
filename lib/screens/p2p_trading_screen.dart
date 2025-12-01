import 'package:flutter/material.dart';
import 'p2p_detail_screen.dart';
import '../models/p2p_user.dart';

class P2PTradingScreen extends StatefulWidget {
  const P2PTradingScreen({super.key});

  @override
  State<P2PTradingScreen> createState() => _P2PTradingScreenState();
}

class _P2PTradingScreenState extends State<P2PTradingScreen> {
  String _selectedMainTab = 'P2P';
  String _selectedFiat = 'KZT';
  String _selectedTab = 'Покупка';

  final List<P2PUser> mockUsers = [
    P2PUser(
      nickname: 'ЕльЧапо',
      timeLimitMinutes: 30,
      rateKZT: 519.00,
      orderLimits: '900,13 - 900,13 KZT',
      availableUSDT: 31,
      paymentMethods: 'Bereke Bank',
      ordersCount: 5,
      completionRatePercent: 100,
      traderInitial: 'E',
    ),
    P2PUser(
      nickname: 'Pantene',
      timeLimitMinutes: 15,
      rateKZT: 524.00,
      orderLimits: '131,45K - 131,45K KZT',
      availableUSDT: 300,
      paymentMethods: 'Freedom Bank | Bank Transfer',
      ordersCount: 186,
      completionRatePercent: 100,
      traderInitial: 'P',
    ),
    P2PUser(
      nickname: 'sdmaratovich',
      timeLimitMinutes: 30,
      rateKZT: 525.00,
      orderLimits: '20 000 - 20 000 KZT',
      availableUSDT: 44,
      paymentMethods: 'Kaspi Bank',
      ordersCount: 731,
      completionRatePercent: 98,
      traderInitial: 'S',
      hasStar: true,
    ),
    P2PUser(
      nickname: 'Diplomat 007',
      timeLimitMinutes: 30,
      rateKZT: 525.00,
      orderLimits: '87 400 - 87 500 KZT',
      availableUSDT: 300,
      paymentMethods: 'Kaspi Bank',
      ordersCount: 587,
      completionRatePercent: 97,
      traderInitial: 'D',
    ),
    P2PUser(
      nickname: 'CryptoTrader',
      timeLimitMinutes: 15,
      rateKZT: 523.50,
      orderLimits: '50 000 - 100 000 KZT',
      availableUSDT: 500,
      paymentMethods: 'Halyk Bank | Kaspi Bank',
      ordersCount: 342,
      completionRatePercent: 99,
      traderInitial: 'C',
    ),
    P2PUser(
      nickname: 'BitcoinMaster',
      timeLimitMinutes: 20,
      rateKZT: 526.00,
      orderLimits: '10 000 - 50 000 KZT',
      availableUSDT: 150,
      paymentMethods: 'Bank Transfer',
      ordersCount: 892,
      completionRatePercent: 100,
      traderInitial: 'B',
      hasStar: true,
    ),
    P2PUser(
      nickname: 'FastExchange',
      timeLimitMinutes: 10,
      rateKZT: 520.00,
      orderLimits: '5 000 - 25 000 KZT',
      availableUSDT: 200,
      paymentMethods: 'Freedom Bank',
      ordersCount: 156,
      completionRatePercent: 98,
      traderInitial: 'F',
    ),
    P2PUser(
      nickname: 'TrustSeller',
      timeLimitMinutes: 25,
      rateKZT: 527.50,
      orderLimits: '15 000 - 75 000 KZT',
      availableUSDT: 400,
      paymentMethods: 'Kaspi Bank | Halyk Bank',
      ordersCount: 1245,
      completionRatePercent: 99,
      traderInitial: 'T',
      hasStar: true,
    ),
    P2PUser(
      nickname: 'QuickTrade',
      timeLimitMinutes: 12,
      rateKZT: 521.00,
      orderLimits: '3 000 - 15 000 KZT',
      availableUSDT: 80,
      paymentMethods: 'Bereke Bank | Bank Transfer',
      ordersCount: 67,
      completionRatePercent: 100,
      traderInitial: 'Q',
    ),
  ];

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
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectedMainTab = 'Express';
                });
              },
              child: Text(
                'Express',
                style: TextStyle(
                  color: _selectedMainTab == 'Express'
                      ? Colors.white
                      : Colors.white54,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectedMainTab = 'P2P';
                });
              },
              child: Text(
                'P2P',
                style: TextStyle(
                  color:
                      _selectedMainTab == 'P2P' ? Colors.white : Colors.white54,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color.fromARGB(255, 98, 97, 97), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedFiat,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                const Icon(Icons.arrow_drop_down,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          // Табы Покупка/Продажа
          Row(
            children: [
              const SizedBox(width: 16),
              _buildTabButton('Покупка', _selectedTab == 'Покупка', () {
                setState(() {
                  _selectedTab = 'Покупка';
                });
              }),
              const SizedBox(width: 6),
              _buildTabButton('Продажа', _selectedTab == 'Продажа', () {
                setState(() {
                  _selectedTab = 'Продажа';
                });
              }),
            ],
          ),
          const SizedBox(height: 12),
          // Фильтры
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip('USDT', true, Icons.diamond),
                const SizedBox(width: 10),
                _buildFilterChip('Сумма', false, null),
                const SizedBox(width: 10),
                _buildFilterChip('Все способы оплаты', false, null),
                const Spacer(),
                Stack(
                  children: [
                    const Icon(Icons.filter_alt_outlined,
                        color: Colors.white, size: 22),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
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
          const SizedBox(height: 12),
          // Список объявлений
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: mockUsers.length,
              itemBuilder: (context, index) {
                final user = mockUsers[index];
                return _buildOrderCard(user);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(P2PUser user) {
    final paymentMethods = user.paymentMethods.split(' | ');
    final isSelling = _selectedTab == 'Продажа';
    // Повышаем цену на 22.5% (среднее между 20-25%) при продаже
    final displayRate = isSelling ? user.rateKZT * 1.12 : user.rateKZT;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => P2PDetailScreen(
              user: user,
              isSelling: isSelling,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 1.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        color: const Color.fromARGB(255, 0, 0, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Имя и время
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            user.traderInitial ?? user.nickname[0],
                            style: const TextStyle(
                              color: Color.fromARGB(255, 0, 0, 0),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        user.nickname,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (user.hasStar == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Icon(Icons.access_time, color: Colors.white54, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${user.timeLimitMinutes}мин.',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Цена
                  Text(
                    '₸ ${displayRate.toStringAsFixed(2).replaceAll('.', ',')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Лимиты
                  Text(
                    'Лимиты ${user.orderLimits}',
                    style: const TextStyle(color: Colors.white54, fontSize: 8),
                  ),
                  const SizedBox(height: 4),
                  // Количество
                  Text(
                    'Количество ${user.availableUSDT} USDT',
                    style: const TextStyle(color: Colors.white54, fontSize: 8),
                  ),
                  const SizedBox(height: 6),
                  // Способы оплаты
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: paymentMethods.map((method) {
                      return Text(
                        method,
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 8),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            // Правая колонка
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${user.ordersCount} Ордера (${user.completionRatePercent}%)',
                  style: const TextStyle(color: Colors.white54, fontSize: 8),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => P2PDetailScreen(
                          user: user,
                          isSelling: isSelling,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelling ? Colors.red : const Color(0xFF007A3E),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      isSelling ? 'Продажа' : 'Покупка',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color.fromARGB(255, 93, 93, 93)
              : const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color.fromARGB(255, 98, 97, 97),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String text, bool active, IconData? icon) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: const Color(0xFF00D4AA), size: 12),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down,
                color: Colors.white, size: 10),
          ],
        ),
      ),
    );
  }
}
