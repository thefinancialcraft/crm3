# Call Log Uploader App - Implementation Blueprint

## Project Overview
A Flutter mobile application that reads call logs from the device, uploads them to a Supabase table, and provides an integrated CRM interface with click-to-call functionality and comprehensive sync features.

The application has two main pages:
1. Developer Mode Page (Dev Mode)
2. In-App WebView Page

The app supports Android and Web platforms only.

## Implementation Steps

### 1. Project Setup
- Configure Flutter environment (3.35.7)
- Set up Android configurations (Kotlin 1.9.22, Gradle 8.12, AGP 8.7.2)
- Add required dependencies to pubspec.yaml

### 2. Supabase Integration
- Create Supabase project
- Configure API keys in lib/constants.dart
- Create required tables (call_logs, sync_meta)

### 3. Core Functionality
- Implement call log reading using call_log package
- Develop background sync service (runs every 1 minute)
- Create duplicate prevention mechanism using bucket system
- Implement auto-retry on failure

### 4. UI Development
- Build Developer Mode Page with three sections:
  - Sync Display
  - Manual Controls
  - Log Display
- Create In-App WebView Page with header and web content
- Implement JavaScript ↔ Flutter bridge for communication

### 5. Phone Integration
- Handle native dialer integration
- Implement WhatsApp, SMS, Mailto link handling
- Manage permissions with user guidance

### 6. Monitoring & Statistics
- Track total logs count, missed calls, last sync time
- Implement persistent foreground service notification
- Add detailed console logs with copy-to-clipboard
- Show current call status ("On Call" / "Idle")

### 7. Background Service
- Implement persistent sync service
- Optimize for battery usage
- Ensure cross-platform support (Android/Web)

## Technical Requirements

### Environment Setup
- Flutter SDK: 3.35.7 (stable)
- Dart SDK: 3.9.2
- Kotlin: 1.9.22 (Stable version compatible with AGP 8.7.2)
- Gradle: 8.12
- Android Gradle Plugin: 8.7.2
- Java JDK: 17
- compileSdkVersion: 35
- targetSdkVersion: 35
- minSdkVersion: 21

### Dependencies
- flutter_inappwebview: ^6.1.5
- call_log: ^6.0.1
- permission_handler: ^12.0.1
- flutter_background_service: ^5.1.0
- device_info_plus: ^12.2.0
- flutter_local_notifications: ^18.0.1
- supabase_flutter: ^2.10.3
- provider: ^6.1.2
- logger: ^2.4.0

## Android Configuration

### Permissions
- READ_CALL_LOG
- READ_CONTACTS
- CALL_PHONE
- FOREGROUND_SERVICE
- POST_NOTIFICATIONS
- Queries for tel:, sms:, mailto:, whatsapp: schemes

## Database Schema

### call_logs Table
| Column | Type | Description |
|--------|------|-------------|
| id | UUID (PK) | Unique identifier |
| number | TEXT | Caller number |
| name | TEXT | Caller name (nullable) |
| call_type | TEXT | incoming/outgoing/missed |
| duration | INTEGER | Call duration (seconds) |
| timestamp | TIMESTAMPTZ | Call time |
| device_id | TEXT | Device unique ID |
| created_at | TIMESTAMPTZ | Default now() |

### sync_meta Table
| Column | Type | Description |
|--------|------|-------------|
| device_id | TEXT (PK) | Device ID |
| last_synced_at | TIMESTAMPTZ | Last successful sync |

## Application Architecture

### Project Directory Structure
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

### Main Function
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  await dotenv.load(fileName: ".env");

  BackgroundService.setup(); // your wrapper
  runApp(MyApp());
}
```

### BackgroundService
```dart
import 'package:flutter_background_service/flutter_background_service.dart';
import 'call_log_service.dart';
import 'sync_service.dart';
import 'constants.dart';

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

### CallLogModel
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

### StorageService
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

### CallLogService
```dart
import 'package:call_log/call_log.dart';
import 'models/call_log_model.dart';
import 'storage_service.dart';
import 'utils/device_utils.dart'; // helper getDeviceId

class CallLogService {
  Future<void> scanAndEnqueueNewCalls() async {
    if (kIsWeb) return;
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
      case CallType.incoming: return 'incoming';
      case CallType.outgoing: return 'outgoing';
      case CallType.missed: return 'missed';
      default: return 'unknown';
    }
  }
}
```

### SyncService
```dart
import 'package:supabase_flutter/sabase_flutter.dart';
import 'storage_service.dart';
import 'models/call_log_model.dart';
import 'utils/retry.dart';
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

### Multi-Layered Error Handling

#### Permission Errors
- Show explanatory modal explaining why permission is needed
- Provide button to open app settings (openAppSettings() from permission_handler)
- If permission revoked during sync, pause background sync and show persistent notification

#### Network Errors
- On transient network failure: use in-memory retry with exponential backoff (3 attempts)
- On persistent failures: record error in sync_meta.last_error, set UI status to Server Unreachable, schedule next retry after 5 minutes

#### Supabase / API Errors
- If 409 duplicate error: treat as already synced — move id → syncedBucket
- If 400 invalid payload: log and move to corrupted list for manual review
- For 500: pause sync for 5 minutes and alert Dev Mode

#### Data Parsing
- Wrap every parse in try/catch
- If parse fails, log with full stack and continue

#### Service Crash Recovery
- On startup, read sync_meta.last_synced_at and resume scanning from last timestamp
- Save progress frequently (e.g., after successful batch upload)

#### Background Throttling
- Detect battery saver / doze via Android APIs (optional plugin) and show a warning in Dev Mode
- Provide user instructions to whitelist app

### Developer Mode Page

#### Sync Display
- Displays contact and sync data:
  - Total contacts, synced contacts, last sync timestamp, last call sync
- Uses a bucket system for call logs
- Unique call log ID: phoneNumber + callTimestamp
- Two buckets:
  - Main Bucket – holds new logs before upload
  - Synced Bucket – records successfully uploaded logs
- Monitors call logs every 1 minute
- Shows current call status ("On Call" / "Idle")
- Displays device info (name, model, OS version, app version)
- Automatically resumes sync from last successful point

#### Manual Controls
- Start Sync → Re-establishes sync when automatic sync fails
- Send Fake Data → Pushes dummy logs for testing
- (Optional) Force Refresh / Clear Buckets buttons

#### Log Display
- Real-time logs of app events, errors, and sync updates
- Color-coded by level (info, warning, error)
- Option to filter or export logs

### In-App WebView Page

#### Layout
- Header (40px height)
  - Left: Title/Logo
  - Right: ⚙️ icon → opens Dev Mode Page

#### Features
- Handles links:
  - tel:, sms:, mailto:, whatsapp://
- Includes JavaScript ↔ Flutter bridge for communication:
  - Web app can request device/sync data
  - Flutter can send updates back to web

## How It Works

### 1. Background Service (CallLogService)
- Runs continuously in the background using flutter_background_service
- Checks for new calls every 1 minute
- Uses sync metadata to track last processed call
- Intelligently uploads only new or changed records
- Maintains persistent notification for service status

### 2. CRM Integration (InAppWebView)
- Loads web-based CRM interface
- Intercepts and handles tel:, sms:, mailto:, whatsapp:// links natively
- Provides seamless click-to-call experience
- Shows real-time call status notifications

### 3. Permission Handling
- Manages READ_CALL_LOG permission for accessing calls
- Handles CALL_PHONE permission for click-to-call
- Provides one-tap access to system settings
- Shows user-friendly error messages

### 4. Error Handling and Monitoring
- Real-time console with color-coded messages
- Copy-to-clipboard functionality for logs
- Network and API error handling
- Permission state tracking
- Comprehensive sync status monitoring

## iOS Limitations
- Call logs are not supported on iOS due to platform restrictions
- Click-to-call functionality works on iOS
- WhatsApp integration works on iOS

## Debugging
- Common issues and solutions
- Log access instructions
- Testing procedures

## Build Configuration

### android/build.gradle
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

### android/app/build.gradle
```gradle
android {
    namespace "com.example.call_log_uploader"
    compileSdk 35

    defaultConfig {
        applicationId "com.example.call_log_uploader"
        minSdk 21
        targetSdk 35
        versionCode 1
        versionName "1.0"
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            minifyEnabled false
            shrinkResources false
        }
    }
}
```

## Build Tips
- Set JAVA_HOME to JDK 17
- Add in gradle.properties:
  ```properties
  org.gradle.jvmargs=-Xmx4g -Dfile.encoding=UTF-8
  ```
- Run clean build:
  ```bash
  flutter clean
  flutter pub get
  flutter build apk
  ```
- Use flutter_background_service for periodic syncs (every 1 min)
- Maintain logs via logger for debugging
- Implement Supabase "bucket" logic to prevent duplicates

## Implementation Best Practices

### Kotlin Version Management
- Use Kotlin version 1.9.22 which is stable and compatible with AGP 8.7.2
- Ensure compatibility between Kotlin version and Android Gradle Plugin

### SDK Configuration
- Ensure compileSdkVersion is set to 35 (or 34+) in android/app/build.gradle to match the requirements of InAppWebView
- Verify targetSdkVersion matches compileSdkVersion for Play Store compliance

### Plugin Testing
- After running flutter pub get, perform a full build on both Android and Web platforms
- Watch for errors like "Module was compiled with incompatible version of Kotlin" or "requires future version of Kotlin Gradle plugin"
- Test each plugin individually to ensure proper functionality

### Platform-Specific Code Handling
- Isolate platform-specific code for Web compatibility
- Ensure graceful fallback when features are not supported on certain platforms (e.g., call_log will not work on Web)
- Use conditional imports or runtime platform checks for platform-specific functionality

### Dependency Management
- Keep dependencies updated using flutter pub outdated to check for newer versions and compatibility notes
- Add version constraints in pubspec.yaml to ensure stable builds (e.g., flutter_inappwebview: ^6.1.5 rather than ^7.0.0 if not yet tested)
- Pin critical dependencies to specific versions to avoid breaking changes

## Final Stack Summary
| Layer | Tool | Version |
|-------|------|----------|
| Flutter | 3.35.7 | stable |
| Dart | 3.9.2 | stable |
| Kotlin | 1.9.22 | |
| Gradle | 8.12 | |
| AGP | 8.7.2 | |
| JDK | 17 | |
| SDKs | min 21 / target 35 | |
| Database | Supabase v2 | |
| Background Tasks | flutter_background_service | |
| Web Bridge | flutter_inappwebview | |
| Logging | logger | |
| State Management | provider | |