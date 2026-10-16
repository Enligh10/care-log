import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import 'log_tile.dart';
import 'sheets.dart';
import 'theme.dart';

const commonSymptoms = [
  'Nausea',
  'Fatigue',
  'Pain',
  'Headache',
  'Mouth sores',
  'Diarrhea',
  'Constipation',
  'Numbness / tingling',
  'Low appetite',
  'Acne',
];

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        DateFormat('EEEE, MMMM d').format(DateTime.now()),
        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
    final left = [
      _SectionHeader(
        'Medicines',
        action: TextButton.icon(
          onPressed: () => showMedEditor(context, state),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
      ),
      _MedGrid(state: state),
      if (state.pausedMeds.isNotEmpty) _PausedMeds(state: state),
      const SizedBox(height: 20),
      const _SectionHeader('Vitals'),
      _VitalsCard(state: state),
    ];
    final right = [
      _SectionHeader(
        'Symptoms',
        action: TextButton.icon(
          onPressed: () => _newSymptom(context, state),
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
      ),
      _SymptomChips(state: state),
      const SizedBox(height: 20),
      _SectionHeader('Today\'s log', trailing: '${state.today.length}'),
      if (state.today.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('Nothing logged yet today.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        )
      else
        for (final e in state.today) LogTile(entry: e),
    ];

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= wideBreakpoint;
      if (!wide) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [header, ...left, const SizedBox(height: 20), ...right],
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                const SizedBox(width: 28),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
              ],
            ),
          ],
        ),
      );
    });
  }
}

Future<void> _newSymptom(BuildContext context, AppState state) async {
  final name = await askText(context, title: 'New symptom', hint: 'e.g. Nausea', action: 'Add');
  if (name != null && name.trim().isNotEmpty) await state.repo.addSymptom(name);
}

Future<void> logMedWithUndo(BuildContext context, AppState state, Med med) async {
  final doses = state.dosesToday(med);
  if (doses.isNotEmpty) {
    final last = doses.first;
    final ok = await confirm(
      context,
      title: '${med.name} already logged',
      message: 'Logged at ${DateFormat.jm().format(last.at)}'
          '${last.byName.isEmpty ? '' : ' by ${last.byName}'}. Log another dose?',
      action: 'Log another',
    );
    if (!ok) return;
  }
  HapticFeedback.mediumImpact();
  final entry = await state.repo.logMed(med, me: state.me);
  if (!context.mounted) return;
  toast(
    context,
    'Logged ${med.name} · ${DateFormat.jm().format(entry.at)}',
    action: SnackBarAction(label: 'Undo', onPressed: () => state.repo.deleteLog(entry.id)),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.action, this.trailing});

  final String title;
  final Widget? action;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ medicines

class _MedGrid extends StatelessWidget {
  const _MedGrid({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!state.medsLoaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final meds = state.activeMeds;
    if (meds.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.medication_outlined, size: 36),
              const SizedBox(height: 8),
              const Text('Add each medicine once. Then one tap logs a dose.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => showMedEditor(context, state),
                icon: const Icon(Icons.add),
                label: const Text('Add medicine'),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 520 ? 3 : 2;
      const gap = 10.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final m in meds)
            SizedBox(width: w, child: _MedCard(state: state, med: m)),
        ],
      );
    });
  }
}

class _MedCard extends StatelessWidget {
  const _MedCard({required this.state, required this.med});

  final AppState state;
  final Med med;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doses = state.dosesToday(med);
    final taken = doses.isNotEmpty;
    final color = med.colorValue;
    final last = taken ? doses.first : null;

    return Material(
      color: taken ? color.withValues(alpha: 0.16) : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: taken ? color : scheme.outlineVariant, width: taken ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => logMedWithUndo(context, state, med),
        onLongPress: () => showMedActions(context, state, med),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      med.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => showMedActions(context, state, med),
                    ),
                  ),
                ],
              ),
              if (med.dose.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text(med.dose,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    taken ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 22,
                    color: taken ? color : scheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      taken
                          ? '${DateFormat.jm().format(last!.at)}'
                              '${doses.length > 1 ? ' ×${doses.length}' : ''}'
                              '${last.byName.isEmpty ? '' : ' · ${last.byName}'}'
                          : 'Tap when taken',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: taken ? FontWeight.w600 : FontWeight.normal,
                        color: taken ? scheme.onSurface : scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PausedMeds extends StatelessWidget {
  const _PausedMeds({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Paused:', style: theme.textTheme.bodySmall),
          for (final m in state.pausedMeds)
            ActionChip(
              avatar: const Icon(Icons.pause, size: 16),
              label: Text(m.name),
              onPressed: () => showMedActions(context, state, m),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ vitals

class _VitalsCard extends StatelessWidget {
  const _VitalsCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    LogEntry? last;
    for (final e in state.today) {
      if (e.kind == LogKind.vitals) {
        last = e;
        break;
      }
    }
    final fever = (last?.tempF ?? 0) >= feverThresholdF;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showVitalsSheet(context, state),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: fever ? scheme.errorContainer : scheme.primaryContainer,
                child: Icon(fever ? Icons.thermostat : Icons.monitor_heart_outlined,
                    color: fever ? scheme.onErrorContainer : scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(last == null ? 'No readings today' : describeVitals(last),
                        style: theme.textTheme.titleMedium),
                    Text(
                      last == null
                          ? 'Blood pressure, heart rate, temperature'
                          : 'Last at ${DateFormat.jm().format(last.at)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => showVitalsSheet(context, state),
                child: const Text('Log'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ symptoms

class _SymptomChips extends StatelessWidget {
  const _SymptomChips({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final symptoms = state.activeSymptoms;
    if (symptoms.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('Add the symptoms you want to track. Tap one to rate it 0–10.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      for (final s in commonSymptoms) {
                        await state.repo.addSymptom(s);
                      }
                    },
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Add common ones'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _newSymptom(context, state),
                    icon: const Icon(Icons.add),
                    label: const Text('Add my own'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in symptoms) _chip(context, s, scheme),
      ],
    );
  }

  Widget _chip(BuildContext context, SymptomType s, ColorScheme scheme) {
    int? latest;
    for (final e in state.today) {
      if (e.kind == LogKind.symptom && e.symptomName == s.name) {
        latest = e.severity;
        break;
      }
    }
    final bg = latest == null ? null : severityColor(latest, scheme);
    return GestureDetector(
      onLongPress: () async {
        final ok = await confirm(
          context,
          title: 'Stop tracking ${s.name}?',
          message: 'It\'s removed from this list. Past entries stay in the journal.',
          action: 'Remove',
          destructive: true,
        );
        if (ok) await state.repo.setSymptomArchived(s.id, true);
      },
      child: ActionChip(
        label: Text(s.name),
        avatar: latest == null
            ? null
            : CircleAvatar(
                backgroundColor: bg,
                child: Text('$latest',
                    style: TextStyle(fontSize: 11, color: onColor(bg!), fontWeight: FontWeight.w700)),
              ),
        onPressed: () => showSymptomSheet(context, state, s),
      ),
    );
  }
}
