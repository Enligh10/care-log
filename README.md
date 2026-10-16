# Care Log

A shared log for medicines, vitals (blood pressure, heart rate, temperature) and
symptoms, built with Flutter and Firebase.

- **Android app** with a home-screen widget: tap a medicine to log it without
  opening the app.
- **Web version** for iPhone (add it to the home screen from Safari), plus
  one-tap logging buttons through Apple's Shortcuts app.
- **Journal**: a month calendar you can switch between each medicine, each
  symptom, blood pressure, heart rate and temperature, a bullet-journal style
  tracker grid, and monthly stats and charts.
- **Profiles**: one per person being tracked. Link more people or devices with
  an invite code, with or without an account.
- **Notifications** through the free [ntfy](https://ntfy.sh) app when someone
  else logs a dose, a fever or a severe symptom.

## How it's built and published

Every push to `main` runs `.github/workflows/build.yml`, which:

1. generates the Android and web platform files with `flutter create`,
2. applies Care Log's changes to them (`tool/patch_platforms.py`),
3. builds the APK and the web app, and
4. publishes both to GitHub Pages:
   - web app: `https://<user>.github.io/<repo>/`
   - APK: `https://<user>.github.io/<repo>/download/care-log.apk`

Firebase settings come from `config/firebase.json`. Security rules are in
`firestore.rules`.

## Project layout

| Path | What it is |
| --- | --- |
| `lib/ui/today_page.dart` | Dashboard: one-tap meds, vitals, symptoms, today's log |
| `lib/ui/journal_page.dart` | Calendar, tracker grid and monthly stats |
| `lib/ui/settings_page.dart` | Profile sharing, appearance, notifications |
| `lib/ui/shortcuts_page.dart` | iPhone Shortcuts setup steps |
| `lib/widget_bridge_android.dart` | Feeds the Android widget and handles its taps |
| `android/app/src/main/kotlin/.../MedWidgetProvider.kt` | The Android widget |
| `lib/repo.dart` | All Firestore reads and writes |
