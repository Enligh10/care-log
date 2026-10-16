import 'dart:math' as math;

import 'package:flutter/material.dart';

class ChartSeries {
  const ChartSeries({required this.name, required this.color, required this.points});

  final String name;
  final Color color;

  /// (day of month, value) pairs, in day order.
  final List<(int, double)> points;
}

/// A small line chart of daily values across one month.
class MonthChart extends StatelessWidget {
  const MonthChart({
    super.key,
    required this.series,
    required this.daysInMonth,
    this.minY,
    this.maxY,
    this.threshold,
    this.thresholdLabel,
    this.height = 160,
  });

  final List<ChartSeries> series;
  final int daysInMonth;
  final double? minY;
  final double? maxY;
  final double? threshold;
  final String? thresholdLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = series.any((s) => s.points.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: hasData
              ? CustomPaint(
                  painter: _ChartPainter(
                    series: series,
                    days: daysInMonth,
                    minY: minY,
                    maxY: maxY,
                    threshold: threshold,
                    thresholdLabel: thresholdLabel,
                    grid: theme.colorScheme.outlineVariant,
                    text: theme.colorScheme.onSurfaceVariant,
                    surface: theme.colorScheme.surface,
                  ),
                )
              : Center(
                  child: Text('No readings this month',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ),
        ),
        if (series.length > 1 && hasData)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 14,
              children: [
                for (final s in series)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 14, height: 3, color: s.color),
                    const SizedBox(width: 6),
                    Text(s.name, style: theme.textTheme.bodySmall),
                  ]),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.series,
    required this.days,
    required this.minY,
    required this.maxY,
    required this.threshold,
    required this.thresholdLabel,
    required this.grid,
    required this.text,
    required this.surface,
  });

  final List<ChartSeries> series;
  final int days;
  final double? minY;
  final double? maxY;
  final double? threshold;
  final String? thresholdLabel;
  final Color grid;
  final Color text;
  final Color surface;

  TextPainter _label(String s, {double size = 10}) => TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: text, fontSize: size)),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      for (final s in series) for (final p in s.points) p.$2,
      ?threshold,
    ];
    var lo = minY ?? values.reduce(math.min);
    var hi = maxY ?? values.reduce(math.max);
    if (hi - lo < 1) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.12;
    if (minY == null) lo -= pad;
    if (maxY == null) hi += pad;

    const left = 34.0, bottom = 18.0, top = 6.0, right = 6.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    double x(int day) => left + (days <= 1 ? 0 : (day - 1) / (days - 1) * w);
    double y(double v) => top + h - (v - lo) / (hi - lo) * h;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // Horizontal grid lines with value labels.
    for (var i = 0; i <= 3; i++) {
      final v = lo + (hi - lo) * i / 3;
      final yy = y(v);
      canvas.drawLine(Offset(left, yy), Offset(size.width - right, yy), gridPaint);
      final tp = _label(v.toStringAsFixed(hi - lo < 10 ? 1 : 0));
      tp.paint(canvas, Offset(left - tp.width - 4, yy - tp.height / 2));
    }
    // Day labels.
    for (final d in [1, 8, 15, 22, days]) {
      if (d > days) continue;
      final tp = _label('$d');
      tp.paint(canvas, Offset(x(d) - tp.width / 2, size.height - bottom + 4));
    }
    // Threshold line (e.g. fever).
    if (threshold != null) {
      final t = threshold!;
      final p = Paint()
        ..color = const Color(0xFFE0603E)
        ..strokeWidth = 1.5;
      final yy = y(t);
      for (var xx = left; xx < size.width - right; xx += 8) {
        canvas.drawLine(Offset(xx, yy), Offset(math.min(xx + 4, size.width - right), yy), p);
      }
      if (thresholdLabel != null) {
        final tp = _label(thresholdLabel!, size: 9);
        tp.paint(canvas, Offset(size.width - right - tp.width, yy - tp.height - 1));
      }
    }
    // Series.
    for (final s in series) {
      if (s.points.isEmpty) continue;
      final line = Paint()
        ..color = s.color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final o = Offset(x(s.points[i].$1), y(s.points[i].$2));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, line);
      final dot = Paint()..color = s.color;
      final ring = Paint()..color = surface;
      for (final p in s.points) {
        final o = Offset(x(p.$1), y(p.$2));
        canvas.drawCircle(o, 4.2, ring);
        canvas.drawCircle(o, 3.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series || old.days != days || old.grid != grid;
}
