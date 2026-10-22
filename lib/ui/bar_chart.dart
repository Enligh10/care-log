import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One piece of a day's bar. Pieces with the same day stack (meds), or a
/// single piece can float between two values (blood pressure).
class BarPart {
  const BarPart(this.from, this.to, this.color);

  final double from;
  final double to;
  final Color color;
}

/// A bar per day of the month. Tap a bar to open that day.
class DayBarChart extends StatelessWidget {
  const DayBarChart({
    super.key,
    required this.daysInMonth,
    required this.bars,
    required this.minY,
    required this.maxY,
    this.refLine,
    this.refLabel,
    this.height = 200,
    this.today,
    this.onTapDay,
    this.decimals = 0,
    this.unit = '',
  });

  final int daysInMonth;
  final Map<int, List<BarPart>> bars;
  final double minY;
  final double maxY;
  final double? refLine;
  final String? refLabel;
  final double height;

  /// Day of month to mark as today (or null when not this month).
  final int? today;
  final ValueChanged<int>? onTapDay;
  final int decimals;
  final String unit;

  static const _left = 34.0;
  static const _right = 6.0;
  static const _top = 8.0;
  static const _bottom = 20.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final slot = (width - _left - _right) / daysInMonth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onTapDay == null
            ? null
            : (d) {
                final day = ((d.localPosition.dx - _left) / slot).floor() + 1;
                if (day >= 1 && day <= daysInMonth && (today == null || day <= today!)) {
                  onTapDay!(day);
                }
              },
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _BarPainter(
              chart: this,
              grid: scheme.outlineVariant.withValues(alpha: 0.6),
              text: scheme.onSurfaceVariant,
              accent: scheme.primary,
              surface: scheme.surfaceContainerLow,
            ),
          ),
        ),
      );
    });
  }
}

/// Picks a round step so the axis gets about [target] gridlines.
double niceStep(double range, {int target = 4, bool integer = false}) {
  if (range <= 0) return 1;
  final raw = range / target;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final n = raw / mag;
  final step = (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * mag;
  return integer ? math.max(1, step.roundToDouble()) : step;
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.chart,
    required this.grid,
    required this.text,
    required this.accent,
    required this.surface,
  });

  final DayBarChart chart;
  final Color grid;
  final Color text;
  final Color accent;
  final Color surface;

  TextPainter _label(String s, {double size = 10, FontWeight weight = FontWeight.w400, Color? color}) =>
      TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: color ?? text, fontSize: size, fontWeight: weight)),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    const left = DayBarChart._left, right = DayBarChart._right;
    const top = DayBarChart._top, bottom = DayBarChart._bottom;
    final lo = chart.minY, hi = chart.maxY <= chart.minY ? chart.minY + 1 : chart.maxY;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    final slot = w / chart.daysInMonth;
    final barW = math.max(2.0, math.min(slot * 0.7, 18.0));
    double y(double v) => top + h - ((v.clamp(lo, hi) - lo) / (hi - lo)) * h;
    double cx(int day) => left + (day - 0.5) * slot;

    // Recessive horizontal grid with value labels.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final step = niceStep(hi - lo, integer: chart.decimals == 0);
    final first = (lo / step).ceil() * step;
    for (var v = first; v <= hi + 1e-9; v += step) {
      final yy = y(v);
      canvas.drawLine(Offset(left, yy), Offset(size.width - right, yy), gridPaint);
      final tp = _label(v.toStringAsFixed(chart.decimals) + chart.unit);
      tp.paint(canvas, Offset(left - tp.width - 4, yy - tp.height / 2));
    }

    // Day labels along the bottom.
    for (final d in {1, 8, 15, 22, chart.daysInMonth}) {
      final isToday = d == chart.today;
      final tp = _label('$d',
          weight: isToday ? FontWeight.w800 : FontWeight.w400, color: isToday ? accent : null);
      tp.paint(canvas, Offset(cx(d) - tp.width / 2, size.height - bottom + 5));
    }
    if (chart.today != null && !{1, 8, 15, 22, chart.daysInMonth}.contains(chart.today)) {
      final t = chart.today!;
      canvas.drawCircle(Offset(cx(t), size.height - bottom + 10), 2.5, Paint()..color = accent);
    }

    // Bars. Stacked pieces get a 2px gap; the outer end is rounded.
    for (final entry in chart.bars.entries) {
      final parts = [...entry.value]..sort((a, b) => a.from.compareTo(b.from));
      if (parts.isEmpty) continue;
      final x0 = cx(entry.key) - barW / 2;
      final floating = parts.first.from > lo + 1e-9;
      for (var i = 0; i < parts.length; i++) {
        final p = parts[i];
        var yTop = y(p.to);
        var yBottom = y(p.from);
        if (i > 0) yBottom -= 1;
        if (i < parts.length - 1) yTop += 1;
        if (yBottom - yTop < 1) yTop = yBottom - 1;
        final r = Radius.circular(math.min(4, barW / 2));
        final last = i == parts.length - 1;
        final rect = RRect.fromLTRBAndCorners(
          x0,
          yTop,
          x0 + barW,
          yBottom,
          topLeft: last ? r : Radius.zero,
          topRight: last ? r : Radius.zero,
          bottomLeft: floating && i == 0 ? r : Radius.zero,
          bottomRight: floating && i == 0 ? r : Radius.zero,
        );
        canvas.drawRRect(rect, Paint()..color = p.color);
      }
    }

    // Reference line (fever threshold, daily target).
    if (chart.refLine != null) {
      final yy = y(chart.refLine!);
      final p = Paint()
        ..color = text
        ..strokeWidth = 1.2;
      for (var xx = left; xx < size.width - right; xx += 7) {
        canvas.drawLine(Offset(xx, yy), Offset(math.min(xx + 3.5, size.width - right), yy), p);
      }
      if (chart.refLabel != null) {
        final tp = _label(chart.refLabel!, size: 9.5, weight: FontWeight.w600);
        final bg = Rect.fromLTWH(size.width - right - tp.width - 6, yy - tp.height - 3, tp.width + 6, tp.height + 2);
        canvas.drawRect(bg, Paint()..color = surface);
        tp.paint(canvas, Offset(bg.left + 3, bg.top + 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => true;
}
