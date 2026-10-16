import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import 'theme.dart';

// ------------------------------------------------------------------ dialogs

Future<String?> askText(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
  String action = 'Save',
  bool barrierDismissible = true,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        if (barrierDismissible)
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(action)),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'OK',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void toast(BuildContext context, String message, {SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Lets the person pick a time today (for logging something after the fact).
Future<DateTime?> pickTimeToday(BuildContext context, DateTime initial) async {
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (t == null) return null;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, t.hour, t.minute);
}

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child),
      ),
    ),
  );
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.at, required this.onChanged});

  final DateTime at;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final isNow = DateTime.now().difference(at).inMinutes.abs() < 2;
    return Row(
      children: [
        const Icon(Icons.schedule, size: 20),
        const SizedBox(width: 8),
        Text(isNow ? 'Now' : 'Today at ${DateFormat.jm().format(at)}'),
        const Spacer(),
        TextButton(
          onPressed: () async {
            final t = await pickTimeToday(context, at);
            if (t != null) onChanged(t);
          },
          child: const Text('Change time'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ medicines

Future<void> showMedEditor(BuildContext context, AppState state, {Med? med}) {
  return _sheet(context, _MedEditor(state: state, med: med));
}

class _MedEditor extends StatefulWidget {
  const _MedEditor({required this.state, this.med});

  final AppState state;
  final Med? med;

  @override
  State<_MedEditor> createState() => _MedEditorState();
}

class _MedEditorState extends State<_MedEditor> {
  late final _name = TextEditingController(text: widget.med?.name ?? '');
  late final _dose = TextEditingController(text: widget.med?.dose ?? '');
  late int _color = widget.med?.color ?? _nextColor();
  bool _busy = false;

  int _nextColor() {
    final used = widget.state.meds.where((m) => !m.isArchived).map((m) => m.color).toSet();
    return medPalette.firstWhere((c) => !used.contains(c), orElse: () => medPalette.first);
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      if (widget.med == null) {
        await widget.state.repo.addMed(name: name, dose: _dose.text, color: _color);
      } else {
        await widget.state.repo
            .updateMed(widget.med!.id, name: name, dose: _dose.text, color: _color);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t save: $e');
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.med == null ? 'Add medicine' : 'Edit medicine',
            style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autofocus: widget.med == null,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. 6-MP'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dose,
          decoration: const InputDecoration(labelText: 'Dose (optional)', hintText: 'e.g. 50 mg'),
        ),
        const SizedBox(height: 16),
        Text('Color', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in medPalette)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == c ? theme.colorScheme.onSurface : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: _color == c ? Icon(Icons.check, color: onColor(Color(c))) : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Padding(padding: EdgeInsets.all(12), child: Text('Save')),
        ),
      ],
    );
  }
}

/// Long-press menu for a medicine.
Future<void> showMedActions(BuildContext context, AppState state, Med med) {
  return _sheet(
    context,
    Builder(builder: (ctx) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(med.label, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.more_time),
            title: const Text('Log at a different time'),
            onTap: () async {
              final at = await pickTimeToday(ctx, DateTime.now());
              if (at == null) return;
              await state.repo.logMed(med, me: state.me, at: at);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                toast(context, 'Logged ${med.name} at ${DateFormat.jm().format(at)}');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit name, dose or color'),
            onTap: () {
              Navigator.pop(ctx);
              showMedEditor(context, state, med: med);
            },
          ),
          ListTile(
            leading: Icon(med.isPaused ? Icons.play_arrow_outlined : Icons.pause_outlined),
            title: Text(med.isPaused ? 'Resume' : 'Pause'),
            subtitle: Text(med.isPaused
                ? 'Show it on the dashboard and widget again'
                : 'Hide it from the dashboard and widget for now, e.g. during a break'),
            onTap: () async {
              await state.repo.updateMed(med.id, status: med.isPaused ? 'active' : 'paused');
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            title: const Text('Remove'),
            subtitle: const Text('Past doses stay in the journal'),
            onTap: () async {
              final ok = await confirm(
                ctx,
                title: 'Remove ${med.name}?',
                message:
                    'It disappears from the dashboard and widget. Its history stays in the journal, and you can restore it in Settings.',
                action: 'Remove',
                destructive: true,
              );
              if (!ok) return;
              await state.repo.updateMed(med.id, status: 'archived');
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      );
    }),
  );
}

// ------------------------------------------------------------------ vitals

Future<void> showVitalsSheet(BuildContext context, AppState state) {
  return _sheet(context, _VitalsSheet(state: state));
}

class _VitalsSheet extends StatefulWidget {
  const _VitalsSheet({required this.state});

  final AppState state;

  @override
  State<_VitalsSheet> createState() => _VitalsSheetState();
}

class _VitalsSheetState extends State<_VitalsSheet> {
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _hr = TextEditingController();
  final _temp = TextEditingController();
  final _note = TextEditingController();
  DateTime _at = DateTime.now();
  String? _error;

  @override
  void dispose() {
    for (final c in [_sys, _dia, _hr, _temp, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _save() async {
    final sys = _int(_sys);
    final dia = _int(_dia);
    final hr = _int(_hr);
    final temp = double.tryParse(_temp.text.trim().replaceAll(',', '.'));
    String? err;
    if ((sys == null) != (dia == null)) {
      err = 'Enter both blood pressure numbers (e.g. 120 / 80).';
    } else if (sys != null && (sys < 50 || sys > 260 || dia! < 30 || dia > 180)) {
      err = 'Blood pressure looks off. Check the numbers.';
    } else if (hr != null && (hr < 25 || hr > 250)) {
      err = 'Heart rate looks off. Check the number.';
    } else if (temp != null && (temp < 90 || temp > 110)) {
      err = 'Enter temperature in °F (e.g. 98.6).';
    } else if (sys == null && hr == null && temp == null) {
      err = 'Enter at least one reading.';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final state = widget.state;
    await state.repo.logVitals(
      me: state.me,
      sys: sys,
      dia: dia,
      hr: hr,
      tempF: temp,
      note: _note.text,
      at: _at,
    );
    if (!mounted) return;
    Navigator.pop(context);
    if (temp != null && temp >= feverThresholdF) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.thermostat, size: 36),
          title: Text('Fever: ${temp.toStringAsFixed(1)}°F'),
          content: const Text(
              'A fever during chemo can be serious. Follow her care team\'s fever instructions, which usually means calling them right away.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } else {
      toast(context, 'Vitals saved');
    }
  }

  Widget _num(TextEditingController c, String label, {bool decimal = false, String? suffix}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]')),
      ],
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Log vitals', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Fill in whatever you measured.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _num(_sys, 'Systolic', suffix: 'top')),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('/')),
          Expanded(child: _num(_dia, 'Diastolic', suffix: 'bottom')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _num(_hr, 'Heart rate', suffix: 'bpm')),
          const SizedBox(width: 12),
          Expanded(child: _num(_temp, 'Temperature', decimal: true, suffix: '°F')),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 8),
        _TimeRow(at: _at, onChanged: (t) => setState(() => _at = t)),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _save,
          child: const Padding(padding: EdgeInsets.all(12), child: Text('Save')),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ symptoms

Future<void> showSymptomSheet(BuildContext context, AppState state, SymptomType symptom) {
  return _sheet(context, _SymptomSheet(state: state, symptom: symptom));
}

class _SymptomSheet extends StatefulWidget {
  const _SymptomSheet({required this.state, required this.symptom});

  final AppState state;
  final SymptomType symptom;

  @override
  State<_SymptomSheet> createState() => _SymptomSheetState();
}

class _SymptomSheetState extends State<_SymptomSheet> {
  int? _severity;
  final _note = TextEditingController();
  DateTime _at = DateTime.now();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = _severity;
    if (s == null) return;
    final state = widget.state;
    await state.repo.logSymptom(
      me: state.me,
      symptomName: widget.symptom.name,
      severity: s,
      note: _note.text,
      at: _at,
    );
    if (!mounted) return;
    Navigator.pop(context);
    toast(context, '${widget.symptom.name} $s/10 saved');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.symptom.name, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('How bad is it right now? 0 = none, 10 = worst',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i <= 10; i++)
              _SeverityDot(
                value: i,
                selected: _severity == i,
                onTap: () => setState(() => _severity = i),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            _severity == null ? 'Tap a number' : severityLabel(_severity!),
            style: theme.textTheme.titleMedium?.copyWith(
              color: _severity == null ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 8),
        _TimeRow(at: _at, onChanged: (t) => setState(() => _at = t)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _severity == null ? null : _save,
          child: const Padding(padding: EdgeInsets.all(12), child: Text('Save')),
        ),
      ],
    );
  }
}

class _SeverityDot extends StatelessWidget {
  const _SeverityDot({required this.value, required this.selected, required this.onTap});

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = severityColor(value, scheme);
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? scheme.onSurface : Colors.transparent, width: 3),
        ),
        child: Text(
          '$value',
          style: TextStyle(color: onColor(bg), fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }
}
