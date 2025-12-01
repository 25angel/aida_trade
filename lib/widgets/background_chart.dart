import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// График на фоне баланса (вертикальные линии разной высоты)
class BackgroundChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textSecondary.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    // Вертикальные линии разной высоты (имитация графика)
    final lineWidth = 3.0;
    final spacing = 8.0;
    final heights = [
      0.3,
      0.5,
      0.2,
      0.7,
      0.4,
      0.6,
      0.3,
      0.5,
      0.4,
      0.8,
      0.3,
      0.6
    ];

    double x = size.width * 0.1;
    for (int i = 0; i < heights.length && x < size.width * 0.9; i++) {
      final height = size.height * heights[i];
      final y = size.height - height;
      canvas.drawRect(
        Rect.fromLTWH(x, y, lineWidth, height),
        paint,
      );
      x += spacing;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
