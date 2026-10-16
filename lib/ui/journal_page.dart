import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import 'log_tile.dart';
import 'month_chart.dart';
import 'theme.dart';

// ------------------------------------------------------------------ view model

enum ViewKind { allMeds, med, symptom, bp, hr, temp }

enum JournalMode { calendar, tracker }

class JournalView {
  const JournalView(this.kind, [this.key = '', this.label = '']);

  final ViewKind kind;

  /// Medicine id or symptom name.
  final String key;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is JournalView && other.kind == kind && other.key == key;

  @override
  int get hashCode => Object.hash(kind, key);
}

const _allMeds = JournalView(ViewKind.allMeds, '', 'All meds');
const _bp = JournalView(ViewKind.bp, '', 'Blood pressure');
const _hr = JournalView(ViewKind.hr, '', 'Heart rate');
const _temp = JournalView(ViewKind.temp, '', 'Temperature');

class DayAgg {
  final Map<String, int> doses = {};
  final Map<String, int> symptomMax = {};
  final List<int> sys = [];
  final List<int> dia = [];
  final List<int> hr = [];
  final List<double> temp = [];
  final List<LogEntry> entries = [];

  double? get avgSys => sys.isEmpty ? null : sys.reduce((a, b) => a + b) / sys.length;
  double? get avgDia => dia.isEmpty ? null : dia.reduce((a, b) => a + b) / dia.length;
  double? get avgHr => hr.isEmpty ? null : hr.reduce((a, b) => a + b) / hr.length;
  double? get maxTemp => temp.isEmpty ? null : temp.reduce((a, b) => a > b ? a : b);
}

Map<int, DayAgg> aggregate(List<LogEntry> logs) {
  final out = <int, DayAgg>{};
  for (final e in logs) {
    final d = out.putIfAbsent(e.at.day, DayAgg.new);
    d.entries.add(e);
    switch (e.kind) {
      case LogKind.med:
        d.doses[e.medId] = (d.doses[e.medId] ?? 0) + 1;
      case LogKind.symptom:
        final s = e.severity ?? 0;
        final prev = d.symptomMax[e.symptomName];
        if (prev == null || s > prev) d.symptomMax[e.symptomName] = s;
      case LogKind.vitals:
        if (e.hasBp) {
          d.sys.add(e.sys!);
          d.dia.add(e.dia!);
        }
        if (e.hr != null) d.hr.add(e.hr!);
        if (e.tempF != null) d.temp.add(e.tempF!);
    }
  }
  for (final d in out.values) {
    d.entries.sort((a, b) => a.at.compareTo(b.at));
  }
  return out;
}

// ------------------------------------------------------------------ color scales

const _blue = Color(0xFF5B8DEF);
const _green = Color(0xFF4CAF7A);
const _yellow = Color(0xFFF2C94C);
const _orange = Color(0xFFEE9A4D);
const _red = Color(0xFFE0603E);
const _darkRed = Color(0xFFB8322E);

(Color, String) bpCategory(double sys, double dia) {
  if (sys >= 140 || dia >= 90) return (_red, 'High 2');
  if (sys >= 130 || dia >= 80) return (_orange, 'High 1');
  if (sys >= 120) return (_yellow, 'Elevated');
  if (sys < 90 || dia < 60) return (_blue, 'Low');
  return (_green, 'Normal');
}

(Color, String) hrCategory(double hr) {
  if (hr > 120) return (_red, 'Very high');
  if (hr > 100) return (_orange, 'High');
  if (hr < 60) return (_blue, 'Low');
  return (_green, 'Normal');
}

(Color, String) tempCategory(double t) {
  if (t >= feverThresholdF) return (_red, 'Fever');
  if (t >= 99.5) return (_yellow, 'Raised');
  if (t < 96.5) return (_blue, 'Low');
  return (_green, 'Normal');
}

List<(Color, String)> legendFor(JournalView v, AppState state, ColorScheme scheme) {
  switch (v.kind) {
    case ViewKind.allMeds:
      return [
        for (final m in state.meds.where((m) => !m.isArchived)) (m.colorValue, m.name),
      ];
    case ViewKind.med:
      Color c = scheme.primary;
      for (final m in state.meds) {
        if (m.id == v.key) c = m.colorValue;
      }
      return [(c, 'Taken'), (scheme.surfaceContainerHighest, 'Not logged')];
    case ViewKind.symptom:
      return [
        (severityColor(2, scheme), 'Mild 1–3'),
        (severityColor(5, scheme), 'Moderate 4–6'),
        (severityColor(8, scheme), 'Severe 7–8'),
        (severityColor(10, scheme), '9–10'),
      ];
    case ViewKind.bp:
      return [
        (_blue, 'Low'),
        (_green, 'Normal'),
        (_yellow, 'Elevated'),
        (_orange, 'High 1'),
        (_red, 'High 2'),
      ];
    case ViewKind.hr:
      return [(_blue, '<60'), (_green, '60–100'), (_orange, '101–120'), (_red, '>120')];
    case ViewKind.temp:
      return [
        (_green, 'Normal'),
        (_yellow, '99.5+'),
        (_red, 'Fever ${feverThresholdF.toStringAsFixed(1)}+'),
      ];
  }
}

/// What one day looks like for a given view.
class CellLook {
  const CellLook({this.fill, this.text, this.dots = const []});

  final Color? fill;
  final String? text;
  final List<Color> dots;
}

CellLook cellLook(JournalView v, DayAgg? d, AppState state, ColorScheme scheme) {
  if (d == null) return const CellLook();
  switch (v.kind) {
    case ViewKind.allMeds:
      return CellLook(dots: [
        for (final m in state.meds)
          if ((d.doses[m.id] ?? 0) > 0) m.colorValue,
      ]);
    case ViewKind.med:
      final n = d.doses[v.key] ?? 0;
      if (n == 0) return const CellLook();
      Color c = scheme.primary;
      for (final m in state.meds) {
        if (m.id == v.key) c = m.colorValue;
      }
      return CellLook(fill: c, text: n > 1 ? '×$n' : '✓');
    case ViewKind.symptom:
      final s = d.symptomMax[v.key];
      if (s == null) return const CellLook();
      return CellLook(fill: severityColor(s, scheme), text: '$s');
    case ViewKind.bp:
      final s = d.avgSys, di = d.avgDia;
      if (s == null || di == null) return const CellLook();
      return CellLook(fill: bpCategory(s, di).$1, text: '${s.round()}\n${di.round()}');
    case ViewKind.hr:
      final h = d.avgHr;
      if (h == null) return const CellLook();
      return CellLook(fill: hrCategory(h).$1, text: '${h.round()}');
    case ViewKind.temp:
      final t = d.maxTemp;
      if (t == null) return const CellLook();
      return CellLook(fill: tempCategory(t).$1, text: t.toStringAsFixed(1));
  }
}

// ------------------------------------------------------------------ page

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  late DateTime _month;
  JournalView _view = _allMeds;
  JournalMode _mode = JournalMode.calendar;
  Stream<List<LogEntry>>? _stream;
  String? _streamFor;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  DateTime get _nextMonth => DateTime(_month.year, _month.month + 1);
  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;

  int get _elapsedDays {
    final now = DateTime.now();
    if (_month.year == now.year && _month.month == now.month) return now.day;
    return _month.isBefore(DateTime(now.year, now.month)) ? _daysInMonth : 0;
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  List<JournalView> _viewOptions(AppState state, List<LogEntry> logs) {
    final medIdsLogged = logs.where((l) => l.kind == LogKind.med).map((l) => l.medId).toSet();
    final symptomsLogged =
        logs.where((l) => l.kind == LogKind.symptom).map((l) => l.symptomName).toSet();
    final symptomNames = <String>[
      for (final s in state.symptoms)
        if (!s.archived || symptomsLogged.contains(s.name)) s.name,
    ];
    for (final n in symptomsLogged) {
      if (!symptomNames.contains(n)) symptomNames.add(n);
    }
    return [
      _allMeds,
      for (final m in state.meds)
        if (!m.isArchived || medIdsLogged.contains(m.id)) JournalView(ViewKind.med, m.id, m.name),
      _bp,
      _hr,
      _temp,
      for (final n in symptomNames) JournalView(ViewKind.symptom, n, n),
    ];
  }

  void _openDay(BuildContext context, int day, DayAgg? agg) {
    final state = AppScope.read(context);
    final date = DateTime(_month.year, _month.month, day);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => AppScope(
        state: state,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(DateFormat('EEEE, MMMM d').format(date),
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (agg == null || agg.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Nothing logged this day.'),
                )
              else
                for (final e in agg.entries) LogTile(entry: e),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${_month.year}-${_month.month}';
    if (_streamFor != key) {
      _streamFor = key;
      _stream = state.repo.watchLogs(_month, _nextMonth);
    }
    return StreamBuilder<List<LogEntry>>(
      stream: _stream,
      builder: (context, snap) {
        final logs = snap.data ?? const <LogEntry>[];
        final agg = aggregate(logs);
        final options = _viewOptions(state, logs);
        if (!options.contains(_view)) _view = _allMeds;
        final view = _view;

        final controls = [
          _MonthBar(
            month: _month,
            canGoForward: !_isCurrentMonth,
            mode: _mode,
            onShift: _shiftMonth,
            onMode: (m) => setState(() => _mode = m),
          ),
          if (_mode == JournalMode.calendar)
            _ViewChips(
              options: options,
              selected: view,
              onSelected: (v) => setState(() => _view = v),
            ),
        ];

        final main = _mode == JournalMode.calendar
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CalendarGrid(
                    month: _month,
                    agg: agg,
                    view: view,
                    onTapDay: (d) => _openDay(context, d, agg[d]),
                  ),
                  const SizedBox(height: 10),
                  _Legend(items: legendFor(view, state, Theme.of(context).colorScheme)),
                ],
              )
            : _TrackerGrid(
                month: _month,
                agg: agg,
                rows: options.where((o) => o.kind != ViewKind.allMeds).toList(),
                onTapDay: (d) => _openDay(context, d, agg[d]),
                onTapRow: (v) => setState(() {
                  _view = v;
                  _mode = JournalMode.calendar;
                }),
              );

        final stats = _StatsCard(
          view: _mode == JournalMode.tracker ? _allMeds : view,
          agg: agg,
          daysInMonth: _daysInMonth,
          elapsedDays: _elapsedDays,
          month: _month,
        );

        return LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= wideBreakpoint && _mode == JournalMode.calendar;
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                ...controls,
                const SizedBox(height: 8),
                main,
                const SizedBox(height: 16),
                stats,
              ],
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...controls,
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: main),
                    const SizedBox(width: 24),
                    Expanded(flex: 4, child: stats),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

// ------------------------------------------------------------------ controls

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.canGoForward,
    required this.mode,
    required this.onShift,
    required this.onMode,
  });

  final DateTime month;
  final bool canGoForward;
  final JournalMode mode;
  final ValueChanged<int> onShift;
  final ValueChanged<JournalMode> onMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => onShift(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            DateFormat('MMMM y').format(month),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: canGoForward ? () => onShift(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 4),
        SegmentedButton<JournalMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: JournalMode.calendar,
              icon: Icon(Icons.calendar_view_month),
              tooltip: 'Calendar',
            ),
            ButtonSegment(
              value: JournalMode.tracker,
              icon: Icon(Icons.grid_on),
              tooltip: 'Tracker',
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onMode(s.first),
        ),
      ],
    );
  }
}

class _ViewChips extends StatelessWidget {
  const _ViewChips({required this.options, required this.selected, required this.onSelected});

  final List<JournalView> options;
  final JournalView selected;
  final ValueChanged<JournalView> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final o = options[i];
          return Center(
            child: ChoiceChip(
              label: Text(o.label),
              avatar: Icon(switch (o.kind) {
                ViewKind.allMeds => Icons.medication,
                ViewKind.med => Icons.medication_outlined,
                ViewKind.symptom => Icons.sick_outlined,
                ViewKind.bp => Icons.bloodtype_outlined,
                ViewKind.hr => Icons.monitor_heart_outlined,
                ViewKind.temp => Icons.thermostat,
              }, size: 18),
              selected: o == selected,
              showCheckmark: false,
              onSelected: (_) => onSelected(o),
            ),
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (c, label) in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.bodySmall),
          ]),
      ],
    );
  }
}

// ------------------------------------------------------------------ calendar

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.agg,
    required this.view,
    required this.onTapDay,
  });

  final DateTime month;
  final Map<int, DayAgg> agg;
  final JournalView view;
  final ValueChanged<int> onTapDay;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month, 1).weekday % 7; // Sunday first
    final today = DateTime.now();
    final weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return LayoutBuilder(builder: (context, c) {
      final cell = (c.maxWidth / 7).floorToDouble();
      final cellH = (cell * 0.92).clamp(44.0, 84.0);
      final cells = <Widget>[];
      for (var i = 0; i < lead; i++) {
        cells.add(SizedBox(width: cell, height: cellH));
      }
      for (var d = 1; d <= days; d++) {
        final date = DateTime(month.year, month.month, d);
        final future = date.isAfter(today);
        final isToday = sameDay(date, today);
        final look = cellLook(view, agg[d], state, scheme);
        final fill = look.fill;
        final fg = fill == null ? scheme.onSurface : onColor(fill);
        cells.add(SizedBox(
          width: cell,
          height: cellH,
          child: Padding(
            padding: const EdgeInsets.all(2.5),
            child: Material(
              color: fill ?? (future ? Colors.transparent : scheme.surfaceContainerLow),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: isToday
                    ? BorderSide(color: scheme.primary, width: 2)
                    : BorderSide(color: scheme.outlineVariant.withValues(alpha: future ? 0.4 : 0.0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: future ? null : () => onTapDay(d),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$d',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                          color: future ? scheme.onSurfaceVariant.withValues(alpha: 0.5) : fg,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: look.dots.isNotEmpty
                              ? Wrap(
                                  spacing: 3,
                                  runSpacing: 3,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    for (final dc in look.dots.take(8))
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration:
                                            BoxDecoration(color: dc, shape: BoxShape.circle),
                                      ),
                                  ],
                                )
                              : look.text == null
                                  ? const SizedBox.shrink()
                                  : FittedBox(
                                      child: Text(
                                        look.text!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: fg,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          height: 1.05,
                                        ),
                                      ),
                                    ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
      }
      return Column(
        children: [
          Row(children: [
            for (final w in weekdays)
              SizedBox(
                width: cell,
                child: Text(w,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
          ]),
          const SizedBox(height: 4),
          Wrap(children: cells),
        ],
      );
    });
  }
}

// ------------------------------------------------------------------ tracker (bullet journal grid)

class _TrackerGrid extends StatelessWidget {
  const _TrackerGrid({
    required this.month,
    required this.agg,
    required this.rows,
    required this.onTapDay,
    required this.onTapRow,
  });

  final DateTime month;
  final Map<int, DayAgg> agg;
  final List<JournalView> rows;
  final ValueChanged<int> onTapDay;
  final ValueChanged<JournalView> onTapRow;

  static const _cell = 26.0;
  static const _gap = 3.0;
  static const _labelW = 112.0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final today = DateTime.now();
    final initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    Widget label(JournalView v) {
      Color? dot;
      if (v.kind == ViewKind.med) {
        for (final m in state.meds) {
          if (m.id == v.key) dot = m.colorValue;
        }
      }
      return InkWell(
        onTap: () => onTapRow(v),
        child: SizedBox(
          height: _cell + _gap,
          width: _labelW,
          child: Row(children: [
            if (dot != null) ...[
              Container(
                  width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(v.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            ),
          ]),
        ),
      );
    }

    Widget header() => Row(children: [
          for (var d = 1; d <= days; d++)
            SizedBox(
              width: _cell + _gap,
              child: Column(children: [
                Text(initials[DateTime(month.year, month.month, d).weekday - 1],
                    style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                Text('$d',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: sameDay(DateTime(month.year, month.month, d), today)
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: sameDay(DateTime(month.year, month.month, d), today)
                          ? scheme.primary
                          : scheme.onSurface,
                    )),
              ]),
            ),
        ]);

    Widget row(JournalView v) => Row(children: [
          for (var d = 1; d <= days; d++)
            Padding(
              padding: const EdgeInsets.only(right: _gap, bottom: _gap),
              child: _trackerCell(context, v, d, state, scheme, today),
            ),
        ]);

    String section(JournalView v) => switch (v.kind) {
          ViewKind.med || ViewKind.allMeds => 'Medicines',
          ViewKind.bp || ViewKind.hr || ViewKind.temp => 'Vitals',
          ViewKind.symptom => 'Symptoms',
        };

    // Group rows under small section titles, like a bullet journal spread.
    final labels = <Widget>[const SizedBox(height: 30)];
    final grid = <Widget>[header()];
    String? current;
    for (final v in rows) {
      final s = section(v);
      if (s != current) {
        current = s;
        labels.add(SizedBox(
          height: 22,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(s.toUpperCase(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.primary, letterSpacing: 0.8)),
          ),
        ));
        grid.add(const SizedBox(height: 22));
      }
      labels.add(label(v));
      grid.add(row(v));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: labels),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: grid),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Tap a name to see it as a calendar. Tap a square to see that day.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _trackerCell(BuildContext context, JournalView v, int d, AppState state,
      ColorScheme scheme, DateTime today) {
    final date = DateTime(month.year, month.month, d);
    final future = date.isAfter(today);
    final look = cellLook(v, agg[d], state, scheme);
    final fill = look.fill;
    String? text;
    if (fill != null && v.kind != ViewKind.med && v.kind != ViewKind.bp) {
      text = look.text?.split('.').first;
    }
    return GestureDetector(
      onTap: future ? null : () => onTapDay(d),
      child: Container(
        width: _cell,
        height: _cell,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ?? Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: fill == null
              ? Border.all(
                  color: scheme.outlineVariant.withValues(alpha: future ? 0.35 : 1),
                  width: sameDay(date, today) ? 2 : 1,
                )
              : null,
        ),
        child: text == null
            ? null
            : FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(text,
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700, color: onColor(fill!))),
                ),
              ),
      ),
    );
  }
}

// ------------------------------------------------------------------ stats

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.view,
    required this.agg,
    required this.daysInMonth,
    required this.elapsedDays,
    required this.month,
  });

  final JournalView view;
  final Map<int, DayAgg> agg;
  final int daysInMonth;
  final int elapsedDays;
  final DateTime month;

  String _date(int d) => DateFormat('MMM d').format(DateTime(month.year, month.month, d));

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = '${DateFormat('MMMM').format(month)} · ${view.label}';
    final children = <Widget>[];

    switch (view.kind) {
      case ViewKind.allMeds:
        final meds = state.meds.where((m) {
          final logged = agg.values.any((d) => (d.doses[m.id] ?? 0) > 0);
          return !m.isArchived || logged;
        }).toList();
        if (meds.isEmpty) children.add(const Text('No medicines yet.'));
        for (final m in meds) {
          final days = agg.values.where((d) => (d.doses[m.id] ?? 0) > 0).length;
          final frac = elapsedDays == 0 ? 0.0 : (days / elapsedDays).clamp(0.0, 1.0);
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(m.name, style: theme.textTheme.bodyMedium)),
                  Text('$days of $elapsedDays days', style: theme.textTheme.bodySmall),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 8,
                    color: m.colorValue,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ));
        }
      case ViewKind.med:
        final takenDays = <int>[
          for (var d = 1; d <= daysInMonth; d++)
            if ((agg[d]?.doses[view.key] ?? 0) > 0) d,
        ];
        final doses = agg.values.fold<int>(0, (s, d) => s + (d.doses[view.key] ?? 0));
        var best = 0, run = 0;
        for (var d = 1; d <= elapsedDays; d++) {
          if ((agg[d]?.doses[view.key] ?? 0) > 0) {
            run++;
            if (run > best) best = run;
          } else {
            run = 0;
          }
        }
        var current = 0;
        for (var d = elapsedDays; d >= 1; d--) {
          if ((agg[d]?.doses[view.key] ?? 0) > 0) {
            current++;
          } else if (d != elapsedDays) {
            break;
          }
        }
        children.add(_StatWrap([
          ('Days taken', '${takenDays.length} / $elapsedDays'),
          ('Doses', '$doses'),
          ('Longest streak', '$best days'),
          ('Current streak', '$current days'),
        ]));
        final missed = [
          for (var d = 1; d < elapsedDays; d++)
            if ((agg[d]?.doses[view.key] ?? 0) == 0) d,
        ];
        if (takenDays.isNotEmpty && missed.isNotEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Not logged: ${missed.map(_date).join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ));
        }
      case ViewKind.symptom:
        final pts = <(int, double)>[
          for (var d = 1; d <= daysInMonth; d++)
            if (agg[d]?.symptomMax[view.key] != null) (d, agg[d]!.symptomMax[view.key]!.toDouble()),
        ];
        if (pts.isEmpty) {
          children.add(const Text('Not logged this month.'));
        } else {
          final avg = pts.map((p) => p.$2).reduce((a, b) => a + b) / pts.length;
          final worst = pts.reduce((a, b) => b.$2 > a.$2 ? b : a);
          final severeDays = pts.where((p) => p.$2 >= severeSymptomLevel).length;
          children.add(_StatWrap([
            ('Days logged', '${pts.length}'),
            ('Average', avg.toStringAsFixed(1)),
            ('Worst', '${worst.$2.round()} on ${_date(worst.$1)}'),
            ('Severe days', '$severeDays'),
          ]));
          children.add(const SizedBox(height: 14));
          children.add(MonthChart(
            daysInMonth: daysInMonth,
            minY: 0,
            maxY: 10,
            series: [ChartSeries(name: view.label, color: severityColor(7, scheme), points: pts)],
          ));
        }
      case ViewKind.bp:
        final sys = [for (final d in agg.values) ...d.sys];
        final dia = [for (final d in agg.values) ...d.dia];
        if (sys.isEmpty) {
          children.add(const Text('No blood pressure readings this month.'));
        } else {
          double avg(List<int> l) => l.reduce((a, b) => a + b) / l.length;
          int mn(List<int> l) => l.reduce((a, b) => a < b ? a : b);
          int mx(List<int> l) => l.reduce((a, b) => a > b ? a : b);
          children.add(_StatWrap([
            ('Readings', '${sys.length}'),
            ('Average', '${avg(sys).round()}/${avg(dia).round()}'),
            ('Systolic range', '${mn(sys)}–${mx(sys)}'),
            ('Diastolic range', '${mn(dia)}–${mx(dia)}'),
          ]));
          children.add(const SizedBox(height: 14));
          children.add(MonthChart(
            daysInMonth: daysInMonth,
            series: [
              ChartSeries(name: 'Systolic', color: _red, points: [
                for (var d = 1; d <= daysInMonth; d++)
                  if (agg[d]?.avgSys != null) (d, agg[d]!.avgSys!),
              ]),
              ChartSeries(name: 'Diastolic', color: _blue, points: [
                for (var d = 1; d <= daysInMonth; d++)
                  if (agg[d]?.avgDia != null) (d, agg[d]!.avgDia!),
              ]),
            ],
          ));
        }
      case ViewKind.hr:
        final hr = [for (final d in agg.values) ...d.hr];
        if (hr.isEmpty) {
          children.add(const Text('No heart rate readings this month.'));
        } else {
          children.add(_StatWrap([
            ('Readings', '${hr.length}'),
            ('Average', '${(hr.reduce((a, b) => a + b) / hr.length).round()} bpm'),
            ('Lowest', '${hr.reduce((a, b) => a < b ? a : b)}'),
            ('Highest', '${hr.reduce((a, b) => a > b ? a : b)}'),
          ]));
          children.add(const SizedBox(height: 14));
          children.add(MonthChart(
            daysInMonth: daysInMonth,
            series: [
              ChartSeries(name: 'Heart rate', color: _darkRed, points: [
                for (var d = 1; d <= daysInMonth; d++)
                  if (agg[d]?.avgHr != null) (d, agg[d]!.avgHr!),
              ]),
            ],
          ));
        }
      case ViewKind.temp:
        final t = [for (final d in agg.values) ...d.temp];
        if (t.isEmpty) {
          children.add(const Text('No temperature readings this month.'));
        } else {
          final feverDays =
              agg.values.where((d) => (d.maxTemp ?? 0) >= feverThresholdF).length;
          children.add(_StatWrap([
            ('Readings', '${t.length}'),
            ('Highest', '${t.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}°F'),
            ('Fever days', '$feverDays'),
          ]));
          children.add(const SizedBox(height: 14));
          children.add(MonthChart(
            daysInMonth: daysInMonth,
            threshold: feverThresholdF,
            thresholdLabel: 'fever',
            series: [
              ChartSeries(name: 'Highest temp', color: _orange, points: [
                for (var d = 1; d <= daysInMonth; d++)
                  if (agg[d]?.maxTemp != null) (d, agg[d]!.maxTemp!),
              ]),
            ],
          ));
        }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatWrap extends StatelessWidget {
  const _StatWrap(this.items);

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (label, value) in items)
            Container(
              width: w,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      );
    });
  }
}
