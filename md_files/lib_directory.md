# 📁 Lib Directory Structure

## 📂 Root Level

```
lib/
├─ main.dart
├─ app.dart
├─ constants.dart
├─ models/
├─ pages/
├─ providers/
├─ services/
├─ utils/
└─ widgets/
```

---

## 📄 Root Files

### `main.dart`
- **Purpose**: Entry point of the application
- **Key Responsibilities**:
  - Initializes Flutter binding
  - Sets up local storage (Hive)
  - Loads environment variables (.env)
  - Initializes Supabase (if credentials provided)
  - Sets up background service
  - Launches the main app

### `app.dart`
- **Purpose**: Main application widget
- **Key Responsibilities**:
  - Implements bottom navigation between CRM and Dev Mode
  - Manages page routing
  - Provides overall app structure

### `constants.dart`
- **Purpose**: Application-wide constants
- **Key Responsibilities**:
  - Supabase configuration (URL, anon key)
  - Storage bucket names
  - Sync settings (interval, retries)
  - Notification settings
  - CRM URL

---

## 📂 `models/`

### `call_log_model.dart`
- **Purpose**: Data model for call logs
- **Key Responsibilities**:
  - Represents call log data structure
  - Provides serialization (toJson)
  - Provides deserialization (fromMap)

---

## 📂 `pages/`

### `inapp_webview_page.dart`
- **Purpose**: WebView-based CRM interface
- **Key Responsibilities**:
  - Loads CRM web application
  - Handles link interception (tel:, sms:, mailto:, whatsapp:)
  - Implements web-to-Flutter communication bridge
  - Provides navigation to Dev Mode

### `dev_mode_page.dart`
- **Purpose**: Developer monitoring interface
- **Key Responsibilities**:
  - Displays sync statistics
  - Provides manual controls
  - Shows real-time logs
  - Implements state management with Provider

---

## 📂 `providers/`

### `sync_provider.dart`
- **Purpose**: State management for sync operations
- **Key Responsibilities**:
  - Tracks sync status (syncing/not syncing)
  - Manages sync statistics (total/synced logs)
  - Stores last sync time
  - Maintains log messages
  - Notifies listeners of state changes

---

## 📂 `services/`

### `background_service.dart`
- **Purpose**: Manages background sync operations
- **Key Responsibilities**:
  - Configures Flutter background service
  - Sets up periodic sync (every minute)
  - Handles service lifecycle events
  - Integrates with call log and sync services

### `call_log_service.dart`
- **Purpose**: Reads and processes device call logs
- **Key Responsibilities**:
  - Requests phone permissions
  - Reads call logs from device
  - Implements duplicate prevention using bucket system
  - Enqueues new logs for sync

### `logger_service.dart`
- **Purpose**: Centralized logging system
- **Key Responsibilities**:
  - Provides structured logging (info, warning, error)
  - Uses Logger package for formatted output
  - Supports stack trace capture

### `storage_service.dart`
- **Purpose**: Local storage management
- **Key Responsibilities**:
  - Initializes Hive storage
  - Manages call bucket (pending logs)
  - Manages synced bucket (uploaded logs)
  - Provides access to storage boxes

### `sync_service.dart`
- **Purpose**: Handles cloud synchronization
- **Key Responsibilities**:
  - Uploads pending logs to Supabase
  - Implements retry mechanism
  - Updates sync metadata
  - Handles API error responses

### `webbridge_service.dart`
- **Purpose**: Communication between web and Flutter
- **Key Responsibilities**:
  - Sends device info to web
  - Sends sync status to web
  - Sends error messages to web
  - Manages web view controller

---

## 📂 `utils/`

### `device_utils.dart`
- **Purpose**: Device identification utilities
- **Key Responsibilities**:
  - Gets unique device ID
  - Handles platform-specific implementations
  - Provides fallback device identification

### `retry.dart`
- **Purpose**: Retry mechanism with exponential backoff
- **Key Responsibilities**:
  - Implements configurable retry logic
  - Provides exponential backoff delays
  - Handles error propagation

---

## 📂 `widgets/`

### `logs_console.dart`
- **Purpose**: Log display component
- **Key Responsibilities**:
  - Displays real-time log messages
  - Provides copy-to-clipboard functionality
  - Implements scrollable log view

### `manual_controls.dart`
- **Purpose**: Manual operation controls
- **Key Responsibilities**:
  - Provides Start Sync button
  - Provides Send Fake Data button
  - Provides Clear Buckets button

### `sync_display.dart`
- **Purpose**: Sync status visualization
- **Key Responsibilities**:
  - Displays total logs count
  - Shows synced vs pending logs
  - Shows last sync time
  - Displays sync status indicator