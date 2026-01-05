# 📱 Call Log Uploader — Human Blueprint (Full Project Explanation)

## 💡 What This App Does

The **Call Log Uploader** is a Flutter mobile app that automatically reads your recent phone call history and uploads it to a **Supabase** database.

It’s designed for Android (and Web for viewing/logging) and can help teams track client calls, sync them to a CRM, and see everything in one place.

Think of it like a lightweight **CRM companion app** that keeps your call data synced with your Supabase backend — quietly running in the background.

---

## 🧭 App Overview

The app has **two main pages**:

1. **Developer Mode Page (Dev Mode)** — where you can see what’s happening behind the scenes.
2. **WebView Page (CRM Page)** — where your web-based CRM dashboard is displayed right inside the app.

### Platform Support

- ✅ Android → Full features (reads call logs, uploads, runs background service)
- 🌐 Web → View-only version for testing or data display
- ❌ iOS → Limited (Apple doesn’t allow reading call logs)

---

## 🧱 App Flow — How Everything Connects

### Step 1. Read Call Logs

- The app uses the `call_log` plugin to read the phone’s call history.
- Each call entry includes: number, name, call type (incoming/outgoing/missed), duration, and timestamp.

### Step 2. Prepare Data

- Before uploading, the app organizes call logs into **buckets**:
  - **Main Bucket:** new call logs that haven’t been uploaded yet.
  - **Synced Bucket:** logs that were already uploaded successfully.
- Each call log gets a **unique ID** — made by combining phone number and call timestamp — to prevent duplicates.

### Step 3. Sync to Supabase

- A background service runs every **minute**, checks for new logs, and uploads them.
- If the internet is offline or Supabase fails, it retries later automatically.
- Sync progress and errors are logged and displayed in Dev Mode.

### Step 4. Developer Mode Page

This page is where you can:

- See total uploaded calls, pending calls, and last sync time.
- Manually start syncing or send fake test data.
- View live logs (with colors for info/warning/error).
- See your device info and app version.
- Watch the sync activity live as it happens.

### Step 5. WebView (CRM) Page

- This page loads your CRM web app inside an embedded browser (`flutter_inappwebview`).
- Any link starting with `tel:`, `sms:`, `mailto:`, or `whatsapp://` is caught and opened using the correct native app.
- A JavaScript bridge allows two-way communication:
  - The web app can request data (like last sync time).
  - The Flutter side can push updates (like new call logs).

---

## 🔄 Background Service

- Runs quietly using `flutter_background_service`.
- Keeps syncing new logs every minute, even when the app is minimized.
- Shows a small **persistent notification** saying “Call Log Sync Active”.
- Uses as little battery as possible.

---

## 🔒 Permissions

On Android, the app asks for:

- `READ_CALL_LOG` → to access call history.
- `CALL_PHONE` → to make calls from inside the app.
- It also declares intent filters for:
  - `tel:`, `sms:`, `mailto:`, and `whatsapp:` links.

If permissions are denied, the app:

- Shows a friendly dialog explaining why it’s needed.
- Offers a one-tap shortcut to open system settings.

---

## 🗃️ Supabase Setup

### Tables Needed

#### `call_history`

| Column     | Type        | Description              |
| ---------- | ----------- | ------------------------ |
| id         | UUID        | Unique log ID            |
| number     | TEXT        | Caller number            |
| name       | TEXT        | Contact name (optional)  |
| call_type  | TEXT        | incoming/outgoing/missed |
| duration   | INTEGER     | Seconds                  |
| timestamp  | TIMESTAMPTZ | When call happened       |
| device_id  | TEXT        | Device identifier        |
| created_at | TIMESTAMPTZ | Defaults to now()        |

#### `sync_meta`

| Column         | Type        | Description       |
| -------------- | ----------- | ----------------- |
| device_id      | TEXT        | Device ID         |
| last_synced_at | TIMESTAMPTZ | Time of last sync |

---

## 🧑‍💻 Developer Mode — Detailed View

### 🧩 1. Sync Display

Shows:

- Total call logs
- Synced vs unsynced logs
- Last successful sync
- Device name, OS, and app version
- Current call state (“On Call” / “Idle”)
- Sync progress bar or percentage

### ⚙️ 2. Manual Controls

Includes:

- **Start Sync:** Manually trigger sync if auto-sync paused.
- **Send Fake Data:** Generate sample call logs to test upload.
- **Clear Buckets (Optional):** Reset stored logs.

### 📋 3. Log Display

- Real-time stream of events: “New call detected”, “Uploading...”, “Sync success!”, or errors.
- Color-coded levels (green = info, orange = warning, red = error).
- Copy logs to clipboard for debugging.
- Option to export logs as a text file.

---

## 🌐 WebView Page — CRM Integration

### Header

A simple top bar:

- **Left:** App name or CRM title.
- **Right:** ⚙️ icon to open Developer Mode.

### Inside WebView

- Loads your CRM website (e.g., Supabase dashboard, or custom CRM).
- If you click on a phone number → the app opens the dialer.
- If you click a WhatsApp or SMS link → the correct app opens.
- Background sync continues even while viewing the CRM.

---

## ⚙️ Technical Environment

| Tool                  | Version | Notes                       |
| --------------------- | ------- | --------------------------- |
| Flutter               | 3.35.7  | Stable                      |
| Dart                  | 3.9.2   | Stable                      |
| Kotlin                | 2.0.21  | Recommended (avoid 2.2.x)   |
| Gradle                | 8.12    | Matches AGP 8.7.x           |
| Android Gradle Plugin | 8.7.2   | Stable                      |
| Java JDK              | 17      | Required                    |
| compileSdkVersion     | 35      | Target latest Android       |
| minSdkVersion         | 21      | Compatible with all plugins |

---

## ⚡ Core Dependencies

```yaml
flutter_inappwebview: ^6.1.5
call_log: ^6.0.1
permission_handler: ^12.0.1
flutter_background_service: ^5.1.0
device_info_plus: ^12.2.0
flutter_local_notifications: ^18.0.1
supabase_flutter: ^2.10.3
provider: ^6.1.2
logger: ^2.4.0
```

These handle everything from background sync and notifications to permission control and state management.

---

## 🧩 App Architecture Summary

| Layer              | Tool                        | Description                        |
| ------------------ | --------------------------- | ---------------------------------- |
| Database           | Supabase                    | Stores all uploaded call logs      |
| Background Service | flutter_background_service  | Sync engine                        |
| UI                 | Flutter                     | Two-page interface                 |
| State Management   | Provider                    | Keeps sync status and logs in sync |
| Logs               | Logger                      | Structured event tracking          |
| Web Layer          | flutter_inappwebview        | Loads CRM dashboard                |
| Notifications      | flutter_local_notifications | Background alerts                  |

---

## 🧠 Developer Tips

- Always test permissions manually (some Android versions behave differently).
- Use `flutter_background_service` carefully to avoid battery drain.
- Monitor Supabase for duplicate records (use `unique(id)` constraint).
- Keep an eye on Kotlin or AGP version mismatches after Flutter updates.
- Use `flutter pub outdated` occasionally to see if any plugin updates are available.

---

## 🚀 Example Workflow

1. User installs and grants permissions.
2. App starts background service.
3. Every minute, the service checks for new call logs.
4. New logs are uploaded to Supabase.
5. WebView CRM reflects updated data in real time.
6. Developer Mode lets you view logs, manually sync, and debug.
