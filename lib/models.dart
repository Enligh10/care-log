import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Colors offered when adding a medicine. Stored as ARGB ints.
const medPalette = <int>[
  0xFF3D7BD9, // blue
  0xFFE0703A, // orange
  0xFF2E9E6A, // green
  0xFF9B59D0, // purple
  0xFFD94C7A, // pink
  0xFF1FA2B3, // teal
  0xFFC9A227, // mustard
  0xFF6B7A8F, // slate
];

class Med {
  final String id;
  final String name;
  final String dose;
  final int color;

  /// 'active', 'paused' or 'archived'. Archived medicines keep their history.
  final String status;
  final int sort;

  /// Planned doses per day. 0 means "as needed" (no daily target).
  final int dosesPerDay;

  const Med({
    required this.id,
    required this.name,
    required this.dose,
    required this.color,
    required this.status,
    required this.sort,
    this.dosesPerDay = 1,
  });

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isArchived => status == 'archived';
  bool get asNeeded => dosesPerDay == 0;
  Color get colorValue => Color(color);

  factory Med.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Med(
      id: doc.id,
      name: (d['name'] as String?) ?? 'Medicine',
      dose: (d['dose'] as String?) ?? '',
      color: (d['color'] as num?)?.toInt() ?? medPalette.first,
      status: (d['status'] as String?) ?? 'active',
      sort: (d['sort'] as num?)?.toInt() ?? 0,
      dosesPerDay: ((d['dosesPerDay'] as num?)?.toInt() ?? 1).clamp(0, 12),
    );
  }

  String get label => dose.isEmpty ? name : '$name · $dose';

  /// "3× a day", "As needed", or "" for once a day.
  String get scheduleLabel => switch (dosesPerDay) {
        0 => 'As needed',
        1 => '',
        _ => '$dosesPerDay× a day',
      };

  /// How a day's dose count compares with the plan.
  DoseProgress progress(int taken) {
    if (taken <= 0) return DoseProgress.none;
    if (asNeeded) return DoseProgress.complete;
    if (taken < dosesPerDay) return DoseProgress.partial;
    if (taken > dosesPerDay) return DoseProgress.extra;
    return DoseProgress.complete;
  }

  /// Short status for a day, e.g. "2 of 3", "✓", "×2".
  String countLabel(int taken) {
    if (asNeeded) return taken == 0 ? '' : '×$taken';
    if (dosesPerDay == 1) return taken == 0 ? '' : (taken == 1 ? '✓' : '×$taken');
    return '$taken/$dosesPerDay';
  }
}

enum DoseProgress { none, partial, complete, extra }

class SymptomType {
  final String id;
  final String name;
  final bool archived;

  const SymptomType({required this.id, required this.name, this.archived = false});

  factory SymptomType.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SymptomType(
      id: doc.id,
      name: (d['name'] as String?) ?? 'Symptom',
      archived: (d['archived'] as bool?) ?? false,
    );
  }
}

/// Someone linked to a profile (a signed-in account or a device linked with
/// an invite code).
class Member {
  final String uid;
  final String name;
  final String role;
  final String ntfyTopic;
  final bool notifyMeds;
  final bool notifyFever;
  final bool notifySevere;

  const Member({
    required this.uid,
    required this.name,
    this.role = 'member',
    this.ntfyTopic = '',
    this.notifyMeds = true,
    this.notifyFever = true,
    this.notifySevere = true,
  });

  bool get hasNotifications => ntfyTopic.isNotEmpty;
  bool get isOwner => role == 'owner';

  factory Member.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Member(
      uid: doc.id,
      name: (d['name'] as String?) ?? '',
      role: (d['role'] as String?) ?? 'member',
      ntfyTopic: (d['ntfyTopic'] as String?) ?? '',
      notifyMeds: (d['notifyMeds'] as bool?) ?? true,
      notifyFever: (d['notifyFever'] as bool?) ?? true,
      notifySevere: (d['notifySevere'] as bool?) ?? true,
    );
  }
}

/// A person whose meds and symptoms are tracked (e.g. "Dani").
class ProfileInfo {
  final String id;
  final String name;
  final String ownerUid;

  const ProfileInfo({required this.id, required this.name, required this.ownerUid});

  factory ProfileInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ProfileInfo(
      id: doc.id,
      name: (d['name'] as String?) ?? 'Profile',
      ownerUid: (d['ownerUid'] as String?) ?? '',
    );
  }
}

/// Per-account settings, shared by all of that account's devices.
class UserPrefs {
  final String uid;
  final List<String> profiles;
  final String activeProfile;
  final int? themeSeed;
  final String themeMode;

  const UserPrefs({
    required this.uid,
    this.profiles = const [],
    this.activeProfile = '',
    this.themeSeed,
    this.themeMode = 'system',
  });

  factory UserPrefs.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return UserPrefs(
      uid: doc.id,
      profiles: ((d['profiles'] as List?) ?? const []).whereType<String>().toList(),
      activeProfile: (d['activeProfile'] as String?) ?? '',
      themeSeed: (d['themeSeed'] as num?)?.toInt(),
      themeMode: (d['themeMode'] as String?) ?? 'system',
    );
  }
}

enum LogKind { med, vitals, symptom }

class LogEntry {
  final String id;
  final LogKind kind;
  final DateTime at;
  final String byName;
  final String byUid;
  final String src;

  // Medicine
  final String medId;
  final String medName;
  final String dose;

  // Vitals
  final int? sys;
  final int? dia;
  final int? hr;
  final double? tempF;

  // Symptom
  final String symptomName;
  final int? severity;
  final String note;

  const LogEntry({
    required this.id,
    required this.kind,
    required this.at,
    required this.byName,
    this.byUid = '',
    this.src = 'app',
    this.medId = '',
    this.medName = '',
    this.dose = '',
    this.sys,
    this.dia,
    this.hr,
    this.tempF,
    this.symptomName = '',
    this.severity,
    this.note = '',
  });

  static LogKind _kind(String? k) => switch (k) {
        'vitals' => LogKind.vitals,
        'symptom' => LogKind.symptom,
        _ => LogKind.med,
      };

  static int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
  static double? _double(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  factory LogEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final at = d['at'];
    return LogEntry(
      id: doc.id,
      kind: _kind(d['kind'] as String?),
      at: at is Timestamp ? at.toDate() : DateTime.now(),
      byName: (d['byName'] as String?) ?? '',
      byUid: (d['byUid'] as String?) ?? '',
      src: (d['src'] as String?) ?? 'app',
      medId: (d['medId'] as String?) ?? '',
      medName: (d['medName'] as String?) ?? '',
      dose: (d['dose'] as String?) ?? '',
      sys: _int(d['sys']),
      dia: _int(d['dia']),
      hr: _int(d['hr']),
      tempF: _double(d['tempF']),
      symptomName: (d['symptomName'] as String?) ?? '',
      severity: _int(d['severity']),
      note: (d['note'] as String?) ?? '',
    );
  }

  bool get hasBp => sys != null && dia != null;
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
