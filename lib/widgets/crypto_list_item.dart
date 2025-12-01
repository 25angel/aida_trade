import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/crypto_model.dart';

class CryptoListItem extends StatelessWidget {
  final CryptoModel crypto;
  final int? index; // Номер в списке
  final bool isNew; // Показывать ли бейдж "New"
  final bool showFireIcon; // Показывать ли иконку огня
  final VoidCallback? onTap; // Callback для обработки нажатия

  const CryptoListItem({
    super.key,
    required this.crypto,
    this.index,
    this.isNew = false,
    this.showFireIcon = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.borderColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Номер
            if (index != null) ...[
              SizedBox(
                width: 20,
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: index! <= 3
                        ? const Color(0xFFFFD700) // Золотой цвет для 1, 2, 3
                        : AppTheme.textSecondary, // Серый цвет для остальных
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          crypto.pair,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showFireIcon) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.local_fire_department,
                          color: AppTheme.depositButton,
                          size: 14,
                        ),
                      ],
                      if (isNew) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'New',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatVolume(crypto.turnover24h),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatPrice(crypto.price),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                        ),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_formatPrice(crypto.price)} USD',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 70, // Фиксированная ширина для всех контейнеров
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: crypto.isPositive
                          ? const Color(
                              0xFF00C853) // Зеленый цвет для положительных значений
                          : AppTheme.primaryRed,
                      borderRadius: BorderRadius.circular(
                          20), // Более округлые края для pill-формы
                    ),
                    child: Text(
                      '${crypto.isPositive ? '+' : ''}${crypto.change24h.toStringAsFixed(2)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white, // Белый текст на цветном фоне
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    if (price >= 1000) {
      return price.toStringAsFixed(1);
    } else if (price >= 1) {
      return price.toStringAsFixed(2);
    } else if (price >= 0.01) {
      return price.toStringAsFixed(4);
    } else {
      return price.toStringAsFixed(5);
    }
  }

  String _formatVolume(double volume) {
    if (volume >= 1000000000) {
      return '${(volume / 1000000000).toStringAsFixed(2)}B USDT';
    } else if (volume >= 1000000) {
      return '${(volume / 1000000).toStringAsFixed(2)}M USDT';
    } else if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(2)}K USDT';
    } else {
      return '${volume.toStringAsFixed(2)} USDT';
    }
  }
}
