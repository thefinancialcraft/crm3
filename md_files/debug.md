# 🐞 Debug Log — Build & Analyze Fixes

This log records issues encountered during setup/build and the exact changes applied to resolve them.

## Analyzer warning
- Message: `unused_field` — The value of the field `_controller` isn't used (`lib/pages/inapp_webview_page.dart`).
- Change: Removed the `_controller` field and its assignment.
- Files:
  - `lib/pages/inapp_webview_page.dart`

## Supabase insert API mismatch
- Message: `undefined_method execute` — Wrong API style used with `supabase_flutter` v2.x.
- Change: Replaced `.insert(...).execute()` with plain `.insert(...)`.
- Files:
  - `lib/services/sync_service.dart`

## Pub dependency resolution
- Message: `hive_flutter ^1.2.0 doesn't match any versions`.
- Change: Downgraded `hive_flutter` to a compatible version.
- Files:
  - `pubspec.yaml` → `hive_flutter: ^1.1.0`

## Android build error — requires core library desugaring
- Messages:
  - `Dependency ':call_log' requires core library desugaring to be enabled`
  - `Dependency ':flutter_local_notifications' requires core library desugaring to be enabled`
- Changes:
  - Enabled core library desugaring.
  - Added `desugar_jdk_libs` dependency at required version.
- Files:
  - `android/app/build.gradle.kts`
    - `compileOptions { isCoreLibraryDesugaringEnabled = true }`
    - `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }`

## Android build instability (Gradle daemon crashes / JVM caches)
- Symptoms: Gradle daemon disappeared; Kotlin incremental cache closing errors.
- Changes:
  - Disable minify and resource shrink in release to reduce build complexity.
  - Disable release lint checks.
  - Reduce Gradle JVM memory to stabilize on Windows.
  - Disable Gradle daemon for the build.
- Files:
  - `android/app/build.gradle.kts`
    - `buildTypes.release { isMinifyEnabled = false; isShrinkResources = false }`
    - `lint { checkReleaseBuilds = false }`
  - `android/gradle.properties`
    - `org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError`
    - `org.gradle.daemon=false`

## Android manifest — required permissions and queries
- Action: Added call log/notifications/foreground service permissions and query intents for `tel`, `mailto`, `whatsapp`.
- Files:
  - `android/app/src/main/AndroidManifest.xml` (top-level `<uses-permission>` + `<queries>`)

## Project documentation alignment
- Action: Updated blueprint to reflect actual, working configuration (KTS, desugaring, dependency versions, gradle properties, namespace/appId).
- Files:
  - `md_files/call_log_uploader_blueprint.md`

## Result
- `flutter analyze`: No issues found.
- `flutter build apk --release`: Success.
- Output: `build/app/outputs/flutter-apk/app-release.apk`


