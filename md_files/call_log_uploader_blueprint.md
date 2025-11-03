# Call Log Uploader — Implementation Blueprint

> **Master setup & implementation prompt** for the `call_log_uploader` Flutter app.
>
> This document is a single-source blueprint for developers: environment, dependencies, Gradle/Kotlin/AGP configuration, architecture, implementation steps, database schema, error-handling strategies, testing, and deployment instructions. Use it to bootstrap the project or to feed into an AI assistant for code generation.

---

## Quick Setup Checklist

- [ ] Flutter SDK `3.35.7` installed and on PATH
- [ ] Dart SDK `3.9.2` (comes with Flutter 3.35.7)
- [ ] Java JDK 17 installed and `JAVA_HOME` set
- [ ] Android Studio with SDKs (compileSdk 35) installed
- [ ] Gradle wrapper configured for `8.12`
- [ ] Android Gradle Plugin (AGP) `8.7.2`
- [ ] Kotlin configured to `1.9.22` (or your chosen stable version) in `android/build.gradle`
- [ ] `flutter pub get` completed successfully
- [ ] `.env` file created and added to `.gitignore` for Supabase keys

---

# 1. Project Overview

A Flutter hybrid app (Android + Web) that:

- Reads Android call logs
- Uploads call logs to Supabase
- Presents a WebView-based CRM with click-to-call
- Provides a Developer Mode page (sync controls, logs, device info)

**Primary pages:**
1. Developer Mode Page (Dev Mode)
2. In-App WebView Page

**Platforms:** Android (call logs) & Web (CRM view and limited features)

**Note:** iOS does not support native call-log access and is out of scope.

---

# 2. Environment & Core Versions (Active Project)

| Component | Recommended Version |
|---|---:|
| Flutter SDK | `3.35.7` (stable)
| Dart SDK | `3.9.2`
| Kotlin | `1.9.x` (project targets JVM 11)
| Gradle (wrapper) | `8.12`
| Android Gradle Plugin (AGP) | `8.7.2`
| Java JDK | `17`
| compileSdkVersion | `35`
| targetSdkVersion | `35`
| minSdkVersion | `21`

> Rationale: these versions are tested and stable for the plugin set chosen. If you need to experiment with newer Kotlin (2.x) do so in a feature branch and test plugin compatibility carefully.

---

# 3. Dependencies (pubspec.yaml)

```yaml
environment:
  sdk: ">=3.9.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  flutter_inappwebview: ^6.1.5
  call_log: ^6.0.1
  permission_handler: ^12.0.1
  flutter_background_service: ^5.1.0
  device_info_plus: ^12.2.0
  package_info_plus: ^4.0.0
  flutter_local_notifications: ^18.0.1
  supabase_flutter: ^2.10.3
  provider: ^6.1.2
  logger: ^2.4.0
  flutter_dotenv: ^5.1.0
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  path_provider: ^2.0.15

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

Run:

```bash
flutter pub get
```

---

# 4. Android Build Configuration

## `android/build.gradle` (root)

```gradle
buildscript {
    ext.kotlin_version = '1.9.22'
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.7.2'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
```

## `android/gradle/wrapper/gradle-wrapper.properties`

```
distributionUrl=https\://services.gradle.org/distributions/gradle-8.12-all.zip
```

## `android/app/build.gradle.kts` (app module)

```kotlin
android {
    namespace = "com.example.crm3"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.crm3"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    lint {
        checkReleaseBuilds = false
        }
    }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Add to `android/gradle.properties` for stability:

```properties
org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError
kotlin.code.style=official
org.gradle.daemon=false
```

---

# 5. Android Manifest & Permissions

Edit `android/app/src/main/AndroidManifest.xml` and add:

```xml
<uses-permission android:name="android.permission.READ_CALL_LOG" />
<uses-permission android:name="android.permission.READ_CONTACTS" />
<uses-permission android:name="android.permission.CALL_PHONE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Add query intent schemes inside `<application>` to allow resolving external apps (Android 11+):

```xml
<queries>
    <intent>
        <action android:name="android.intent.action.DIAL" />
    </intent>
    <intent>
        <action android:name="android.intent.action.SENDTO" />
        <data android:scheme="mailto"/>
    </intent>
    <intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="whatsapp"/>
        </intent>
    </intent>
</queries>
```

> Note: On Android 11+, queries are required to check availability of other apps.

---

# 6. Database (Supabase) Schema & Policies

## SQL: `call_logs` table

```sql
create table public.call_logs (
  id text primary key,
  number text not null,
  name text,
  call_type text,
  duration int,
  timestamp timestamptz not null,
  device_id text not null,
  created_at timestamptz default now()
);
```

## SQL: `sync_meta` table

```sql
create table public.sync_meta (
  device_id text primary key,
  last_synced_at timestamptz,
  last_error text
);
```

## Row-Level Security (RLS) guidance

- Prefer limiting inserts by `device_id` or authenticated claims.
- If direct device uploads are used with anon keys, ensure proper server-side validation.
- Example policy placeholder (adapt to your auth scheme):

```sql
alter table public.call_logs enable row level security;

create policy "allow device insert" on public.call_logs
  for insert
  with check (device_id = current_setting('request.jwt_claims.device_id', true));
```

> IMPORTANT: RLS and claim-based policies require customizing JWT claims or using a server-side proxy.

---

# 7. Local Storage & Bucket System

Use **Hive** for two local boxes:

- `callBucket` — pending logs (keyed by unique id)
- `syncedBucket` — set of ids that have been uploaded

## Unique ID strategy

```
{id} = "{phoneNumber}_{timestampIso}"
```

Use ISO 8601 with timezone (UTC) to avoid collisions. E.g. `+919876543210_2025-03-20T12:30:45Z`.

## Workflow

1. `CallLogService` scans device call logs.
2. For each call entry create `id` and `CallLogModel`.
3. If id not in `syncedBucket` and not in `callBucket`, push to `callBucket`.
4. `SyncService` reads `callBucket`, attempts upload to Supabase.
5. On success: move id → `syncedBucket` and remove from `callBucket`.
6. On failure: leave in `callBucket`, log error, apply retry/backoff policy.

---

# 8. Folder Structure

```
lib/
├─ main.dart
├─ app.dart
├─ services/
│   ├─ call_log_service.dart
│   ├─ sync_service.dart
│   ├─ background_service.dart
│   ├─ webbridge_service.dart
│   ├─ logger_service.dart
│   └─ storage_service.dart
├─ models/
│   └─ call_log_model.dart
├─ pages/
│   ├─ dev_mode_page.dart
│   └─ inapp_webview_page.dart
├─ widgets/
│   ├─ sync_display.dart
│   ├─ manual_controls.dart
│   └─ logs_console.dart
├─ utils/
│   └─ retry.dart
├─ constants.dart
└─ providers/
    └─ sync_provider.dart
```

---

# 9. Core Code Snippets (Canonical Implementations)

> These snippets are canonical starting points. Replace values with your app `package` and wire into providers + DI as you implement.

## `models/call_log_model.dart`

```dart
class CallLogModel {
  final String id;
  final String number;
  final String? name;
  final String callType; // incoming/outgoing/missed
  final int duration;
  final DateTime timestamp;
  final String deviceId;

  CallLogModel({
    required this.id,
    required this.number,
    this.name,
    required this.callType,
    required this.duration,
    required this.timestamp,
    required this.deviceId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'name': name,
    'call_type': callType,
    'duration': duration,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'device_id': deviceId,
  };

  static CallLogModel fromMap(Map m) => CallLogModel(
    id: m['id'],
    number: m['number'],
    name: m['name'],
    callType: m['call_type'],
    duration: m['duration'],
    timestamp: DateTime.parse(m['timestamp']).toUtc(),
    deviceId: m['device_id'],
  );
}
```

## `services/storage_service.dart`

```dart
import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  static const callBucketBox = 'callBucket';
  static const syncedBucketBox = 'syncedBucket';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(callBucketBox);
    await Hive.openBox(syncedBucketBox);
  }

  static Box get callBucket => Hive.box(callBucketBox);
  static Box get syncedBucket => Hive.box(syncedBucketBox);
}
```

## `services/call_log_service.dart` (scan & enqueue)

```dart
import 'package:flutter/foundation.dart';
import 'package:call_log/call_log.dart';
import '../models/call_log_model.dart';
import 'storage_service.dart';
import '../utils/device_utils.dart';

class CallLogService {
  Future<void> scanAndEnqueueNewCalls() async {
    if (kIsWeb) return; // no call logs on web
    Iterable<CallLogEntry> entries = await CallLog.get();
    final deviceId = await DeviceUtils.getDeviceId();

    for (final e in entries) {
      final ts = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
      final id = '${e.number}_${ts.toIso8601String()}';
      if (!StorageService.syncedBucket.containsKey(id) &&
          !StorageService.callBucket.containsKey(id)) {
        final model = CallLogModel(
          id: id,
          number: e.number ?? '',
          name: e.name,
          callType: _mapType(e.callType),
          duration: e.duration ?? 0,
          timestamp: ts.toUtc(),
          deviceId: deviceId,
        );
        StorageService.callBucket.put(id, model.toJson());
      }
    }
  }

  String _mapType(CallType? t) {
    switch (t) {
      case CallType.incoming:
        return 'incoming';
      case CallType.outgoing:
        return 'outgoing';
      case CallType.missed:
        return 'missed';
      default:
        return 'unknown';
    }
  }
}
```

## `services/sync_service.dart` (sync + retry)

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'storage_service.dart';
import '../models/call_log_model.dart';
import '../utils/retry.dart';
import 'logger_service.dart';

class SyncService {
  final SupabaseClient client;
  SyncService(this.client);

  Future<void> syncPending() async {
    final box = StorageService.callBucket;
    final keys = box.keys.toList();
    for (final id in keys) {
      final data = box.get(id);
      final model = CallLogModel.fromMap(Map<String, dynamic>.from(data));
      try {
        await Retry.retry(
          () async {
            final res = await client
                .from('call_logs')
                .insert(model.toJson())
                .execute();
            if (res.error != null) throw res.error!;
          },
          retries: 3,
        );

        // On success:
        StorageService.syncedBucket.put(id, DateTime.now().toIso8601String());
        box.delete(id);
        LoggerService.logInfo('Synced $id');
      } catch (e, st) {
        LoggerService.logError('Failed to sync $id: $e');
        // store last error in sync_meta table or local meta
      }
    }
  }
}
```

## `utils/retry.dart`

```dart
import 'dart:async';

class Retry {
  static Future<T> retry<T>(
    Future<T> Function() fn, {
    int retries = 3,
    Duration initialDelay = const Duration(seconds: 2),
  }) async {
    Duration delay = initialDelay;
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        if (attempt == retries) rethrow;
        await Future.delayed(delay);
        delay *= 2;
      }
    }
    throw Exception('unreachable');
  }
}
```

---

# 10. Background Service

Use `flutter_background_service` with a persistent foreground notification on Android.

### `background_service.dart` (sketch)

```dart
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'call_log_service.dart';
import 'sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BackgroundService {
  static Future<void> setup() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
      ),
      iosConfiguration: IosConfiguration(onForeground: onStart),
    );
    service.startService();
  }

  static void onStart(ServiceInstance service) async {
    final callSvc = CallLogService();
    final syncSvc = SyncService(Supabase.instance.client);

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // run every minute
    Timer.periodic(Duration(minutes: 1), (timer) async {
      try {
        await callSvc.scanAndEnqueueNewCalls();
        await syncSvc.syncPending();
      } catch (e) {
        // log
      }
    });
  }
}
```

> Important: display a persistent notification for the foreground service and handle battery optimization prompts on Android.

---

# 11. WebView & Native Bridge

- Use `flutter_inappwebview`.
- Header: 40px height (use `PreferredSize` for AppBar size). Right corner: settings icon opens Dev Mode.

### Key points

- Register `addJavaScriptHandler` handlers in `InAppWebViewController`.
- Use `shouldOverrideUrlLoading` to intercept `tel:`, `sms:`, `mailto:`, `whatsapp://` and forward to native handlers.
- Log bridge messages to the Dev Mode log console.

### Example JS handler

```dart
webViewController.addJavaScriptHandler(
  handlerName: 'requestDeviceInfo',
  callback: (args) {
    return {
      'deviceId': deviceId,
      'lastSync': lastSyncIso,
    };
  },
);
```

---

# 12. UX & Developer Mode

**Dev Mode page** should include:

- **Sync Display** (counts, last sync timestamps, sync status badge)
- **Manual Controls** (Start Sync, Send Fake Data, Reset Buckets)
- **Log Console** (filterable, color-coded, exportable)
- **Device Info** card (device name, model, OS, app version)

Make UI reactive via `Provider` or `Riverpod` and keep logs persisted for offline inspection.

---

# 13. Error Handling (Detailed)

### Permission errors
- Show modal explaining why access is needed.
- Provide open-app-settings button using `permission_handler` (`openAppSettings()`).
- Pause background sync if permission revoked.

### Network errors
- Retry with exponential backoff (3 attempts). If still failing: pause for 5 minutes, update `sync_meta.last_error`, reflect in UI.

### API errors
- 409 duplicate: mark as synced → move id into `syncedBucket`.
- 400 invalid payload: mark as corrupted and move to a `corrupted` box for manual review.
- 5xx server errors: pause sync and notify user in Dev Mode.

### Service crashes
- On app/service restart, resume from `sync_meta.last_synced_at`.
- Save progress after each successful batch upload.

### Battery optimization
- Detect battery saver/doze (via Android APIs or plugin), warn user, and provide whitelist instructions.

---

# 14. Testing Strategy

- Unit tests: retry logic, bucket logic, id generation.
- Integration tests: sync flow with mock Supabase client.
- Manual tests: permission flows, background sync while app killed, WebView bridge messages.
- Edge-case tests: time zone shifts, clock skew, multiple calls in same second.

---

# 15. CI, Build & Deployment

- Add GitHub Actions for `flutter analyze` and `flutter test`.
- Android build: `flutter build apk --release`.
- Web build: `flutter build web`.
- Keep keystore & signing configs out of repo; use secrets in CI.
- Play Store: include privacy policy explaining call-log usage and background processing.

---

# 16. Privacy & Compliance

- Obtain explicit consent before accessing call logs.
- Optionally hash phone numbers if full number not required.
- Provide opt-out toggle for uploads.
- Document data retention policy and deletion procedure.

---

# 17. Housekeeping SQL

Remove old logs (90 days):

```sql
delete from public.call_logs where timestamp < now() - interval '90 days';
```

---

# 18. Final Checklist Before Development

- [ ] Versions & environment verified
- [ ] Dependencies installed
- [ ] Supabase project & tables set up
- [ ] Hive initialized in `main.dart`
- [ ] Permissions & manifest updated
- [ ] Background service scaffolding in place
- [ ] Dev Mode & WebView skeletons in UI
- [ ] Logging & error capture implemented

---

# 19. Next Deliverables (choose one)

I can generate immediately (paste-ready):

1. Full `/lib` scaffold with empty classes and comments.
2. Working `CallLogService`, `SyncService`, and background loop in a minimal demo app.
3. `dev_mode_page.dart` and `inapp_webview_page.dart` ready UI files wired with Provider and Logger console.
4. Supabase SQL + RLS policies tailored to your auth model (if you provide auth approach).
5. Play Store privacy policy draft for call-log collection and background sync.

Reply with the number of the deliverable you want next and I will generate it.

---

*End of blueprint.*

