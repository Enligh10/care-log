import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import 'config.dart';
import 'models.dart';
import 'repo.dart';

/// Fully qualified name of the Kotlin AppWidgetProvider.
const _provider = 'app.carelog.care_log.MedWidgetProvider';

/// Upper limit on rows written to the widget (the list scrolls).
const maxWidgetRows = 40;

bool get widgetsSupported => defaultTargetPlatform == TargetPlatform.android;

Future<void> initWidgetBridge() async {
  if (!widgetsSupported) return;
  try {
    await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  } catch (e) {
    debugPrint('Widget callback registration failed: $e');
  }
}

Future<void> requestPinWidget() async {
  if (!widgetsSupported) return;
  await HomeWidget.requestPinWidget(qualifiedAndroidName: _provider);
}

/// Widget size: 0 small, 1 medium (default), 2 large, 3 extra large.
/// The widget's own A− / A+ buttons change the same setting.
Future<int> getWidgetSize() async {
  try {
    final v = await HomeWidget.getWidgetData<String>('size');
    return (int.tryParse(v ?? '') ?? 1).clamp(0, 3);
  } catch (_) {
    return 1;
  }
}

Future<void> setWidgetSize(int size) async {
  if (!widgetsSupported) return;
  await _save('size', '${size.clamp(0, 3)}');
  await _redraw();
}

Future<void> _save(String key, String value) =>
    HomeWidget.saveWidgetData<String>(key, value);

Future<void> _redraw() => HomeWidget.updateWidget(qualifiedAndroidName: _provider);

Future<void> _stamp(String text) async {
  await _save('updated', text);
  await _save('updated_ms', '${DateTime.now().millisecondsSinceEpoch}');
}

/// Writes today's medicine status into the widget's storage and redraws it.
Future<void> syncWidget(
  List<Med> meds,
  List<LogEntry> todayLogs, {
  required String profileId,
  String? title,
  String? notice,
  String? noticeMedId,
}) async {
  if (!widgetsSupported) return;
  try {
    final active = meds.where((m) => m.isActive).take(maxWidgetRows).toList();
    await _save('profile', profileId);
    if (title != null && title.isNotEmpty) await _save('title', '$title · meds today');
    await _save('count', '${active.length}');
    await _save('message', active.isEmpty ? 'No medicines yet. Tap to open Care Log.' : '');
    for (var i = 0; i < active.length; i++) {
      final m = active[i];
      final doses = todayLogs
          .where((l) => l.kind == LogKind.med && l.medId == m.id)
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));
      final n = doses.length;
      final progress = m.progress(n);
      String status;
      if (n == 0) {
        status = m.dosesPerDay > 1 ? '0 of ${m.dosesPerDay}' : 'Tap to log';
      } else {
        final time = DateFormat.jm().format(doses.first.at);
        if (m.asNeeded) {
          status = '×$n · $time';
        } else if (m.dosesPerDay > 1) {
          status = '$n of ${m.dosesPerDay} · $time';
        } else {
          final who = doses.first.byName.split(' ').first;
          status = '✓ $time${n > 1 ? ' ×$n' : ''}${who.isEmpty ? '' : ' · $who'}';
        }
      }
      if (notice != null && noticeMedId == m.id) status = notice;
      await _save('m${i}_id', m.id);
      await _save('m${i}_name', m.dose.isEmpty ? m.name : '${m.name} · ${m.dose}');
      await _save('m${i}_status', status);
      await _save(
        'm${i}_taken',
        switch (progress) {
          DoseProgress.none => '0',
          DoseProgress.partial => 'part',
          DoseProgress.complete || DoseProgress.extra => '1',
        },
      );
      await _save('m${i}_color', '${m.color}');
    }
    await _stamp('Updated ${DateFormat.jm().format(DateTime.now())}');
    await _redraw();
  } catch (e) {
    debugPrint('Widget sync failed: $e');
  }
}

Future<void> showWidgetMessage(String message) async {
  if (!widgetsSupported) return;
  try {
    await _save('count', '0');
    await _save('message', message);
    await _stamp('');
    await _redraw();
  } catch (_) {}
}

Future<void> _setRowStatus(String? medId, String status) async {
  if (medId == null) return;
  final count = int.tryParse(await HomeWidget.getWidgetData<String>('count') ?? '0') ?? 0;
  for (var i = 0; i < count; i++) {
    if (await HomeWidget.getWidgetData<String>('m${i}_id') == medId) {
      await _save('m${i}_status', status);
      await _redraw();
      return;
    }
  }
}

/// Runs in the background when a widget row or the refresh button is tapped.
///
/// `carelog://log?id=<medId>` logs the next dose of that medicine. To avoid
/// accidental doses it won't log within a minute of the last one, or past
/// the medicine's daily target (extra doses are logged in the app).
/// `carelog://refresh` just reloads today's status.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: firebaseOptions);
    }
  } catch (e) {
    debugPrint('Firebase init in widget callback failed: $e');
  }

  final user = FirebaseAuth.instance.currentUser ??
      await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 6), onTimeout: () => null);
  if (user == null) {
    await showWidgetMessage('Open Care Log and sign in.');
    return;
  }

  var profileId = await HomeWidget.getWidgetData<String>('profile') ?? '';
  if (profileId.isEmpty) {
    try {
      profileId = (await Accounts.fetchUser(user.uid)).activeProfile;
    } catch (_) {}
  }
  if (profileId.isEmpty) {
    await showWidgetMessage('Open Care Log to finish setup.');
    return;
  }
  final repo = Repo(profileId);
  final startOfDay = dayOf(DateTime.now());
  final isLog = uri?.host == 'log';
  final medId = uri?.queryParameters['id'];

  try {
    if (isLog) await _setRowStatus(medId, 'Logging…');

    final meds = await repo.fetchMeds();
    final today = await repo.fetchLogsSince(startOfDay);
    String? notice;

    if (isLog && medId != null) {
      final matches = meds.where((m) => m.id == medId).toList();
      if (matches.isNotEmpty) {
        final med = matches.first;
        final prior = today.where((l) => l.kind == LogKind.med && l.medId == med.id).toList()
          ..sort((a, b) => b.at.compareTo(a.at));
        final sinceLast =
            prior.isEmpty ? null : DateTime.now().difference(prior.first.at).inSeconds.abs();
        if (sinceLast != null && sinceLast < 60) {
          notice = 'Just logged ✓ ${DateFormat.jm().format(prior.first.at)}';
        } else if (!med.asNeeded && prior.length >= med.dosesPerDay) {
          notice = med.dosesPerDay == 1
              ? 'Already logged ✓ ${DateFormat.jm().format(prior.first.at)}'
              : 'All ${med.dosesPerDay} logged ✓ · extras in app';
        } else {
          final me = await repo.fetchMember(user.uid) ??
              Member(uid: user.uid, name: user.displayName ?? user.email?.split('@').first ?? '');
          final entry = await repo.logMed(med, me: me, src: 'widget');
          today.insert(0, entry);
        }
      }
    }
    await syncWidget(meds, today, profileId: profileId, notice: notice, noticeMedId: medId);
  } catch (e) {
    debugPrint('Widget callback failed: $e');
    await _stamp('Couldn\'t update. Check your connection.');
    if (isLog) await _setRowStatus(medId, 'Not logged. Try again');
    await _redraw();
  }
}
