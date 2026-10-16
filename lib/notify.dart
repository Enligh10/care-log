import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'config.dart';
import 'models.dart';

/// Push notifications through ntfy (https://ntfy.sh), a free notification
/// app. Each person who wants alerts gets a private, random topic name and
/// subscribes to it in the ntfy app.
class Notifier {
  static const server = 'https://ntfy.sh';

  static Future<void> sendForLog(LogEntry e, List<Member> recipients) async {
    final time = DateFormat.jm().format(e.at);
    final who = e.byName.isEmpty ? 'Someone' : e.byName;
    for (final m in recipients) {
      if (!m.hasNotifications) continue;
      switch (e.kind) {
        case LogKind.med:
          if (!m.notifyMeds) continue;
          await send(
            m.ntfyTopic,
            title: '$who took ${e.medName}',
            message: '${e.dose.isEmpty ? 'Logged' : e.dose} at $time',
            tags: 'pill',
          );
        case LogKind.vitals:
          final t = e.tempF;
          if (t != null && t >= feverThresholdF && m.notifyFever) {
            await send(
              m.ntfyTopic,
              title: 'Temperature ${t.toStringAsFixed(1)}°F',
              message: 'Logged by $who at $time. Follow her care team\'s fever instructions.',
              tags: 'thermometer,warning',
              priority: 5,
            );
          }
        case LogKind.symptom:
          final s = e.severity ?? 0;
          if (s >= severeSymptomLevel && m.notifySevere) {
            await send(
              m.ntfyTopic,
              title: '${e.symptomName} $s/10',
              message: 'Logged by $who at $time${e.note.isEmpty ? '' : ': ${e.note}'}',
              tags: 'warning',
              priority: 4,
            );
          }
      }
    }
  }

  /// Sends one notification. Parameters go in the query string so a browser
  /// can send it as a "simple" request without a CORS preflight.
  static Future<bool> send(
    String topic, {
    required String title,
    required String message,
    String tags = '',
    int priority = 3,
  }) async {
    if (topic.isEmpty) return false;
    final uri = Uri.parse('$server/$topic').replace(queryParameters: {
      'title': title,
      if (tags.isNotEmpty) 'tags': tags,
      if (priority != 3) 'priority': '$priority',
    });
    try {
      final res = await http
          .post(uri, body: message)
          .timeout(const Duration(seconds: 15));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
