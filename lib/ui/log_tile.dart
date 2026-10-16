import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import 'sheets.dart';
import 'theme.dart';

String describeVitals(LogEntry e) {
  final parts = <String>[
    if (e.hasBp) 'BP ${e.sys}/${e.dia}',
    if (e.hr != null) 'HR ${e.hr}',
    if (e.tempF != null) '${e.tempF!.toStringAsFixed(1)}°F',
  ];
  return parts.isEmpty ? 'Vitals' : parts.join(' · ');
}

String _source(String src) => switch (src) {
      'widget' => ' · widget',
      'shortcut' => ' · iPhone shortcut',
      _ => '',
    };

/// One entry in a day's log. Swipe to delete (with undo).
class LogTile extends StatelessWidget {
  const LogTile({super.key, required this.entry, this.showDate = false});

  final LogEntry entry;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final e = entry;
    final time = showDate
        ? DateFormat('MMM d, h:mm a').format(e.at)
        : DateFormat.jm().format(e.at);
    final who = e.byName.isEmpty ? '' : ' · ${e.byName}';

    Widget leading;
    String title;
    String? extra;
    switch (e.kind) {
      case LogKind.med:
        Color c = scheme.outline;
        for (final m in state.meds) {
          if (m.id == e.medId) c = m.colorValue;
        }
        leading = CircleAvatar(
          radius: 18,
          backgroundColor: c.withValues(alpha: 0.18),
          child: Icon(Icons.medication, color: c, size: 20),
        );
        title = e.dose.isEmpty ? e.medName : '${e.medName} · ${e.dose}';
      case LogKind.vitals:
        final fever = (e.tempF ?? 0) >= feverThresholdF;
        leading = CircleAvatar(
          radius: 18,
          backgroundColor: fever ? scheme.errorContainer : scheme.secondaryContainer,
          child: Icon(fever ? Icons.thermostat : Icons.favorite_outline,
              color: fever ? scheme.onErrorContainer : scheme.onSecondaryContainer, size: 20),
        );
        title = describeVitals(e);
      case LogKind.symptom:
        final s = e.severity ?? 0;
        final bg = severityColor(s, scheme);
        leading = CircleAvatar(
          radius: 18,
          backgroundColor: bg,
          child: Text('$s', style: TextStyle(color: onColor(bg), fontWeight: FontWeight.w700)),
        );
        title = '${e.symptomName} · ${severityLabel(s)}';
    }
    if (e.note.isNotEmpty) extra = e.note;

    return Dismissible(
      key: ValueKey('log-${e.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) async {
        await state.repo.deleteLog(e.id);
        if (context.mounted) {
          toast(
            context,
            'Entry deleted',
            action: SnackBarAction(label: 'Undo', onPressed: () => state.repo.restoreLog(e)),
          );
        }
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: leading,
        title: Text(title),
        subtitle: Text('$time$who${_source(e.src)}${extra == null ? '' : '\n$extra'}'),
        isThreeLine: extra != null,
      ),
    );
  }
}
