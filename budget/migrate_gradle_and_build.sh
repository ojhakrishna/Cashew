#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
ANDROID_DIR="$ROOT/android"
BACKUP_DIR="$ROOT/_gradle_migration_backups_$(date +%s)"
FLUTTER_SNAP_PATH="/home/ballae/snap/flutter/common/flutter"
ANDROID_SDK_PATH="/home/ballae/Android/Sdk"

echo "Working in: $ROOT"
mkdir -p "$BACKUP_DIR"
echo "Backups will be saved to: $BACKUP_DIR"

# Backup important files if they exist
for f in "$ANDROID_DIR/settings.gradle" "$ANDROID_DIR/build.gradle" "$ANDROID_DIR/app/build.gradle" "$ANDROID_DIR/gradle/wrapper/gradle-wrapper.properties"; do
  if [ -f "$f" ]; then
    cp -v "$f" "$BACKUP_DIR/"
  fi
done

# Ensure local.properties exists and points to snap flutter
echo "Writing android/local.properties (flutter.sdk and sdk.dir)..."
mkdir -p "$ANDROID_DIR"
cat > "$ANDROID_DIR/local.properties" <<LOCALPROPS
flutter.sdk=$FLUTTER_SNAP_PATH
sdk.dir=$ANDROID_SDK_PATH
LOCALPROPS
echo "Wrote: $ANDROID_DIR/local.properties"

# Write modern settings.gradle with pluginManagement and includeBuild
echo "Writing modern android/settings.gradle..."
cat > "$ANDROID_DIR/settings.gradle" <<'SETTINGS'
import java.util.Properties

pluginManagement {
    def localProps = new Properties()
    def localPropsFile = file('local.properties')
    if (localPropsFile.exists()) {
        localPropsFile.withInputStream { s -> localProps.load(s) }
    }
    def flutterSdkPath = localProps.getProperty('flutter.sdk') ?: System.getenv('FLUTTER_ROOT')
    if (flutterSdkPath != null) {
        includeBuild("${flutterSdkPath}/packages/flutter_tools/gradle")
    } else {
        println "Warning: flutter.sdk not set in local.properties and FLUTTER_ROOT not set"
    }

    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
        maven { url 'https://storage.googleapis.com/download.flutter.io' }
        if (flutterSdkPath != null) {
            maven { url "${flutterSdkPath}/packages/flutter_tools/gradle/flutter_plugin_repository" }
        }
    }

    plugins {
        id "dev.flutter.flutter-gradle-plugin" version "1.0.0"
        id "com.android.application" version "7.4.2" apply false
        id "org.jetbrains.kotlin.android" version "1.8.0" apply false
    }
}

rootProject.name = 'budget'
include ':app'
SETTINGS
echo "Wrote: $ANDROID_DIR/settings.gradle"

# Replace app/build.gradle top block with plugins DSL (conservative replace)
if [ -f "$ANDROID_DIR/app/build.gradle" ]; then
  echo "Patching android/app/build.gradle (backup already stored)..."
  cat > "$ANDROID_DIR/app/build.gradle.new" <<APPBUILD
def localProperties = new Properties()
def localPropertiesFile = rootProject.file('local.properties')
if (localPropertiesFile.exists()) {
    localPropertiesFile.withReader('UTF-8') { reader ->
        localProperties.load(reader)
    }
}

def flutterRoot = localProperties.getProperty('flutter.sdk') ?: System.getenv('FLUTTER_ROOT')
if (flutterRoot == null) {
    throw new GradleException("Flutter SDK not found. Define location with flutter.sdk in the local.properties file or set FLUTTER_ROOT environment variable.")
}

plugins {
    id 'com.android.application'
    id 'dev.flutter.flutter-gradle-plugin'
    id 'org.jetbrains.kotlin.android'
    id 'com.google.gms.google-services' // remove if you don't use Firebase
}

def flutterVersionCode = localProperties.getProperty('flutter.versionCode') ?: '1'
def flutterVersionName = localProperties.getProperty('flutter.versionName') ?: '1.0'

def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    compileSdkVersion 34

    sourceSets {
        main.java.srcDirs += 'src/main/kotlin'
    }

    defaultConfig {
        applicationId "com.budget.tracker_app"
        minSdkVersion 23
        targetSdkVersion 34
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
        multiDexEnabled true
    }

    lintOptions {
        disable 'InvalidPackage'
        disable "Instantiatable"
        checkReleaseBuilds false
        abortOnError false
    }

    compileOptions {
      coreLibraryDesugaringEnabled true
      sourceCompatibility JavaVersion.VERSION_1_8
      targetCompatibility JavaVersion.VERSION_1_8
    }

    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}

flutter {
    source '../..'
}

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:1.2.2'
    implementation platform('com.google.firebase:firebase-bom:31.1.1')
    implementation 'com.google.firebase:firebase-auth'
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'androidx.window:window:1.0.0'
    implementation 'androidx.window:window-java:1.0.0'
    implementation 'com.google.android.play:review:2.0.1'
    implementation 'com.google.android.play:review-ktx:2.0.1'
}
APPBUILD

  awk 'BEGIN{p=1} /flutter\s*\{/{p=0} !p{print}' "$ANDROID_DIR/app/build.gradle" >> "$ANDROID_DIR/app/build.gradle.new" 2>/dev/null || true
  mv -v "$ANDROID_DIR/app/build.gradle.new" "$ANDROID_DIR/app/build.gradle"
  echo "Patched android/app/build.gradle"
else
  echo "No android/app/build.gradle found to patch. Aborting."
  exit 1
fi

# Remove any leftover apply from flutter_tools/gradle lines in android dir
echo "Searching for any remaining 'apply from' references to flutter_tools..."
grep -R --line-number "flutter_tools/gradle" "$ANDROID_DIR" || true
find "$ANDROID_DIR" -type f -name "*.gradle" -print0 | xargs -0 sed -i.bak -E "/apply from:.*flutter_tools\\/gradle\\/.*\\.gradle/d" || true
echo "Removed imperative 'apply from' lines referencing flutter_tools (backups are .bak files)."

# Ensure ext.kotlin_version exists in android/build.gradle if needed
if grep -q "kotlin-gradle-plugin" "$ANDROID_DIR/build.gradle" 2>/dev/null; then
  if ! grep -q "ext.kotlin_version" "$ANDROID_DIR/build.gradle" 2>/dev/null; then
    echo "Adding ext.kotlin_version = '1.8.0' to android/build.gradle (if classpath exists)"
    awk 'BEGIN{added=0} /buildscript/ && added==0 {print; print "    ext.kotlin_version = \"1.8.0\""; added=1; next} {print}' "$ANDROID_DIR/build.gradle" > "$ANDROID_DIR/build.gradle.tmp" && mv "$ANDROID_DIR/build.gradle.tmp" "$ANDROID_DIR/build.gradle"
  fi
fi

# Try to detect AGP version and pick a compatible Gradle wrapper version
AGP_VERSION=$(grep -Po "com.android.tools.build:gradle:\K[0-9.]+" "$ANDROID_DIR/build.gradle" 2>/dev/null || echo "")
if [ -z "$AGP_VERSION" ]; then
  AGP_VERSION="7.4.2"
fi
echo "Detected AGP version (best-effort): $AGP_VERSION"
if [[ "$AGP_VERSION" =~ ^7\. ]]; then
  GRADLE_VER="7.6.1"
else
  GRADLE_VER="8.6"
fi

echo "Updating gradle wrapper to Gradle $GRADLE_VER (best-effort)..."
cd "$ANDROID_DIR"
if ./gradlew wrapper --gradle-version="$GRADLE_VER" --no-daemon; then
  echo "Gradle wrapper updated."
else
  echo "Gradle wrapper update failed or was unnecessary; continuing."
fi
cd "$ROOT"

export FLUTTER_ROOT="$FLUTTER_SNAP_PATH"
export PATH="$FLUTTER_ROOT/bin:$PATH"

flutter clean || true
flutter pub get || true

echo "Running ./gradlew assembleDebug --stacktrace (this will print a lot). Building now..."
cd "$ANDROID_DIR"
chmod +x gradlew || true
./gradlew assembleDebug --stacktrace --no-daemon 2>&1 | tee "$BACKUP_DIR/gradle_build_output.log"
BUILD_EXIT=${PIPESTATUS[0]}
cd "$ROOT"

echo "Build exit code: $BUILD_EXIT"
echo "Showing last 200 lines of Gradle output:"
tail -n 200 "$BACKUP_DIR/gradle_build_output.log" || true

if [ "$BUILD_EXIT" -ne 0 ]; then
  echo
  echo "If the build still fails, please copy and paste the above tail output here so I can parse the exact error."
  echo "Also, you can share the files in $BACKUP_DIR (backups of original files are stored there)."
else
  echo
  echo "Build succeeded (assembleDebug). Try 'flutter run' from project root now."
fi

exit $BUILD_EXIT
