#!/usr/bin/env python3
"""Adjusts the Android files that `flutter create` generates.

The build workflow runs `flutter create .` first (so the Android/Gradle
template always matches the installed Flutter version), then this script adds
what Care Log needs: the home-screen widget receivers, internet permission,
app name, minimum Android version and release signing.

Safe to run more than once. Exits with an error if an expected anchor is
missing, so template changes show up as a clear build failure.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "android" / "app"


def fail(msg: str) -> None:
    print(f"patch_platforms: {msg}", file=sys.stderr)
    sys.exit(1)


def patch_manifest() -> None:
    path = APP / "src" / "main" / "AndroidManifest.xml"
    text = path.read_text()

    if "android.permission.INTERNET" not in text:
        text, n = re.subn(
            r"(<manifest\b[^>]*>)",
            r'\1\n    <uses-permission android:name="android.permission.INTERNET" />',
            text,
            count=1,
        )
        if n != 1:
            fail("could not find <manifest> tag")

    text = re.sub(r'android:label="[^"]*"', 'android:label="Care Log"', text, count=1)

    if "es.antonborri.home_widget.action.LAUNCH" not in text:
        # Let the widget open the app.
        text, n = re.subn(
            r"(</intent-filter>)",
            r"""\1
            <intent-filter>
                <action android:name="es.antonborri.home_widget.action.LAUNCH" />
            </intent-filter>""",
            text,
            count=1,
        )
        if n != 1:
            fail("could not find the activity's intent-filter")

    if "MedWidgetProvider" not in text:
        receivers = """
        <!-- Care Log home-screen widget -->
        <receiver
            android:name=".MedWidgetProvider"
            android:exported="true"
            android:label="Care Log meds">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/med_widget_info" />
        </receiver>

        <!-- Runs Dart code when a widget row is tapped -->
        <receiver
            android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="es.antonborri.home_widget.action.BACKGROUND" />
            </intent-filter>
        </receiver>
    </application>"""
        text, n = re.subn(r"\s*</application>", receivers, text, count=1)
        if n != 1:
            fail("could not find </application>")

    path.write_text(text)
    print("patched", path.relative_to(ROOT))


SIGNING_KTS = """
    signingConfigs {
        create("release") {
            val ks = System.getenv("CARELOG_KEYSTORE")
            if (ks != null && file(ks).exists()) {
                storeFile = file(ks)
                storePassword = System.getenv("CARELOG_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CARELOG_KEY_ALIAS")
                keyPassword = System.getenv("CARELOG_KEY_PASSWORD")
            }
        }
    }

    buildTypes {"""

SIGNING_GROOVY = """
    signingConfigs {
        release {
            def ks = System.getenv("CARELOG_KEYSTORE")
            if (ks != null && file(ks).exists()) {
                storeFile file(ks)
                storePassword System.getenv("CARELOG_KEYSTORE_PASSWORD")
                keyAlias System.getenv("CARELOG_KEY_ALIAS")
                keyPassword System.getenv("CARELOG_KEY_PASSWORD")
            }
        }
    }

    buildTypes {"""


def patch_gradle() -> None:
    kts = APP / "build.gradle.kts"
    groovy = APP / "build.gradle"
    if kts.exists():
        path, is_kts = kts, True
    elif groovy.exists():
        path, is_kts = groovy, False
    else:
        fail("no android/app/build.gradle(.kts) found")
    text = path.read_text()

    # Firebase needs Android 7.0 (API 24) or newer.
    if "CARELOG_MIN_SDK" not in text:
        if is_kts:
            text, n = re.subn(
                r"minSdk\s*=\s*flutter\.minSdkVersion",
                "minSdk = maxOf(flutter.minSdkVersion, 24) // CARELOG_MIN_SDK",
                text,
            )
        else:
            text, n = re.subn(
                r"minSdk(?:Version)?\s*=?\s*flutter\.minSdkVersion",
                "minSdkVersion Math.max(flutter.minSdkVersion, 24) // CARELOG_MIN_SDK",
                text,
            )
        if n == 0:
            fail("could not find minSdk line")

    if "CARELOG_KEYSTORE" not in text:
        text, n = re.subn(r"\n\s*buildTypes\s*\{", SIGNING_KTS if is_kts else SIGNING_GROOVY, text, count=1)
        if n != 1:
            fail("could not find buildTypes block")
        if is_kts:
            text, n = re.subn(
                r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                'signingConfig = if (System.getenv("CARELOG_KEYSTORE") != null) '
                'signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
                text,
            )
        else:
            text, n = re.subn(
                r"signingConfig\s*=?\s*signingConfigs\.debug",
                'signingConfig System.getenv("CARELOG_KEYSTORE") != null ? '
                "signingConfigs.release : signingConfigs.debug",
                text,
            )
        if n == 0:
            fail("could not find the release signingConfig line")

    path.write_text(text)
    print("patched", path.relative_to(ROOT))


if __name__ == "__main__":
    patch_manifest()
    patch_gradle()
