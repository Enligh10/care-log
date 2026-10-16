import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase settings are passed in at build time from config/firebase.json
/// (see `--dart-define-from-file` in the build workflow).
const _apiKey = String.fromEnvironment('FB_API_KEY');
const _projectId = String.fromEnvironment('FB_PROJECT_ID');
const _senderId = String.fromEnvironment('FB_SENDER_ID');
const _authDomain = String.fromEnvironment('FB_AUTH_DOMAIN');
const _storageBucket = String.fromEnvironment('FB_STORAGE_BUCKET');
const _webAppId = String.fromEnvironment('FB_WEB_APP_ID');
const _androidAppId = String.fromEnvironment('FB_ANDROID_APP_ID');

bool get firebaseConfigured => _apiKey.isNotEmpty && _projectId.isNotEmpty;

String get firebaseProjectId => _projectId;
String get firebaseApiKey => _apiKey;

FirebaseOptions get firebaseOptions => FirebaseOptions(
      apiKey: _apiKey,
      appId: kIsWeb || _androidAppId.isEmpty ? _webAppId : _androidAppId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      authDomain: _authDomain.isEmpty ? null : _authDomain,
      storageBucket: _storageBucket.isEmpty ? null : _storageBucket,
    );

/// Temperature (°F) at or above which a reading is flagged as a fever.
const feverThresholdF = 100.4;

/// Symptom severity (0–10) at or above which a symptom counts as severe.
const severeSymptomLevel = 7;
