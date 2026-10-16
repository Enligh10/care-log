import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../repo.dart';

enum _Mode { signIn, create, code }

/// True while a code-based link is being set up, so the app keeps showing
/// this page (and any error) instead of jumping ahead on sign-in.
final linkingDevice = ValueNotifier<bool>(false);

/// Sign in, create an account, or link this device with an invite code.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  _Mode _mode = _Mode.signIn;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _password, _code, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  String _authMessage(FirebaseAuthException e) => switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Email or password is incorrect.',
        'invalid-email' => 'That email address doesn\'t look right.',
        'email-already-in-use' => 'There\'s already an account with that email. Sign in instead.',
        'weak-password' => 'Use a password with at least 6 characters.',
        'operation-not-allowed' =>
          'This sign-in method is turned off in Firebase (Authentication → Sign-in method).',
        'network-request-failed' => 'No connection. Try again.',
        'too-many-requests' => 'Too many tries. Wait a minute and try again.',
        _ => e.message ?? 'Sign-in failed (${e.code}).',
      };

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = FirebaseAuth.instance;
    try {
      switch (_mode) {
        case _Mode.signIn:
          await auth.signInWithEmailAndPassword(
              email: _email.text.trim(), password: _password.text);
        case _Mode.create:
          await auth.createUserWithEmailAndPassword(
              email: _email.text.trim(), password: _password.text);
        case _Mode.code:
          final code = Accounts.normalizeCode(_code.text);
          final name = _name.text.trim();
          if (code.length < 6) throw JoinError('Enter the full code, like ABCD-1234.');
          if (name.isEmpty) throw JoinError('Enter your name.');
          linkingDevice.value = true;
          try {
            final cred = await auth.signInAnonymously();
            try {
              await Accounts.joinWithCode(uid: cred.user!.uid, code: code, myName: name);
            } catch (e) {
              // Don't leave a half-set-up anonymous account behind.
              try {
                await cred.user?.delete();
              } catch (_) {}
              await auth.signOut();
              rethrow;
            }
          } finally {
            linkingDevice.value = false;
          }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _authMessage(e));
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
    final isCode = _mode == _Mode.code;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.favorite_rounded, size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Care Log',
                        textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text('Meds, vitals and symptoms, shared.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 28),
                    SegmentedButton<_Mode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: _Mode.signIn, label: Text('Sign in')),
                        ButtonSegment(value: _Mode.create, label: Text('New account')),
                        ButtonSegment(value: _Mode.code, label: Text('Use a code')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setState(() {
                        _mode = s.first;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 20),
                    if (isCode) ...[
                      Text(
                        'Link this device to someone\'s profile with the invite code from their Care Log '
                        '(Settings → Invite). No account needed.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'Invite code', hintText: 'ABCD-1234'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(labelText: 'Your name'),
                      ),
                    ] else ...[
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        autofillHints: [
                          _mode == _Mode.create ? AutofillHints.newPassword : AutofillHints.password,
                        ],
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(labelText: 'Password'),
                      ),
                    ],
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
                            : Text(switch (_mode) {
                                _Mode.signIn => 'Sign in',
                                _Mode.create => 'Create account',
                                _Mode.code => 'Link this device',
                              }),
                      ),
                    ),
                    if (_mode == _Mode.signIn) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final email = _email.text.trim();
                                if (email.isEmpty) {
                                  setState(() => _error = 'Enter your email first.');
                                  return;
                                }
                                try {
                                  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                  setState(() => _error = 'Password reset email sent.');
                                } on FirebaseAuthException catch (e) {
                                  setState(() => _error = _authMessage(e));
                                }
                              },
                        child: const Text('Forgot password?'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
