import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../repo.dart';
import 'journal_page.dart';
import 'onboarding_page.dart';
import 'settings_page.dart';
import 'sheets.dart';
import 'today_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  bool _askedName = false;

  void _maybeAskName(AppState state) {
    if (_askedName || !state.needsName) return;
    _askedName = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final name = await askText(
        context,
        title: 'What should we call you?',
        hint: 'Shown next to what you log',
        initial: state.user.email?.split('@').first ?? '',
        action: 'Save',
        barrierDismissible: false,
      );
      if (name != null && name.trim().isNotEmpty) {
        await state.repo.saveMember(state.user.uid, {'name': name.trim()});
      } else {
        _askedName = false;
      }
    });
  }

  Future<void> _switchProfile(AppState state) async {
    final profiles = await Accounts.fetchProfiles(state.prefs.profiles);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Profiles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (final ProfileInfo p in profiles)
              ListTile(
                leading: Icon(p.id == state.profileId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(p.name),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (p.id != state.profileId) {
                    await Accounts.savePrefs(state.user.uid, {'activeProfile': p.id});
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add a profile'),
              subtitle: const Text('Start tracking someone new, or join with a code'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => OnboardingPage(user: state.user, canCancel: true),
                ));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _maybeAskName(state);
    final titles = ['Today', 'Journal'];
    final profileName = state.profile?.name ?? '';
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _switchProfile(state),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titles[_tab]),
                if (profileName.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(profileName,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                    Icon(Icons.arrow_drop_down,
                        size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ]),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AppScope(state: state, child: const SettingsPage())),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.error != null) _ErrorBanner(state: state),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [TodayPage(), JournalPage()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Journal',
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = state.error!;
    final denied = error.contains('permission-denied');
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(denied ? Icons.lock_outline : Icons.cloud_off, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                denied
                    ? 'You don\'t have access to this profile anymore.'
                    : 'Sync problem: $error',
                style: TextStyle(color: scheme.onErrorContainer),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (denied)
              TextButton(
                onPressed: () =>
                    Accounts.forgetProfile(state.prefs, state.profileId, leave: false),
                child: const Text('Remove'),
              ),
          ],
        ),
      ),
    );
  }
}
