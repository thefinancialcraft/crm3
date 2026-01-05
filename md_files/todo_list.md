# Call Log Uploader App - Implementation Todo List

## Phase 1: Project Setup & Configuration

### 1. Environment Setup

- [ ] Install Flutter SDK 3.35.7
- [ ] Verify Dart SDK 3.9.2
- [ ] Install JDK 17 and set JAVA_HOME
- [ ] Install Android Studio with SDKs (compileSdk 35)
- [ ] Configure Gradle wrapper for 8.12
- [ ] Set up Android Gradle Plugin 8.7.2
- [ ] Configure Kotlin to 1.9.22 in android/build.gradle

### 2. Flutter Project Initialization

- [ ] Create new Flutter project
- [ ] Update pubspec.yaml with all required dependencies
- [ ] Run `flutter pub get` to install dependencies
- [ ] Verify all plugins are compatible and build successfully

### 3. Android Configuration

- [ ] Update AndroidManifest.xml with required permissions:
  - [ ] READ_CALL_LOG
  - [ ] READ_CONTACTS
  - [ ] CALL_PHONE
  - [ ] FOREGROUND_SERVICE
  - [ ] POST_NOTIFICATIONS
- [ ] Add intent queries for tel:, sms:, mailto:, whatsapp: schemes
- [ ] Configure build.gradle files with correct SDK versions

### 4. Supabase Setup

- [ ] Create Supabase project
- [ ] Create call_history table with proper schema
- [ ] Create sync_meta table with proper schema
- [ ] Configure Row Level Security (RLS) policies
- [ ] Add Supabase credentials to .env file

## Phase 2: Core Architecture Implementation

### 5. Project Structure Setup

- [ ] Create lib/services/ directory
- [ ] Create lib/models/ directory
- [ ] Create lib/pages/ directory
- [ ] Create lib/widgets/ directory
- [ ] Create lib/utils/ directory
- [ ] Create lib/providers/ directory

### 6. Data Model Implementation

- [ ] Implement CallLogModel class
  - [ ] Constructor with all required fields
  - [ ] toJson() method for serialization
  - [ ] fromMap() factory constructor for deserialization
- [ ] Implement error handling for data parsing

### 7. Local Storage Service

- [ ] Implement StorageService with Hive
  - [ ] Initialize Hive with Flutter
  - [ ] Create callBucket box
  - [ ] Create syncedBucket box
  - [ ] Implement get methods for both boxes
- [ ] Add error handling for storage operations

### 8. Utility Functions

- [ ] Implement Retry utility with exponential backoff
  - [ ] Configurable retry attempts (default: 3)
  - [ ] Exponential delay between retries
  - [ ] Proper error propagation
- [ ] Implement DeviceUtils for device identification

## Phase 3: Core Functionality Implementation

### 9. Call Log Service

- [ ] Implement CallLogService
  - [ ] scanAndEnqueueNewCalls() method
  - [ ] Platform-specific implementation (exclude Web)
  - [ ] Unique ID generation (phoneNumber_timestamp)
  - [ ] Duplicate prevention using bucket system
  - [ ] Call type mapping (\_mapType method)
- [ ] Add permission error handling
  - [ ] Check for READ_CALL_LOG permission
  - [ ] Show explanatory modal when permission denied
  - [ ] Provide button to open app settings
- [ ] Add data parsing error handling

### 10. Sync Service

- [ ] Implement SyncService
  - [ ] syncPending() method
  - [ ] Integration with Supabase client
  - [ ] Retry mechanism for failed uploads
  - [ ] Success handling (move to syncedBucket)
  - [ ] Error handling for different API responses
- [ ] Add network error handling
  - [ ] Transient network failure detection
  - [ ] Exponential backoff retry (3 attempts)
  - [ ] Persistent failure handling (5-minute pause)
- [ ] Add Supabase/API error handling
  - [ ] 409 duplicate error handling
  - [ ] 400 invalid payload handling
  - [ ] 500 server error handling (5-minute pause)

### 11. Background Service

- [ ] Implement BackgroundService
  - [ ] setup() method for service configuration
  - [ ] onStart() method for service initialization
  - [ ] Timer-based execution every minute
  - [ ] Integration with CallLogService and SyncService
- [ ] Add foreground service notification
- [ ] Add service crash recovery
  - [ ] Resume from sync_meta.last_synced_at
  - [ ] Save progress frequently
- [ ] Add background throttling detection
  - [ ] Battery saver/doze mode detection
  - [ ] User warning in Dev Mode
  - [ ] Whitelist instructions

## Phase 4: UI Implementation

### 12. Main Application Structure

- [ ] Implement main.dart
  - [ ] Initialize StorageService
  - [ ] Load .env file
  - [ ] Setup BackgroundService
  - [ ] Run main app
- [ ] Implement app.dart with proper routing

### 13. Developer Mode Page

- [ ] Create dev_mode_page.dart
  - [ ] Sync Display section
    - [ ] Total contacts display
    - [ ] Synced contacts display
    - [ ] Last sync timestamp
    - [ ] Last call sync
    - [ ] Current call status ("On Call" / "Idle")
    - [ ] Device info display
  - [ ] Manual Controls section
    - [ ] Start Sync button
    - [ ] Send Fake Data button
    - [ ] Force Refresh / Clear Buckets buttons
  - [ ] Log Display section
    - [ ] Real-time log streaming
    - [ ] Color-coded log levels
    - [ ] Filter and export capabilities
    - [ ] Copy to clipboard functionality

### 14. WebView Page

- [ ] Create inapp_webview_page.dart
  - [ ] Header implementation (40px height)
    - [ ] Left: Title/Logo
    - [ ] Right: Settings icon to open Dev Mode
  - [ ] WebView integration
    - [ ] Load CRM web app
    - [ ] Handle tel:, sms:, mailto:, whatsapp:// links
    - [ ] JavaScript ↔ Flutter bridge
    - [ ] Request device/sync data capability
    - [ ] Send updates back to web capability

### 15. Reusable Widgets

- [ ] Create sync_display.dart
- [ ] Create manual_controls.dart
- [ ] Create logs_console.dart

## Phase 5: State Management & Providers

### 16. Provider Implementation

- [ ] Implement SyncProvider
  - [ ] Sync status management
  - [ ] Log streaming
  - [ ] Device info
  - [ ] Error state management

## Phase 6: Error Handling & Logging

### 17. Comprehensive Error Handling

- [ ] Implement permission error handling across all services
- [ ] Implement network error handling with retry mechanisms
- [ ] Implement API error handling for all Supabase responses
- [ ] Implement data parsing error handling
- [ ] Implement service crash recovery mechanisms
- [ ] Implement background throttling detection and handling

### 18. Logging Service

- [ ] Implement LoggerService
  - [ ] Structured logging for all operations
  - [ ] Error logging with full stack traces
  - [ ] Info/warning/error level differentiation
  - [ ] Log persistence for offline inspection

## Phase 7: Testing & Quality Assurance

### 19. Unit Testing

- [ ] Write tests for Retry utility
- [ ] Write tests for bucket logic
- [ ] Write tests for ID generation
- [ ] Write tests for CallLogModel serialization/deserialization

### 20. Integration Testing

- [ ] Write tests for sync flow with mock Supabase client
- [ ] Write tests for background service integration
- [ ] Write tests for WebView bridge communication

### 21. Manual Testing

- [ ] Test permission flows
- [ ] Test background sync while app is killed
- [ ] Test WebView bridge messages
- [ ] Test edge cases (time zone shifts, clock skew)

## Phase 8: Finalization & Deployment

### 22. Final Configuration

- [ ] Verify all environment configurations
- [ ] Test on multiple Android versions
- [ ] Optimize for battery usage
- [ ] Verify cross-platform compatibility

### 23. Documentation

- [ ] Update README with setup instructions
- [ ] Document Supabase table schemas
- [ ] Document error handling procedures
- [ ] Document troubleshooting steps

### 24. Deployment Preparation

- [ ] Prepare Play Store privacy policy
- [ ] Configure build signing for release
- [ ] Test release build
- [ ] Prepare web deployment
