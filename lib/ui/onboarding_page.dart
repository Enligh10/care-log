import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../repo.dart';

/// Shown when an account isn't linked to any profile yet: start a new
/// profile, or join an existing one with an invite code.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.user, this.canCancel = false});

  final User user;
  final bool canCancel;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _join = false;
  final _profileName = TextEditingController();
  final _myName = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _myName.text = widget.user.displayName ?? '';
  }

  @override
  void dispose() {
    for (final c in [_profileName, _myName, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final myName = _myName.text.trim();
    setState(() {
      _error = null;
    });
    if (myName.isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    if (!_join && _profileName.text.trim().isEmpty) {
      setState(() => _error = 'Enter the name of the person you\'re tracking.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_join) {
        await Accounts.joinWithCode(
          uid: widget.user.uid,
          code: _code.text,
          myName: myName,
          email: widget.user.email ?? '',
        );
      } else {
        await Accounts.createProfile(
          uid: widget.user.uid,
          profileName: _profileName.text,
          myName: myName,
          email: widget.user.email ?? '',
        );
      }
      if (widget.canCancel && mounted) Navigator.of(context).pop();
    } on JoinError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.canCancel ? AppBar(title: const Text('Add a profile')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.canCancel) ...[
                    Text('Welcome', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Care Log keeps one profile per person being tracked. '
                      'Everyone linked to a profile sees and logs the same meds and symptoms.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                  ],
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Start a profile')),
                      ButtonSegment(value: true, label: Text('Join with a code')),
                    ],
                    selected: {_join},
                    onSelectionChanged: (s) => setState(() {
                      _join = s.first;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  if (_join)
                    TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Invite code',
                        hintText: 'ABCD-1234',
                        helperText: 'From Settings → Invite on a phone already linked',
                      ),
                    )
                  else
                    TextField(
                      controller: _profileName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Who are you tracking?',
                        hintText: 'e.g. Dani',
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _myName,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      helperText: 'Shown next to what you log',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_join ? 'Join' : 'Create profile'),
                    ),
                  ),
                  if (!widget.canCancel) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: Text('Sign out (${widget.user.email ?? 'this device'})'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
