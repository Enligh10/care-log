part of 'journal_page.dart';

/// What one bar chart shows.
class _ChartSpec {
  _ChartSpec({
    required this.bars,
    required this.minY,
    required this.maxY,
    this.refLine,
    this.refLabel,
    this.decimals = 0,
    this.caption = '',
    this.legend = const [],
  });

  final Map<int, List<BarPart>> bars;
  final double minY;
  final double maxY;
  final double? refLine;
  final String? refLabel;
  final int decimals;
  final String caption;
  final List<(Color, String)> legend;

  bool get hasData => bars.isNotEmpty;
}

/// The journal's bar-chart mode: one chart for the selected view, or, for
/// "Everything", a small chart for each thing logged this month.
class ChartPanel extends StatelessWidget {
  const ChartPanel({
    super.key,
    required this.view,
    required this.agg,
    required this.month,
    required this.daysInMonth,
    required this.onTapDay,
    required this.onPickView,
    required this.symptomViews,
  });

  final JournalView view;
  final Map<int, DayAgg> agg;
  final DateTime month;
  final int daysInMonth;
  final ValueChanged<int> onTapDay;
  final ValueChanged<JournalView> onPickView;
  final List<JournalView> symptomViews;

  int? get _today {
    final now = DateTime.now();
    return now.year == month.year && now.month == month.month ? now.day : null;
  }

  _ChartSpec _spec(JournalView v, AppState state, ColorScheme scheme) {
    final bars = <int, List<BarPart>>{};
    switch (v.kind) {
      case ViewKind.everything:
      case ViewKind.allMeds:
        final meds = [
          for (final m in state.meds)
            if (agg.values.any((d) => (d.doses[m.id] ?? 0) > 0)) m,
        ];
        var maxTotal = 0;
        for (final e in agg.entries) {
          var acc = 0;
          final parts = <BarPart>[];
          for (final m in meds) {
            final n = e.value.doses[m.id] ?? 0;
            if (n == 0) continue;
            parts.add(BarPart(acc.toDouble(), (acc + n).toDouble(), m.colorValue));
            acc += n;
          }
          if (parts.isNotEmpty) bars[e.key] = parts;
          maxTotal = math.max(maxTotal, acc);
        }
        return _ChartSpec(
          bars: bars,
          minY: 0,
          maxY: (maxTotal + 1).toDouble(),
          caption: 'Doses logged each day, stacked by medicine.',
          legend: [for (final m in meds) (m.colorValue, m.name)],
        );
      case ViewKind.med:
        final med = medById(state, v.key);
        final target = med?.dosesPerDay ?? 1;
        var maxN = 0;
        for (final e in agg.entries) {
          final n = e.value.doses[v.key] ?? 0;
          if (n == 0) continue;
          bars[e.key] = [BarPart(0, n.toDouble(), doseFill(med, n, scheme)!)];
          maxN = math.max(maxN, n);
        }
        return _ChartSpec(
          bars: bars,
          minY: 0,
          maxY: (math.max(maxN, target) + 1).toDouble(),
          refLine: target > 1 ? target.toDouble() : null,
          refLabel: target > 1 ? '$target a day' : null,
          caption: 'Doses logged each day.',
          legend: legendFor(v, state, scheme).where((l) => l.$2 != 'Not logged').toList(),
        );
      case ViewKind.symptom:
        for (final e in agg.entries) {
          final s = e.value.symptomMax[v.key];
          if (s == null) continue;
          bars[e.key] = [BarPart(0, math.max(s, 0.15).toDouble(), severityColor(s, scheme))];
        }
        return _ChartSpec(
          bars: bars,
          minY: 0,
          maxY: 10,
          caption: 'Worst rating each day, 0 to 10.',
          legend: legendFor(v, state, scheme),
        );
      case ViewKind.bp:
        var lo = 999.0, hi = 0.0;
        for (final e in agg.entries) {
          final s = e.value.avgSys, d = e.value.avgDia;
          if (s == null || d == null) continue;
          bars[e.key] = [BarPart(d, s, bpCategory(s, d).$1)];
          lo = math.min(lo, d);
          hi = math.max(hi, s);
        }
        return _ChartSpec(
          bars: bars,
          minY: bars.isEmpty ? 40 : math.max(30, ((lo - 10) / 10).floorToDouble() * 10),
          maxY: bars.isEmpty ? 160 : ((hi + 10) / 10).ceilToDouble() * 10,
          caption: 'Each bar runs from diastolic (bottom) to systolic (top), averaged per day.',
          legend: legendFor(v, state, scheme),
        );
      case ViewKind.hr:
        var lo = 999.0, hi = 0.0;
        for (final e in agg.entries) {
          final h = e.value.avgHr;
          if (h == null) continue;
          lo = math.min(lo, h);
          hi = math.max(hi, h);
        }
        final base = lo == 999 ? 40.0 : math.min(40.0, ((lo - 10) / 10).floorToDouble() * 10);
        for (final e in agg.entries) {
          final h = e.value.avgHr;
          if (h == null) continue;
          bars[e.key] = [BarPart(base, h, hrCategory(h).$1)];
        }
        return _ChartSpec(
          bars: bars,
          minY: base,
          maxY: bars.isEmpty ? 120 : ((hi + 10) / 10).ceilToDouble() * 10,
          caption: 'Average heart rate each day (bpm). The axis starts at ${base.round()}.',
          legend: legendFor(v, state, scheme),
        );
      case ViewKind.temp:
        var lo = 999.0, hi = 0.0;
        for (final e in agg.entries) {
          final t = e.value.maxTemp;
          if (t == null) continue;
          lo = math.min(lo, t);
          hi = math.max(hi, t);
        }
        final base = lo == 999 ? 96.0 : math.min(96.0, lo.floorToDouble() - 1);
        for (final e in agg.entries) {
          final t = e.value.maxTemp;
          if (t == null) continue;
          bars[e.key] = [BarPart(base, t, tempCategory(t).$1)];
        }
        return _ChartSpec(
          bars: bars,
          minY: base,
          maxY: math.max(101.5, ((hi + 0.5) * 2).ceilToDouble() / 2),
          refLine: feverThresholdF,
          refLabel: 'fever',
          decimals: 1,
          caption: 'Highest temperature each day (°F). The axis starts at ${base.toStringAsFixed(0)}°F.',
          legend: legendFor(v, state, scheme),
        );
    }
  }

  Widget _chart(_ChartSpec spec, {required double height}) => DayBarChart(
        daysInMonth: daysInMonth,
        bars: spec.bars,
        minY: spec.minY,
        maxY: spec.maxY,
        refLine: spec.refLine,
        refLabel: spec.refLabel,
        decimals: spec.decimals,
        height: height,
        today: _today,
        onTapDay: onTapDay,
      );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    if (view.kind != ViewKind.everything) {
      final spec = _spec(view, state, scheme);
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(view.label, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(spec.caption, style: muted),
              const SizedBox(height: 12),
              _chart(spec, height: 220),
              if (spec.legend.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Legend(items: spec.legend),
              ],
              if (!spec.hasData)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Nothing logged this month.', style: muted),
                ),
            ],
          ),
        ),
      );
    }

    // Everything: a compact chart per thing that has data this month.
    final sections = <(JournalView, _ChartSpec)>[
      for (final v in [_allMeds, _bp, _hr, _temp, ...symptomViews]) (v, _spec(v, state, scheme)),
    ].where((s) => s.$2.hasData).toList();

    if (sections.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Nothing logged this month yet.', style: muted, textAlign: TextAlign.center),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (v, spec) in sections) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(v.kind == ViewKind.allMeds ? 'Medicines' : v.label,
                          style: theme.textTheme.titleSmall),
                    ),
                    TextButton(
                      onPressed: () => onPickView(v),
                      child: const Text('Open'),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _chart(spec, height: 130),
                  ),
                  if (v.kind == ViewKind.allMeds && spec.legend.length > 1) ...[
                    const SizedBox(height: 8),
                    _Legend(items: spec.legend),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text('Tap a bar to see that day. "Open" shows one chart larger.', style: muted),
      ],
    );
  }
}
