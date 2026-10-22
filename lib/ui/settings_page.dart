import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../notify.dart';
import '../repo.dart';
import '../widget_bridge.dart';
import 'onboarding_page.dart';
import 'sheets.dart';
import 'shortcuts_page.dart';
import 'theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final me = state.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Header('Profile · ${state.profile?.name ?? ''}'),
              _ProfileSection(state: state),
              const _Header('You'),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(me.name.isEmpty ? 'Set your name' : me.name),
                subtitle: const Text('Shown next to what you log'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final name = await askText(context,
                      title: 'Your name', initial: me.name, hint: 'Shown next to what you log');
                  if (name != null && name.trim().isNotEmpty) {
                    await state.repo.saveMember(state.user.uid, {'name': name.trim()});
                  }
                },
              ),
              _AccountTile(state: state),
              const _Header('Appearance'),
              _AppearanceSection(state: state),
              const _Header('Notifications'),
              _NotificationSettings(state: state),
              if (widgetsSupported) ...[
                const _Header('Home-screen widget'),
                ListTile(
                  leading: const Icon(Icons.widgets_outlined),
                  title: const Text('Add the meds widget'),
                  subtitle: const Text(
                      'Shows today\'s medicines. Tap one to log it without opening the app. '
                      'You can also long-press your home screen → Widgets → Care Log.'),
                  isThreeLine: true,
                  onTap: () => requestPinWidget(),
                ),
                const _WidgetSizeSetting(),
              ],
              const _Header('iPhone'),
              ListTile(
                leading: const Icon(Icons.touch_app_outlined),
                title: const Text('One-tap logging with Shortcuts'),
                subtitle: const Text('Home-screen buttons and a daily reminder for iPhone'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AppScope(state: state, child: const ShortcutsPage()),
                )),
              ),
              const _Header('Medicines'),
              if (state.meds.isEmpty)
                const ListTile(title: Text('No medicines yet. Add them on the Today screen.')),
              for (final m in state.meds) _MedRow(state: state, med: m),
              const _Header('Symptoms'),
              for (final s in state.symptoms)
                ListTile(
                  title: Text(s.name),
                  subtitle: s.archived ? const Text('Not tracked') : null,
                  trailing: s.archived
                      ? TextButton(
                          onPressed: () => state.repo.setSymptomArchived(s.id, false),
                          child: const Text('Restore'),
                        )
                      : IconButton(
                          tooltip: 'Stop tracking',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => state.repo.setSymptomArchived(s.id, true),
                        ),
                ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirm(context,
                        title: 'Sign out?', message: 'You can sign back in any time.',
                        action: 'Sign out');
                    if (!ok) return;
                    if (widgetsSupported) await showWidgetMessage('Open Care Log and sign in.');
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('Care Log', style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(text.toUpperCase(),
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.8)),
    );
  }
}

class _MedRow extends StatelessWidget {
  const _MedRow({required this.state, required this.med});

  final AppState state;
  final Med med;

  Future<void> _deleteForever(BuildContext context) async {
    int? count;
    try {
      count = await state.repo.countMedLogs(med.id);
    } catch (_) {}
    if (!context.mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final doses = count == null
        ? 'every logged dose'
        : count == 1
            ? '1 logged dose'
            : '$count logged doses';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 36),
        title: Text('Permanently delete ${med.name}?'),
        content: Text(
          'This is permanent and can\'t be undone. All saved data for ${med.name} will be lost, '
          'including $doses, for everyone linked to this profile.\n\n'
          'To hide it but keep its history, use Remove instead.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final n = await state.repo.deleteMedPermanently(med.id);
      if (context.mounted) {
        toast(context, '${med.name} deleted, with $n logged ${n == 1 ? 'dose' : 'doses'}');
      }
    } catch (e) {
      if (context.mounted) toast(context, 'Couldn\'t delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = switch (med.status) {
      'paused' => 'Paused',
      'archived' => 'Removed',
      _ => 'Active',
    };
    return ListTile(
      leading: CircleAvatar(radius: 8, backgroundColor: med.colorValue),
      title: Text(med.label),
      subtitle: Text([status, if (med.scheduleLabel.isNotEmpty) med.scheduleLabel].join(' · ')),
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (med.isArchived)
            TextButton(
              onPressed: () => state.repo.updateMed(med.id, status: 'active'),
              child: const Text('Restore'),
            ),
          IconButton(
            tooltip: 'Delete forever',
            icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
            onPressed: () => _deleteForever(context),
          ),
        ],
      ),
      onTap: med.isArchived ? null : () => showMedActions(context, state, med),
    );
  }
}

class _NotificationSettings extends StatelessWidget {
  const _NotificationSettings({required this.state});

  final AppState state;

  Future<void> _save(Map<String, dynamic> fields) =>
      state.repo.saveMember(state.user.uid, fields);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = state.me;
    if (!me.hasNotifications) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Get a notification on this phone whenever someone else logs a medicine, a fever, or a severe symptom. '
                'Notifications come through ntfy, a free app.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _save({
                'ntfyTopic': 'carelog-${randomToken(20)}',
                'notifyMeds': true,
                'notifyFever': true,
                'notifySevere': true,
                if (state.myMember == null) 'name': me.name,
              }),
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Turn on notifications'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Finish setup in the ntfy app:', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              const Text('1. Install "ntfy" from the Play Store (or App Store).\n'
                  '2. In ntfy, tap + and paste this topic name, then Subscribe.\n'
                  '3. Tap "Send test" below to check it works.'),
              const SizedBox(height: 10),
              CopyBox(text: me.ntfyTopic),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await Notifier.send(me.ntfyTopic,
                        title: 'Care Log test', message: 'Notifications are working.', tags: 'tada');
                    if (context.mounted) {
                      toast(context, ok ? 'Test sent' : 'Couldn\'t reach ntfy. Check your connection.');
                    }
                  },
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send test'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final ok = await confirm(context,
                        title: 'Turn off notifications?',
                        message: 'This phone stops getting alerts. You can turn them on again later.',
                        action: 'Turn off');
                    if (ok) await _save({'ntfyTopic': ''});
                  },
                  child: const Text('Turn off'),
                ),
              ]),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Medicines'),
          subtitle: const Text('When someone else logs a dose'),
          value: me.notifyMeds,
          onChanged: (v) => _save({'notifyMeds': v}),
        ),
        SwitchListTile(
          title: const Text('Fever'),
          subtitle: const Text('Temperature of 100.4°F or higher'),
          value: me.notifyFever,
          onChanged: (v) => _save({'notifyFever': v}),
        ),
        SwitchListTile(
          title: const Text('Severe symptoms'),
          subtitle: const Text('Any symptom rated 7 or higher'),
          value: me.notifySevere,
          onChanged: (v) => _save({'notifySevere': v}),
        ),
      ],
    );
  }
}

/// Monospace text with a copy button.
class CopyBox extends StatelessWidget {
  const CopyBox({super.key, required this.text, this.label});

  final String text;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(label!,
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                SelectableText(
                  text,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) toast(context, 'Copied');
            },
          ),
        ],
      ),
    );
  }
}

class _WidgetSizeSetting extends StatefulWidget {
  const _WidgetSizeSetting();

  @override
  State<_WidgetSizeSetting> createState() => _WidgetSizeSettingState();
}

class _WidgetSizeSettingState extends State<_WidgetSizeSetting> {
  int? _size;

  @override
  void initState() {
    super.initState();
    getWidgetSize().then((v) {
      if (mounted) setState(() => _size = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Widget text size', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Bigger is easier to read; smaller fits more medicines. '
            'The A− and A+ buttons on the widget change this too.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Small')),
              ButtonSegment(value: 1, label: Text('Medium')),
              ButtonSegment(value: 2, label: Text('Large')),
              ButtonSegment(value: 3, label: Text('XL')),
            ],
            selected: {_size ?? 1},
            onSelectionChanged: (s) async {
              setState(() => _size = s.first);
              await setWidgetSize(s.first);
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ profile & sharing

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.state});

  final AppState state;

  Future<void> _invite(BuildContext context) async {
    String code;
    try {
      code = await Accounts.createInvite(profileId: state.profileId, uid: state.user.uid);
    } catch (e) {
      if (context.mounted) toast(context, 'Couldn\'t make a code: $e');
      return;
    }
    if (!context.mounted) return;
    final pretty = Accounts.formatCode(code);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SelectableText(
                pretty,
                style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'On the other phone, open Care Log and choose "Use a code" (no account needed), '
              'or sign in and choose "Join with a code". The code works for 7 days.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: pretty));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) toast(context, 'Code copied');
            },
            child: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = state.iAmOwner;
    final multiple = state.prefs.profiles.length > 1;
    return Column(
      children: [
        if (owner)
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Profile name'),
            subtitle: Text(state.profile?.name ?? ''),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final name = await askText(context,
                  title: 'Profile name', initial: state.profile?.name ?? '', hint: 'e.g. Dani');
              if (name != null && name.trim().isNotEmpty) await state.repo.renameProfile(name);
            },
          ),
        ListTile(
          leading: const Icon(Icons.person_add_alt_1_outlined),
          title: const Text('Invite someone or link a device'),
          subtitle: const Text('Makes a code that works for 7 days'),
          onTap: () => _invite(context),
        ),
        for (final m in state.members)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              child: Text(m.name.isEmpty ? '?' : m.name.characters.first.toUpperCase()),
            ),
            title: Text('${m.name.isEmpty ? 'Someone' : m.name}${m.uid == state.user.uid ? ' (you)' : ''}'),
            subtitle: Text(m.isOwner ? 'Owner' : 'Linked'),
            trailing: owner && m.uid != state.user.uid
                ? IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () async {
                      final ok = await confirm(context,
                          title: 'Remove ${m.name}?',
                          message: 'They lose access to this profile. You can invite them again later.',
                          action: 'Remove',
                          destructive: true);
                      if (ok) await state.repo.removeMember(m.uid);
                    },
                  )
                : null,
          ),
        ListTile(
          leading: const Icon(Icons.group_add_outlined),
          title: const Text('Add another profile'),
          subtitle: Text(multiple
              ? 'Switch profiles by tapping the name at the top of the main screen'
              : 'Track someone else, or join their profile with a code'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => OnboardingPage(user: state.user, canCancel: true),
          )),
        ),
        if (!owner)
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Leave this profile'),
            onTap: () async {
              final ok = await confirm(context,
                  title: 'Leave ${state.profile?.name ?? 'this profile'}?',
                  message: 'This account stops seeing it. Someone linked to it can invite you again.',
                  action: 'Leave',
                  destructive: true);
              if (!ok) return;
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              await Accounts.forgetProfile(state.prefs, state.profileId);
            },
          ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.state});

  final AppState state;

  Future<void> _addLogin(BuildContext context) async {
    final email = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add email & password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Then you can sign in on other devices, or after reinstalling, and keep access.'),
          const SizedBox(height: 12),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password (6+ characters)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await state.user.linkWithCredential(
        EmailAuthProvider.credential(email: email.text.trim(), password: password.text),
      );
      await state.user.reload();
      if (context.mounted) toast(context, 'Saved. You can now sign in with that email.');
    } on FirebaseAuthException catch (e) {
      if (context.mounted) toast(context, e.message ?? 'Couldn\'t save (${e.code}).');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser ?? state.user;
    if (user.isAnonymous) {
      return ListTile(
        leading: const Icon(Icons.key_outlined),
        title: const Text('Linked with a code'),
        subtitle: const Text(
            'No account yet. Add an email and password so you don\'t lose access if you reinstall.'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _addLogin(context),
      );
    }
    return ListTile(
      leading: const Icon(Icons.alternate_email),
      title: Text(user.email ?? 'Signed in'),
      subtitle: const Text('Tap to get a password reset email'),
      onTap: () async {
        final email = user.email;
        if (email == null) return;
        final ok = await confirm(context,
            title: 'Reset password?',
            message: 'We\'ll email a reset link to $email.',
            action: 'Send');
        if (!ok) return;
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (context.mounted) toast(context, 'Reset email sent');
      },
    );
  }
}

// ------------------------------------------------------------------ appearance

class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection({required this.state});

  final AppState state;

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  late HSVColor _custom = HSVColor.fromColor(themeController.value.seed);
  bool _showCustom = false;

  Future<void> _setSeed(Color c) async {
    themeController.value = ThemePrefs(c, themeController.value.mode);
    await Accounts.savePrefs(widget.state.user.uid, {'themeSeed': c.toARGB32()});
  }

  Future<void> _setMode(String mode) async {
    themeController.value = ThemePrefs(themeController.value.seed, parseThemeMode(mode));
    await Accounts.savePrefs(widget.state.user.uid, {'themeMode': mode});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = themeController.value;
    final modeKey = switch (current.mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    final seedValue = current.seed.toARGB32();
    final isPreset = themePresets.any((p) => p.$2 == seedValue);

    Widget swatch(Color c, String label, {bool selected = false, VoidCallback? onTap}) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? theme.colorScheme.onSurface : Colors.transparent,
                  width: 3,
                ),
              ),
              child: selected ? Icon(Icons.check, color: onColor(c)) : null,
            ),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.labelSmall, maxLines: 1),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'system', label: Text('Auto'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode)),
              ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode)),
            ],
            selected: {modeKey},
            onSelectionChanged: (s) => _setMode(s.first),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 4,
            runSpacing: 10,
            children: [
              for (final (name, value) in themePresets)
                swatch(Color(value), name,
                    selected: seedValue == value, onTap: () => _setSeed(Color(value))),
              swatch(
                isPreset ? _custom.toColor() : current.seed,
                'Custom',
                selected: !isPreset,
                onTap: () => setState(() => _showCustom = !_showCustom),
              ),
            ],
          ),
          if (_showCustom) ...[
            const SizedBox(height: 12),
            Text('Hue', style: theme.textTheme.labelLarge),
            Slider(
              value: _custom.hue,
              max: 360,
              activeColor: _custom.toColor(),
              onChanged: (v) => setState(() => _custom = _custom.withHue(v)),
            ),
            Text('Vividness', style: theme.textTheme.labelLarge),
            Slider(
              value: _custom.saturation,
              min: 0.1,
              max: 1,
              activeColor: _custom.toColor(),
              onChanged: (v) => setState(() => _custom = _custom.withSaturation(v)),
            ),
            Text('Brightness', style: theme.textTheme.labelLarge),
            Slider(
              value: _custom.value,
              min: 0.25,
              max: 1,
              activeColor: _custom.toColor(),
              onChanged: (v) => setState(() => _custom = _custom.withValue(v)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _setSeed(_custom.toColor()),
                icon: const Icon(Icons.palette_outlined),
                label: const Text('Use this color'),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
