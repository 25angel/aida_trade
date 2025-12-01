import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Custom icon widgets для точного соответствия дизайну Bybit

class BybitEarnIcon extends StatelessWidget {
  const BybitEarnIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: BybitEarnPainter(),
    );
  }
}

class BybitEarnPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Два квадрата
    canvas.drawRect(Rect.fromLTWH(4, 4, 10, 10), paint);
    canvas.drawRect(Rect.fromLTWH(14, 14, 10, 10), paint);

    // Круг в правом верхнем углу левого квадрата
    final circlePaint = Paint()
      ..color = AppTheme.textPrimary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(12, 6), 3, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class InviteFriendsIcon extends StatelessWidget {
  const InviteFriendsIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: InviteFriendsPainter(),
    );
  }
}

class InviteFriendsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textPrimary
      ..style = PaintingStyle.fill;

    // Два силуэта людей
    // Первый (слева)
    canvas.drawCircle(const Offset(10, 12), 4, paint);
    canvas.drawPath(
      Path()
        ..moveTo(6, 16)
        ..lineTo(6, 22)
        ..lineTo(10, 22)
        ..lineTo(10, 16),
      paint,
    );

    // Второй (справа, немного сзади)
    canvas.drawCircle(const Offset(18, 12), 4, paint);
    canvas.drawPath(
      Path()
        ..moveTo(14, 16)
        ..lineTo(14, 22)
        ..lineTo(18, 22)
        ..lineTo(18, 16),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CopyTradingIcon extends StatelessWidget {
  const CopyTradingIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: CopyTradingPainter(),
    );
  }
}

class CopyTradingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Две стрелки по кругу
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 8.0;

    // Первая стрелка (по часовой)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      3.14,
      false,
      paint,
    );

    // Вторая стрелка (против часовой)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.14,
      3.14,
      false,
      paint,
    );

    // Доллар в центре
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '\$',
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - 4, center.dy - 6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TradingBotIcon extends StatelessWidget {
  const TradingBotIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: TradingBotPainter(),
    );
  }
}

class TradingBotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textPrimary
      ..style = PaintingStyle.fill;

    // Голова робота (квадрат со скругленными углами)
    final headRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(6, 4, 16, 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(headRect, paint);

    // Экран (прямоугольник внутри)
    final screenPaint = Paint()
      ..color = AppTheme.backgroundDark
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(9, 7, 10, 6), screenPaint);

    // Антенна
    canvas.drawCircle(const Offset(14, 2), 2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MoreIcon extends StatelessWidget {
  const MoreIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: MorePainter(),
    );
  }
}

class MorePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textPrimary
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = 8.0;

    // Стрелка по кругу
    final strokePaint = Paint()
      ..color = AppTheme.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      5.5,
      false,
      strokePaint,
    );

    // Три точки внутри
    canvas.drawCircle(Offset(center.dx - 3, center.dy - 2), 1.5, paint);
    canvas.drawCircle(center, 1.5, paint);
    canvas.drawCircle(Offset(center.dx + 3, center.dy + 2), 1.5, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
