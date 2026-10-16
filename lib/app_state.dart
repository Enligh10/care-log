import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'models.dart';
import 'repo.dart';
import 'widget_bridge.dart';

/// Live, shared data for the signed-in person: medicines, symptom types,
/// people, and today's log. Everything updates in real time from Firestore.
class AppState extends ChangeNotifier {
  AppState(this.user, this.prefs) : repo = Repo(prefs.activeProfile) {
    _subscribe();
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!sameDay(_day, DateTime.now())) {
        _subscribeToday();
        notifyListeners();
      }
    });
  }

  final User user;

  /// Account settings at the time this profile was opened.
  UserPrefs prefs;
  final Repo repo;

  String get profileId => repo.profileId;
  ProfileInfo? profile;

  List<Med> meds = const [];
  List<SymptomType> symptoms = const [];
  List<Member> members = const [];
  List<LogEntry> today = const [];

  bool medsLoaded = false;
  bool membersLoaded = false;
  String? error;

  DateTime _day = dayOf(DateTime.now());
  final _subs = <StreamSubscription<dynamic>>[];
  StreamSubscription<List<LogEntry>>? _todaySub;
  Timer? _dayTimer;
  Timer? _widgetDebounce;

  List<Med> get activeMeds => meds.where((m) => m.isActive).toList();
  List<Med> get pausedMeds => meds.where((m) => m.isPaused).toList();
  List<Med> get archivedMeds => meds.where((m) => m.isArchived).toList();
  List<SymptomType> get activeSymptoms => symptoms.where((s) => !s.archived).toList();

  Member? get myMember {
    for (final m in members) {
      if (m.uid == user.uid) return m;
    }
    return null;
  }

  /// The signed-in person, with a sensible name even before they set one.
  Member get me =>
      myMember ??
      Member(
        uid: user.uid,
        name: user.displayName ?? user.email?.split('@').first ?? 'Me',
      );

  bool get needsName => membersLoaded && (myMember == null || myMember!.name.trim().isEmpty);

  List<LogEntry> dosesToday(Med med) =>
      today.where((l) => l.kind == LogKind.med && l.medId == med.id).toList();

  bool get iAmOwner => profile?.ownerUid == user.uid;

  void _subscribe() {
    _subs.add(repo.watchProfile().listen((v) {
      profile = v;
      _changed();
    }, onError: _onError));
    _subs.add(repo.watchMeds().listen((v) {
      meds = v;
      medsLoaded = true;
      _changed(widget: true);
    }, onError: _onError));
    _subs.add(repo.watchSymptoms().listen((v) {
      symptoms = v;
      _changed();
    }, onError: _onError));
    _subs.add(repo.watchMembers().listen((v) {
      members = v;
      membersLoaded = true;
      _changed();
    }, onError: _onError));
    _subscribeToday();
  }

  void _subscribeToday() {
    _todaySub?.cancel();
    _day = dayOf(DateTime.now());
    final end = _day.add(const Duration(days: 1));
    _todaySub = repo.watchLogs(_day, end).listen((v) {
      today = v;
      _changed(widget: true);
    }, onError: _onError);
  }

  void _onError(Object e) {
    error = e.toString();
    notifyListeners();
  }

  void _changed({bool widget = false}) {
    error = null;
    notifyListeners();
    if (widget && widgetsSupported) {
      _widgetDebounce?.cancel();
      _widgetDebounce = Timer(const Duration(milliseconds: 600), () {
        if (medsLoaded) syncWidget(meds, today, profileId: profileId, title: profile?.name);
      });
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _todaySub?.cancel();
    _dayTimer?.cancel();
    _widgetDebounce?.cancel();
    super.dispose();
  }
}

/// Makes [AppState] available to every screen.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
