# Call Log Application - Function Documentation

## Overview
This Flutter application reads call logs from an Android device and uploads them to a Supabase database. It includes background service capabilities for continuous monitoring and syncing of new calls.

## File Structure
- [constants.dart](file:///d:/flutter%20apps/st/call_log_app/lib/constants.dart) - Contains Supabase configuration constants
- [call_log_service.dart](file:///d:/flutter%20apps/st/call_log_app/lib/call_log_service.dart) - Core service for handling call log operations
- [main.dart](file:///d:/flutter%20apps/st/call_log_app/lib/main.dart) - Main application UI and logic

---

## Constants.dart

### Class: SupabaseConstants
Contains configuration values for connecting to Supabase.

**Properties:**
- `supabaseUrl`: The URL of the Supabase instance
- `supabaseAnonKey`: The anonymous key for accessing Supabase

These values are loaded from environment variables at build time, with defaults provided for local development.

---

## Call_Log_Service.dart

### Class: CallLogService
Main service class responsible for handling all call log operations including reading, uploading, and syncing.

#### Properties
- `_supabase`: Supabase client instance
- `_autoSyncTimer`: Timer for automatic synchronization
- `_autoSyncIntervalSeconds`: Interval for auto-sync (default: 60 seconds)
- `_deviceId`: Unique identifier for the device
- `_syncMetaTable`: Name of the synchronization metadata table
- `_lastKnownCallCount`: Tracks the last known number of call logs
- `_lastSyncTime`: Timestamp of the last successful sync
- `_lastSyncCount`: Number of records in the last sync
- `onSyncComplete`: Callback function triggered after sync completion

#### Methods

##### Static Methods

**initializeBackgroundService()**
Initializes the background service for continuous call log monitoring.
- Configures Android and iOS background service settings
- Sets up notifications for the background service
- Enables auto-start and foreground mode

**backgroundCallback(ServiceInstance service)**
Background execution callback for the service.
- Ensures Dart plugin registration
- Initializes Supabase connection
- Sets up periodic checks for new calls (every 30 seconds)

**onIosBackground(ServiceInstance service)**
iOS background handler.
- Ensures Flutter binding initialization
- Returns true to continue background execution

**checkAndSyncNewCalls()**
Checks for new calls and syncs them if found.
- Reads current call logs
- Compares count with last known count
- Triggers upload if new calls are detected

##### Constructor

**CallLogService()**
Constructor that initializes the Supabase client.

##### Public Methods

**requestPermission()**
Requests phone permission required for reading call logs.
- Uses permission_handler package
- Returns true if permission is granted

**readCallLogs()**
Reads call logs from the device.
- Uses call_log package to fetch entries
- Returns list of CallLogEntry objects or null on error

**uploadNewCallLogs()**
Uploads only new call logs that haven't been synced yet.
- Retrieves last synced timestamp from Supabase
- Filters out duplicate calls using unique identifiers
- Uploads new calls with UUIDs and metadata
- Updates sync metadata after successful upload

**startAutoSync(Function? onSync)**
Starts automatic periodic syncing while the app is active.
- Cancels existing timer if present
- Sets up periodic timer based on _autoSyncIntervalSeconds
- Triggers uploadNewCallLogs() periodically

**stopAutoSync()**
Stops automatic synchronization.
- Cancels the auto-sync timer

**uploadCallLogs(List<CallLogEntry> callLogs)**
Uploads a specific list of call logs to Supabase.
- Converts CallLogEntry objects to database records
- Inserts all records in a single batch

**sendFakeData()**
Sends test/fake call log data to Supabase.
- Creates sample call log entries
- Useful for testing the upload functionality

**getCallLogStats()**
Retrieves statistics about call logs.
- Returns total count, latest call timestamp, and missed call count

**getLastSyncTime()**
Returns the timestamp of the last successful sync.

**getLastSyncCount()**
Returns the number of records in the last sync.

##### Private Methods

**_initSupabase()**
Initializes the Supabase client.

**_getLastSyncedTimestampMs()**
Retrieves the last synced timestamp from Supabase metadata table.

**_updateLastSyncedTimestampMs(int tsMs)**
Updates the last synced timestamp in Supabase metadata table.

**_getCallTypeString(CallType? callType)**
Converts CallType enum to string representation.
- Handles incoming, outgoing, missed, blocked, rejected, and answered externally calls

---

## Main.dart

### Main Function
Entry point of the application.
- Initializes Flutter binding
- Sets up background service
- Initializes Supabase connection
- Requests call log permissions on Android
- Launches the MyApp widget

### Classes

#### MyApp
Root widget of the application.
- Sets up MaterialApp with theme
- Uses BlankScreen as home

#### BlankScreen
Main screen of the application with dual-mode UI.

##### Properties
- `_callLogService`: Instance of CallLogService
- `_logMessages`: List of log messages for display
- `_isProcessing`: Flag indicating ongoing operations
- `_fetchedCount`, `_syncedCount`: Counters for call log operations
- `_totalLogs`, `_missedCalls`: Statistics counters
- `_latestCallTime`, `_lastSyncTime`: Timestamp trackers
- `_showSupabaseSetup`: Controls UI mode (setup vs WebView)
- Various WebView related properties

##### Methods

**_updateStats()**
Updates call log statistics by querying the service.

**initState()**
Initializes the screen.
- Creates CallLogService instance
- Tests Supabase connection
- Updates statistics
- Starts auto-sync

**_testSupabaseConnection()**
Tests the Supabase connection with a simple query.

**_addLogMessage(String message)**
Adds a log message to the display.

**_addErrorMessage(String message)**
Adds an error message to the display.

**_copyLogsToClipboard()**
Copies all log messages to the clipboard.

**_handleStartButtonPressed()**
Handles the Start button press.
- Checks platform compatibility (Android only)
- Calls _readAndUploadLogs()

**_sendFakeData()**
Sends fake test data to Supabase.

**_readAndUploadLogs()**
Main workflow function for reading and uploading call logs.
1. Requests call log permissions
2. Reads call logs from device
3. Uploads new call logs to Supabase
4. Updates statistics

**build()**
Builds the UI with two modes:
1. Supabase Setup Mode: Control panel with statistics and logs
2. WebView Mode: Embedded web browser for CRM interface

**dispose()**
Cleans up resources when the widget is disposed.

---

## Workflow Explanation

### Application Startup
1. Main function initializes background service and Supabase
2. Permissions are requested for Android devices
3. MyApp widget is launched with BlankScreen

### Normal Operation
1. Application starts in WebView mode showing CRM interface
2. User can switch to Setup mode using the menu button
3. In Setup mode, user can manually trigger call log sync or send fake data

### Background Operation
1. Background service runs continuously
2. Checks for new calls every 30 seconds
3. Automatically syncs new calls to Supabase

### Call Log Sync Process
1. Read all call logs from device
2. Retrieve last sync timestamp from Supabase
3. Filter out calls that existed before last sync
4. Generate unique identifiers for remaining calls
5. Upload new calls with full metadata
6. Update sync timestamp in metadata table

### Data Deduplication
- Uses combination of phone number, timestamp, duration, and call type as unique identifier
- Stores last sync timestamp to avoid re-uploading existing calls
- Maintains sync metadata per device

### Error Handling
- Comprehensive try-catch blocks throughout
- Detailed logging for debugging
- User notifications for critical errors
- Graceful degradation when services are unavailable

---

## Key Features
1. **Background Monitoring**: Continuously monitors for new calls
2. **Automatic Sync**: Periodically syncs new calls to cloud storage
3. **Manual Control**: Allows manual triggering of sync operations
4. **Statistics Display**: Shows call log statistics and sync status
5. **Error Logging**: Maintains detailed logs of operations
6. **Cross-Platform**: Supports both Android and iOS (call logs Android only)
7. **WebView Integration**: Embeds CRM interface within the app
8. **Test Data**: Provides option to send fake data for testing