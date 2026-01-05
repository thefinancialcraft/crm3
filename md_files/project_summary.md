# Call Log Uploader App - Project Summary

## Overview

The Call Log Uploader is a Flutter mobile application that automatically reads phone call history from Android devices and uploads it to a Supabase database. It features a dual-interface design with a Developer Mode for monitoring and a WebView-based CRM interface with click-to-call functionality.

## Core Functionality

### 1. Call Log Management

- Reads device call logs using the `call_log` package
- Prevents duplicate uploads using a dual-bucket system:
  - Main Bucket: Holds new logs before upload
  - Synced Bucket: Tracks successfully uploaded logs
- Generates unique IDs using phoneNumber_timestamp format

### 2. Background Sync Service

- Runs continuously using `flutter_background_service`
- Checks for new calls every minute
- Implements retry mechanism with exponential backoff (3 attempts)
- Maintains persistent foreground notification on Android

### 3. Supabase Integration

- Uploads call logs to Supabase tables
- Handles API errors (409 duplicates, 400 invalid payloads, 500 server errors)
- Updates sync metadata with last successful sync time

### 4. Dual-Interface Design

- Developer Mode Page: Monitoring and control interface
- WebView Page: CRM interface with native link handling

## Workflow

### Data Flow

1. Background service initializes and starts periodic scanning
2. CallLogService scans device call logs every minute
3. New logs are checked against synced and pending buckets
4. Unsynced logs are added to the call bucket
5. SyncService uploads pending logs to Supabase
6. Successful uploads move logs to synced bucket
7. Errors are logged and retried based on type

### Error Handling

- **Permission Errors**: Explanatory modals with app settings access
- **Network Errors**: Exponential backoff retry (3 attempts)
- **API Errors**: Specific handling for different HTTP status codes
- **Data Parsing**: Try/catch wrapping with full stack logging
- **Service Crashes**: Resume from last sync timestamp
- **Background Throttling**: Detect battery saver/doze mode

## Technical Configuration

### Environment Versions

- Flutter SDK: 3.35.7 (stable)
- Dart SDK: 3.9.2
- Kotlin: 1.9.22 (stable version compatible with AGP 8.7.2)
- Gradle: 8.12
- Android Gradle Plugin: 8.7.2
- Java JDK: 17
- compileSdkVersion: 35
- targetSdkVersion: 35
- minSdkVersion: 21

### Dependencies

```yaml
dependencies:
  flutter_inappwebview: ^6.1.5
  call_log: ^6.0.1
  permission_handler: ^12.0.1
  flutter_background_service: ^5.1.0
  device_info_plus: ^12.2.0
  flutter_local_notifications: ^18.0.1
  supabase_flutter: ^2.10.3
  provider: ^6.1.2
  logger: ^2.4.0
  hive: ^2.2.3
  hive_flutter: ^1.2.0
  flutter_dotenv: ^5.1.0
  path_provider: ^2.0.15

dev_dependencies:
  flutter_lints: ^5.0.0
```

### Android Permissions

```xml
<uses-permission android:name="android.permission.READ_CALL_LOG" />
<uses-permission android:name="android.permission.READ_CONTACTS" />
<uses-permission android:name="android.permission.CALL_PHONE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<queries>
    <intent>
        <action android:name="android.intent.action.DIAL" />
    </intent>
    <intent>
        <action android:name="android.intent.action.SENDTO" />
        <data android:scheme="mailto"/>
    </intent>
    <intent>
        <action android:name="android.intent.action.VIEW" />
        <data android:scheme="whatsapp"/>
    </intent>
</queries>
```

## Database Schema

### call_history Table

| Column     | Type        | Description                               |
| ---------- | ----------- | ----------------------------------------- |
| id         | TEXT (PK)   | Unique identifier (phoneNumber_timestamp) |
| number     | TEXT        | Caller number                             |
| name       | TEXT        | Caller name (nullable)                    |
| call_type  | TEXT        | incoming/outgoing/missed                  |
| duration   | INTEGER     | Call duration (seconds)                   |
| timestamp  | TIMESTAMPTZ | Call time                                 |
| device_id  | TEXT        | Device unique ID                          |
| created_at | TIMESTAMPTZ | Default now()                             |

### sync_meta Table

| Column         | Type        | Description                   |
| -------------- | ----------- | ----------------------------- |
| device_id      | TEXT (PK)   | Device ID                     |
| last_synced_at | TIMESTAMPTZ | Last successful sync          |
| last_error     | TEXT        | Last error message (optional) |

## UI/UX Design

### Developer Mode Page

#### Sync Display

- Total contacts, synced contacts, last sync timestamp
- Current call status ("On Call" / "Idle")
- Device info (name, model, OS version, app version)
- Automatic resume from last successful sync point

#### Manual Controls

- Start Sync: Re-establishes sync when automatic sync fails
- Send Fake Data: Pushes dummy logs for testing
- Force Refresh / Clear Buckets: Optional buttons

#### Log Display

- Real-time logs of app events, errors, and sync updates
- Color-coded by level (info, warning, error)
- Filter and export capabilities

### In-App WebView Page

#### Layout

- Header (40px height)
  - Left: Title/Logo
  - Right: ⚙️ icon to open Dev Mode Page

#### Features

- Handles tel:, sms:, mailto:, whatsapp:// links
- JavaScript ↔ Flutter bridge for communication
- Web app can request device/sync data
- Flutter can send updates back to web

## Platform Support

- Android: Full features (call logs, background service)
- Web: View-only version (CRM interface)
- iOS: Limited support (no call logs due to platform restrictions)

## Architecture

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

## Key Implementation Details

### Storage System

- Uses Hive for local storage
- Two-box system for duplicate prevention
- Persistent storage across app sessions

### Retry Mechanism

- Exponential backoff for network failures
- Specific error handling for different API responses
- Configurable retry attempts (default: 3)

### Security & Privacy

- Requires explicit user permission for call log access
- Device identification for multi-device support
- Potential for phone number hashing (optional)

## Build & Deployment

- Android: `flutter build apk --release`
- Web: `flutter build web`
- GitHub Actions for CI/CD
- Play Store compliance with privacy policy

## Testing Strategy

- Unit tests for retry logic and bucket management
- Integration tests with mock Supabase client
- Manual testing for permission flows
- Edge-case testing for time zones and clock skew
