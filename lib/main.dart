import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config.dart';
import 'models.dart';
import 'repo.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/onboarding_page.dart';
import 'ui/theme.dart';
import 'widget_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  if (firebaseConfigured) {
    try {
      await Firebase.initializeApp(options: firebaseOptions);
      await initWidgetBridge();
    } catch (e) {
      startupError = e;
    }
  }
  runApp(CareLogApp(startupError: startupError));
}

class CareLogApp extends StatelessWidget {
  const CareLogApp({super.key, this.startupError});

  final Object? startupError;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemePrefs>(
      valueListenable: themeController,
      builder: (context, t, _) => MaterialApp(
        title: 'Care Log',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, t.seed),
        darkTheme: buildTheme(Brightness.dark, t.seed),
        themeMode: t.mode,
        home: !firebaseConfigured
            ? const _Problem(
                'This build has no Firebase settings yet. Add config/firebase.json and rebuild.')
            : startupError != null
                ? _Problem('Couldn\'t start: $startupError')
                : const _AuthGate(),
      ),
    );
  }
}

/// Signed out → login. Signed in → the account's settings.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _auth = FirebaseAuth.instance.authStateChanges();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: linkingDevice,
      builder: (context, linking, _) => StreamBuilder<User?>(
        stream: _auth,
        builder: (context, snap) {
          if (linking) return const LoginPage();
          if (snap.connectionState == ConnectionState.waiting) return const _Loading();
          final user = snap.data;
          if (user == null) return const LoginPage();
          return _UserGate(key: ValueKey(user.uid), user: user);
        },
      ),
    );
  }
}

/// Loads the account's settings, then opens its active profile (or asks the
/// person to create or join one).
class _UserGate extends StatefulWidget {
  const _UserGate({super.key, required this.user});

  final User user;

  @override
  State<_UserGate> createState() => _UserGateState();
}

class _UserGateState extends State<_UserGate> {
  late final Stream<UserPrefs> _prefs = Accounts.watchUser(widget.user.uid);
  AppState? _state;

  @override
  void dispose() {
    _state?.dispose();
    super.dispose();
  }

  /// Disposes old state after the frame, once nothing is listening to it.
  void _retire(AppState? old) {
    if (old == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserPrefs>(
      stream: _prefs,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Problem('Couldn\'t load your account: ${snap.error}', showSignOut: true);
        }
        final prefs = snap.data;
        if (prefs == null) return const _Loading();
        WidgetsBinding.instance.addPostFrameCallback((_) => applyUserTheme(prefs));

        var active = prefs.activeProfile;
        if (!prefs.profiles.contains(active)) {
          active = prefs.profiles.isEmpty ? '' : prefs.profiles.first;
          if (active.isNotEmpty) {
            Accounts.savePrefs(prefs.uid, {'activeProfile': active});
            return const _Loading();
          }
        }
        if (active.isEmpty) {
          _retire(_state);
          _state = null;
          return OnboardingPage(user: widget.user);
        }
        if (_state == null || _state!.profileId != active) {
          _retire(_state);
          _state = AppState(widget.user, prefs);
        } else {
          _state!.prefs = prefs;
        }
        return AppScope(
          key: ValueKey(active),
          state: _state!,
          child: const HomePage(),
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Problem extends StatelessWidget {
  const _Problem(this.message, {this.showSignOut = false});

  final String message;
  final bool showSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, textAlign: TextAlign.center),
                if (showSignOut) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
