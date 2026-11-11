import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Геометрический знак Verde в духе логотипа Perplexity:
/// контурные диагонали и тонкая вертикальная ось.
class VerdeLogoMark extends StatelessWidget {
  /// Высота знака; ширина вычисляется из пропорций исходного пути.
  final double size;

  final Color color;

  /// Толщина линии в координатах исходного SVG (не в пикселях).
  final double strokeWidth;

  const VerdeLogoMark({
    super.key,
    this.size = 30,
    this.color = AppTheme.accentGreen,
    this.strokeWidth = 1.35,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * _VerdeMarkPainter.viewWidth / _VerdeMarkPainter.viewHeight,
      height: size,
      child: CustomPaint(
        painter: _VerdeMarkPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

/// Знак + словесный логотип «verde».
class VerdeLogo extends StatelessWidget {
  final double markSize;
  final double fontSize;
  final Color markColor;
  final Color textColor;
  final bool showWordmark;

  const VerdeLogo({
    super.key,
    this.markSize = 30,
    this.fontSize = 27,
    this.markColor = AppTheme.accentGreen,
    this.textColor = const Color(0xFFE9ECEA),
    this.showWordmark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        VerdeLogoMark(size: markSize, color: markColor),
        if (showWordmark) ...[
          SizedBox(width: markSize * 0.28),
          Text(
            'verde',
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.1,
              height: 1,
            ),
          ),
        ],
      ],
    );
  }
}

class _VerdeMarkPainter extends CustomPainter {
  static const double viewWidth = 27.14;
  static const double viewHeight = 36;

  /// Исходный viewBox начинается с x = 0.5; сдвигаем его к нулю.
  static const double _viewLeft = 0.5;

  /// Путь из геометрического знака Perplexity. Используем только
  /// контурную отрисовку: заливка превратила бы тонкие линии в пятна.
  static const String _pathData =
      'm23.566,1.398l-9.495,9.504h9.495V1.398v2.602V1.398Z'
      'm-9.496,9.504L4.574,1.398v9.504h9.496Z'
      'm-.021-10.902v36'
      'm9.517-15.596l-9.495-9.504v13.625l9.495,9.504v-13.625Z'
      'm-18.991,0l9.496-9.504v13.625l-9.496,9.504v-13.625Z'
      'M.5,10.9v13.57h4.074v-4.066l9.496-9.504H.5Z'
      'm13.57,0l9.495,9.504v4.066h4.075v-13.57h-13.57Z';

  final Color color;
  final double strokeWidth;

  const _VerdeMarkPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final padding = strokeWidth;
    final scale = math.min(
      size.width / (viewWidth + padding * 2),
      size.height / (viewHeight + padding * 2),
    );
    if (scale <= 0) return;

    final dx = (size.width - viewWidth * scale) / 2 - _viewLeft * scale;
    final dy = (size.height - viewHeight * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;

    canvas.drawPath(_SvgPathParser.parse(_pathData), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VerdeMarkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Минимальный парсер SVG-пути: M/m, L/l, H/h, V/v и Z/z.
///
/// Полноценная библиотека здесь не нужна: логотип — один статический
/// путь, а лишняя зависимость утяжелила бы приложение.
class _SvgPathParser {
  static final RegExp _token = RegExp(
    r'[MmLlHhVvZz]|-?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?',
  );

  static Path parse(String data) {
    final tokens = _token
        .allMatches(data)
        .map((match) => match.group(0)!)
        .toList(growable: false);
    final path = Path();

    var index = 0;
    var command = '';
    var started = false;
    double x = 0;
    double y = 0;
    double startX = 0;
    double startY = 0;

    double nextNumber() {
      if (index >= tokens.length) {
        throw const FormatException('SVG path: missing coordinate');
      }
      return double.parse(tokens[index++]);
    }

    bool isCommand(String token) =>
        token.length == 1 && 'MmLlHhVvZz'.contains(token);

    while (index < tokens.length) {
      final token = tokens[index];
      if (isCommand(token)) {
        command = token;
        index++;
      } else if (command.isEmpty) {
        break;
      }

      final relative = command == command.toLowerCase();

      switch (command.toUpperCase()) {
        case 'M':
          final nextX = nextNumber();
          final nextY = nextNumber();
          x = relative ? x + nextX : nextX;
          y = relative ? y + nextY : nextY;
          startX = x;
          startY = y;
          path.moveTo(x, y);
          started = true;
          // Пары после M трактуются как неявные L/l.
          command = relative ? 'l' : 'L';
          break;
        case 'L':
          final nextX = nextNumber();
          final nextY = nextNumber();
          x = relative ? x + nextX : nextX;
          y = relative ? y + nextY : nextY;
          path.lineTo(x, y);
          break;
        case 'H':
          final nextX = nextNumber();
          x = relative ? x + nextX : nextX;
          path.lineTo(x, y);
          break;
        case 'V':
          final nextY = nextNumber();
          y = relative ? y + nextY : nextY;
          path.lineTo(x, y);
          break;
        case 'Z':
          if (started) {
            path.close();
            x = startX;
            y = startY;
          }
          break;
        default:
          return path;
      }
    }

    return path;
  }
}
