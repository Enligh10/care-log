import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import 'settings_page.dart';
import 'sheets.dart';

/// Step-by-step setup for iPhone home-screen buttons that log a dose with
/// one tap, using Apple's built-in Shortcuts app (no App Store app needed).
class ShortcutsPage extends StatefulWidget {
  const ShortcutsPage({super.key});

  @override
  State<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends State<ShortcutsPage> {
  String? _key;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final k = await AppScope.read(context).repo.getOrCreateQuickKey();
      if (mounted) setState(() => _key = k);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _url(String logsPath) =>
      'https://firestore.googleapis.com/v1/projects/$firebaseProjectId/databases/(default)/documents/$logsPath?key=$firebaseApiKey';

  String _body(Med m, String byName) {
    final fields = {
      'kind': {'stringValue': 'med'},
      'medId': {'stringValue': m.id},
      'medName': {'stringValue': m.name},
      'dose': {'stringValue': m.dose},
      'byName': {'stringValue': byName},
      'src': {'stringValue': 'shortcut'},
      'qk': {'stringValue': _key},
      'at': {'timestampValue': 'NOW'},
    };
    return jsonEncode({'fields': fields});
  }

  String _ntfyUrl(String topic, Med m, String byName) => Uri.parse('https://ntfy.sh/$topic')
      .replace(queryParameters: {'title': '$byName took ${m.name}', 'tags': 'pill'})
      .toString();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final me = state.me;
    final others = state.members.where((m) => m.uid != me.uid && m.hasNotifications).toList();
    final meds = [...state.activeMeds, ...state.pausedMeds];

    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 11, child: Text(n, style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('iPhone shortcuts')),
      body: _key == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    Text(
                      'Make a home-screen button for each medicine. One tap logs the dose'
                      '${others.isEmpty ? '' : ' and notifies ${others.map((o) => o.name).join(' & ')}'}. '
                      'Do this on the iPhone, from this page in Safari or the home-screen app, so you can copy and paste.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (others.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Tip: turn on notifications on the other phone first (Settings → Notifications), '
                          'then come back here so the steps include the notification.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (meds.isEmpty) const Text('Add medicines on the Today screen first.'),
                    for (final m in meds)
                      Card(
                        child: Theme(
                          data: theme.copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            leading: CircleAvatar(radius: 8, backgroundColor: m.colorValue),
                            title: Text('"Took ${m.name}" button'),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              step('1', 'Open the Shortcuts app, tap +, and rename the shortcut to "Took ${m.name}".'),
                              step('2', 'Add the action "Text" and paste this into it:'),
                              const SizedBox(height: 6),
                              CopyBox(text: _body(m, me.name)),
                              step('3',
                                  'In that text, select the word NOW and replace it: tap "Current Date" above the keyboard. '
                                  'Then tap the blue Current Date, choose Date Format → ISO 8601, and turn on "Include ISO 8601 Time".'),
                              step('4', 'Add the action "Get Contents of URL" and paste this as the URL:'),
                              const SizedBox(height: 6),
                              CopyBox(text: _url(state.repo.logsPath)),
                              step('5',
                                  'Tap the arrow on that action. Set Method to POST. Under Headers add Key "Content-Type", '
                                  'Text "application/json". Set Request Body to File, and pick the Text from step 2.'),
                              step('6',
                                  'Add the action "If". Set it to: Contents of URL · contains · error. '
                                  'Inside "If", add "Show Notification" with "Didn\'t log. Open Care Log."'),
                              step('7',
                                  'Inside "Otherwise", add "Show Notification" with "${m.name} logged ✓".'),
                              for (final o in others) ...[
                                step('+',
                                    'Also inside "Otherwise", add another "Get Contents of URL" to notify ${o.name}. '
                                    'Paste this URL and set Method to POST:'),
                                const SizedBox(height: 6),
                                CopyBox(text: _ntfyUrl(o.ntfyTopic, m, me.name)),
                              ],
                              step('✓', 'Tap Done, then tap the shortcut once to test it. It should appear on the Today screen.'),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text('Put the buttons on the home screen', style: theme.textTheme.titleMedium),
                    step('1', 'Long-press an empty spot on the home screen, then tap Edit → Add Widget.'),
                    step('2', 'Search for Shortcuts, pick the medium or large size, and tap Add Widget.'),
                    step('3', 'Tap the new widget to choose which shortcuts it shows.'),
                    const SizedBox(height: 20),
                    Text('Daily reminder', style: theme.textTheme.titleMedium),
                    step('1', 'In Shortcuts, open the Automation tab and tap +. Choose Time of Day.'),
                    step('2', 'Set the time she takes the medicine, Repeat Daily, and choose "Run Immediately". Tap Next.'),
                    step('3', 'Choose New Blank Automation. Add "Choose from Menu" with the prompt "Did you take your medicine?" and two items: "Yes, log it" and "Not yet".'),
                    step('4', 'Under "Yes, log it", add "Run Shortcut" and pick the "Took …" shortcut. Leave "Not yet" empty.'),
                    const SizedBox(height: 24),
                    Text('Security', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      'The text from step 2 contains a private key that lets these shortcuts add doses, nothing else. '
                      'If it ever gets shared by mistake, make a new key here. Then update each shortcut\'s Text.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: () async {
                          final ok = await confirm(context,
                              title: 'Make a new key?',
                              message: 'Existing iPhone shortcuts stop working until you paste the new text into them.',
                              action: 'Make new key',
                              destructive: true);
                          if (!ok) return;
                          final k = await state.repo.rotateQuickKey();
                          setState(() => _key = k);
                        },
                        child: const Text('Make a new key'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
