import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'models.dart';
import 'notify.dart';

/// Reads and writes for one profile (one person being tracked).
///
/// Everything lives under `profiles/{profileId}/…`, so several families can
/// share one Firebase project without seeing each other's data.
/// Used both by the app UI and by the Android widget's background callback,
/// so it holds no UI state.
class Repo {
  Repo(this.profileId, [FirebaseFirestore? db]) : db = db ?? FirebaseFirestore.instance;

  final String profileId;
  final FirebaseFirestore db;

  DocumentReference<Map<String, dynamic>> get profile =>
      db.collection('profiles').doc(profileId);
  CollectionReference<Map<String, dynamic>> get meds => profile.collection('meds');
  CollectionReference<Map<String, dynamic>> get symptoms => profile.collection('symptomTypes');
  CollectionReference<Map<String, dynamic>> get logs => profile.collection('logs');
  CollectionReference<Map<String, dynamic>> get members => profile.collection('members');
  DocumentReference<Map<String, dynamic>> get quickLogConfig =>
      profile.collection('config').doc('quicklog');

  /// Firestore path of this profile's log collection (for iPhone Shortcuts).
  String get logsPath => 'profiles/$profileId/logs';

  // ---------------------------------------------------------------- streams

  Stream<ProfileInfo> watchProfile() => profile.snapshots().map(ProfileInfo.fromDoc);

  Future<void> renameProfile(String name) => profile.update({'name': name.trim()});

  Stream<List<Med>> watchMeds() => meds
      .orderBy('sort')
      .snapshots()
      .map((s) => s.docs.map(Med.fromDoc).toList());

  Stream<List<SymptomType>> watchSymptoms() => symptoms
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map(SymptomType.fromDoc).toList());

  Stream<List<Member>> watchMembers() =>
      members.snapshots().map((s) => s.docs.map(Member.fromDoc).toList());

  /// Logs with `start <= at < end`, newest first.
  Stream<List<LogEntry>> watchLogs(DateTime start, DateTime end) => logs
      .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('at', isLessThan: Timestamp.fromDate(end))
      .orderBy('at', descending: true)
      .snapshots()
      .map((s) => s.docs.map(LogEntry.fromDoc).toList());

  // ---------------------------------------------------------------- one-shot reads

  Future<List<Med>> fetchMeds() async {
    final s = await meds.orderBy('sort').get();
    return s.docs.map(Med.fromDoc).toList();
  }

  Future<List<Member>> fetchMembers() async {
    final s = await members.get();
    return s.docs.map(Member.fromDoc).toList();
  }

  Future<List<LogEntry>> fetchLogsSince(DateTime start) async {
    final s = await logs
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .orderBy('at', descending: true)
        .get();
    return s.docs.map(LogEntry.fromDoc).toList();
  }

  // ---------------------------------------------------------------- medicines

  Future<void> addMed({required String name, required String dose, required int color}) async {
    final existing = await meds.get();
    final maxSort = existing.docs
        .map((d) => (d.data()['sort'] as num?)?.toInt() ?? 0)
        .fold<int>(0, max);
    await meds.add({
      'name': name.trim(),
      'dose': dose.trim(),
      'color': color,
      'status': 'active',
      'sort': maxSort + 1,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMed(String id, {String? name, String? dose, int? color, String? status}) {
    return meds.doc(id).update({
      if (name != null) 'name': name.trim(),
      if (dose != null) 'dose': dose.trim(),
      'color': ?color,
      'status': ?status,
    });
  }

  // ---------------------------------------------------------------- symptoms

  Future<void> addSymptom(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final existing = await symptoms.get();
    for (final d in existing.docs) {
      if (((d.data()['name'] as String?) ?? '').toLowerCase() == clean.toLowerCase()) {
        await d.reference.update({'archived': false});
        return;
      }
    }
    await symptoms.add({'name': clean, 'archived': false, 'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> setSymptomArchived(String id, bool archived) =>
      symptoms.doc(id).update({'archived': archived});

  // ---------------------------------------------------------------- logging

  Future<LogEntry> logMed(Med med, {required Member me, String src = 'app', DateTime? at}) {
    return _addLog({
      'kind': 'med',
      'medId': med.id,
      'medName': med.name,
      'dose': med.dose,
    }, me: me, src: src, at: at);
  }

  Future<LogEntry> logVitals({
    required Member me,
    int? sys,
    int? dia,
    int? hr,
    double? tempF,
    String note = '',
    DateTime? at,
  }) {
    return _addLog({
      'kind': 'vitals',
      'sys': ?sys,
      'dia': ?dia,
      'hr': ?hr,
      'tempF': ?tempF,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    }, me: me, at: at);
  }

  Future<LogEntry> logSymptom({
    required Member me,
    required String symptomName,
    required int severity,
    String note = '',
    DateTime? at,
  }) {
    return _addLog({
      'kind': 'symptom',
      'symptomName': symptomName,
      'severity': severity,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    }, me: me, at: at);
  }

  Future<LogEntry> _addLog(
    Map<String, dynamic> fields, {
    required Member me,
    String src = 'app',
    DateTime? at,
  }) async {
    final when = at ?? DateTime.now();
    final data = {
      ...fields,
      'at': Timestamp.fromDate(when),
      'byName': me.name,
      'byUid': me.uid,
      'src': src,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final ref = logs.doc();
    // Don't wait for the server: Firestore queues the write offline and
    // the snapshot listeners update immediately.
    final write = ref.set(data).catchError((Object _) {});
    final entry = LogEntry(
      id: ref.id,
      kind: switch (fields['kind']) {
        'vitals' => LogKind.vitals,
        'symptom' => LogKind.symptom,
        _ => LogKind.med,
      },
      at: when,
      byName: me.name,
      byUid: me.uid,
      src: src,
      medId: (fields['medId'] as String?) ?? '',
      medName: (fields['medName'] as String?) ?? '',
      dose: (fields['dose'] as String?) ?? '',
      sys: fields['sys'] as int?,
      dia: fields['dia'] as int?,
      hr: fields['hr'] as int?,
      tempF: fields['tempF'] as double?,
      symptomName: (fields['symptomName'] as String?) ?? '',
      severity: fields['severity'] as int?,
      note: (fields['note'] as String?) ?? '',
    );
    // Tell the other people. In the app this is fire-and-forget.
    final notify = _notifyOthers(entry, me);
    if (src == 'widget') {
      // In the widget's background isolate, make sure the write and the
      // notification finish before the callback returns.
      await write.timeout(const Duration(seconds: 20), onTimeout: () {});
      await notify.timeout(const Duration(seconds: 15), onTimeout: () {});
    }
    return entry;
  }

  Future<void> _notifyOthers(LogEntry entry, Member me) async {
    try {
      final everyone = await fetchMembers();
      await Notifier.sendForLog(entry, everyone.where((m) => m.uid != me.uid).toList());
    } catch (_) {
      // Notifications are best-effort.
    }
  }

  Future<void> deleteLog(String id) => logs.doc(id).delete();

  Future<void> restoreLog(LogEntry e) {
    return logs.doc(e.id).set({
      'kind': e.kind.name,
      'at': Timestamp.fromDate(e.at),
      'byName': e.byName,
      'byUid': e.byUid,
      'src': e.src,
      if (e.kind == LogKind.med) ...{'medId': e.medId, 'medName': e.medName, 'dose': e.dose},
      'sys': ?e.sys,
      'dia': ?e.dia,
      'hr': ?e.hr,
      'tempF': ?e.tempF,
      if (e.kind == LogKind.symptom) ...{'symptomName': e.symptomName, 'severity': e.severity},
      if (e.note.isNotEmpty) 'note': e.note,
    });
  }

  // ---------------------------------------------------------------- members

  Future<Member?> fetchMember(String uid) async {
    final d = await members.doc(uid).get();
    return d.exists ? Member.fromDoc(d) : null;
  }

  Future<void> saveMember(String uid, Map<String, dynamic> fields) =>
      members.doc(uid).set(fields, SetOptions(merge: true));

  /// Unlinks someone from this profile (owner only).
  Future<void> removeMember(String uid) => members.doc(uid).delete();

  // ---------------------------------------------------------------- iPhone shortcuts

  Future<String> getOrCreateQuickKey() async {
    final d = await quickLogConfig.get();
    final existing = d.data()?['key'] as String?;
    if (existing != null && existing.length >= 20) return existing;
    final key = randomToken(32);
    await quickLogConfig.set({'key': key});
    return key;
  }

  Future<String> rotateQuickKey() async {
    final key = randomToken(32);
    await quickLogConfig.set({'key': key});
    return key;
  }
}

class JoinError implements Exception {
  JoinError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Account-level operations: profiles, invite codes and personal settings.
class Accounts {
  Accounts._();

  static FirebaseFirestore get db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      db.collection('users').doc(uid);

  static Stream<UserPrefs> watchUser(String uid) =>
      userDoc(uid).snapshots().map(UserPrefs.fromDoc);

  static Future<UserPrefs> fetchUser(String uid) async =>
      UserPrefs.fromDoc(await userDoc(uid).get());

  static Future<void> savePrefs(String uid, Map<String, dynamic> fields) =>
      userDoc(uid).set(fields, SetOptions(merge: true));

  /// Creates a profile owned by [uid] and makes it the active one.
  static Future<String> createProfile({
    required String uid,
    required String profileName,
    required String myName,
    String email = '',
  }) async {
    final ref = db.collection('profiles').doc();
    final batch = db.batch();
    batch.set(ref, {
      'name': profileName.trim(),
      'ownerUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('members').doc(uid), {
      'name': myName.trim(),
      'role': 'owner',
      'email': email,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await savePrefs(uid, {
      'profiles': FieldValue.arrayUnion([ref.id]),
      'activeProfile': ref.id,
    });
    return ref.id;
  }

  static String normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String formatCode(String code) =>
      code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

  /// Links [uid] to the profile an invite code points at.
  static Future<String> joinWithCode({
    required String uid,
    required String code,
    required String myName,
    String email = '',
  }) async {
    final c = normalizeCode(code);
    if (c.length < 6) throw JoinError('Enter the full code, like ABCD-1234.');
    final DocumentSnapshot<Map<String, dynamic>> inv;
    try {
      inv = await db.collection('invites').doc(c).get();
    } on FirebaseException catch (e) {
      throw JoinError('Couldn\'t check the code (${e.code}). Try again.');
    }
    if (!inv.exists) throw JoinError('That code wasn\'t found. Check it and try again.');
    final d = inv.data()!;
    final exp = d['expiresAt'];
    if (exp is Timestamp && exp.toDate().isBefore(DateTime.now())) {
      throw JoinError('That code has expired. Ask for a new one.');
    }
    final pid = d['profileId'] as String;
    await db.collection('profiles').doc(pid).collection('members').doc(uid).set({
      'name': myName.trim(),
      'role': 'member',
      'invite': c,
      'email': email,
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await savePrefs(uid, {
      'profiles': FieldValue.arrayUnion([pid]),
      'activeProfile': pid,
    });
    return pid;
  }

  /// Makes a one-week invite code for [profileId].
  static Future<String> createInvite({required String profileId, required String uid}) async {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final code = List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
    await db.collection('invites').doc(code).set({
      'profileId': profileId,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
    });
    return code;
  }

  static Future<List<ProfileInfo>> fetchProfiles(List<String> ids) async {
    final out = <ProfileInfo>[];
    for (final id in ids) {
      try {
        final d = await db.collection('profiles').doc(id).get();
        if (d.exists) out.add(ProfileInfo.fromDoc(d));
      } catch (_) {
        // No longer a member of that profile.
      }
    }
    return out;
  }

  /// Removes a profile from this account's list (and leaves it, if allowed).
  static Future<void> forgetProfile(UserPrefs prefs, String profileId, {bool leave = true}) async {
    if (leave) {
      try {
        await db.collection('profiles').doc(profileId).collection('members').doc(prefs.uid).delete();
      } catch (_) {}
    }
    final remaining = prefs.profiles.where((p) => p != profileId).toList();
    await savePrefs(prefs.uid, {
      'profiles': FieldValue.arrayRemove([profileId]),
      'activeProfile': remaining.isEmpty ? '' : remaining.first,
    });
  }
}

String randomToken(int length) {
  const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}
