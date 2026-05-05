package com.example.crm3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.app.AlarmManager
import android.app.PendingIntent
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class CallService : Service() {

    private val NOTIFICATION_ID = 9999
    
    companion object {
        var preStartData: Map<String, Any>? = null
        private var instance: CallService? = null

        fun updateOverlayData(data: Map<String, Any>) {
            Log.d("CallService", "Requesting overlay update: $data")
            preStartData = data
            instance?.pushDataToOverlay(data)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private lateinit var prefs: android.content.SharedPreferences
    private val prefListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { p, key ->
        if (key == "flutter.last_lookup_result") {
            val json = p.getString(key, null)
            if (json != null) {
                try {
                    val map = mutableMapOf<String, Any>()
                    val jsonObj = org.json.JSONObject(json)
                    val keys = jsonObj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        map[k] = jsonObj.get(k)
                    }
                    Log.d("CallService", "Detected lookup result in prefs: $map")
                    updateOverlayData(map)
                } catch (e: Exception) {
                    Log.e("CallService", "Failed to parse pref lookup: $e")
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()

        prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.registerOnSharedPreferenceChangeListener(prefListener)

        // Foreground service start — version-wise sahi type use karo
        val notification = createNotification()
        try {
            when {
                Build.VERSION.SDK_INT >= 34 -> // Android 14+
                    startForeground(
                        NOTIFICATION_ID, notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                    )
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> // Android 10-13
                    startForeground(
                        NOTIFICATION_ID, notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                else -> // Android 9 aur neeche
                    startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e("CallService", "startForeground failed: ${e.message}")
            // Last resort fallback
            try { startForeground(NOTIFICATION_ID, notification) } catch (_: Exception) {}
        }

        CallManager.getInstance(this).apply {
            onCallStateChanged = { state, number -> handleCallState(state, number) }
            startListening()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val state = intent?.getStringExtra("state")
        val number = intent?.getStringExtra("number")
        val command = intent?.getStringExtra("command")
        
        Log.d("CallService", "onStartCommand: command=$command, state=$state, number=$number")

        when (command) {
            "showOverlayWithData" -> OverlayManager.getInstance(this).showOverlay()
            "closeOverlay" -> OverlayManager.getInstance(this).hideOverlay()
            else -> {
                if (state != null) {
                    // 🚀 Proactive Overlay: Show immediately if we know we are ringing or active
                    if (state == "RINGING" || state == "OFFHOOK" || state == TelephonyManager.EXTRA_STATE_RINGING || state == TelephonyManager.EXTRA_STATE_OFFHOOK) {
                        OverlayManager.getInstance(this).showOverlay()
                    }
                    CallManager.getInstance(this).updateState(state, number)
                }
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // App swipe karke band ho to bhi service restart karo — Vivo ke liye zaroori
        val restartIntent = Intent(applicationContext, CallService::class.java).apply {
            setPackage(packageName)
        }
        val restartPendingIntent = PendingIntent.getService(
            this, 1, restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            alarmManager.set(
                AlarmManager.ELAPSED_REALTIME,
                android.os.SystemClock.elapsedRealtime() + 1000,
                restartPendingIntent
            )
        } catch (e: Exception) {
            Log.e("CallService", "onTaskRemoved restart failed: $e")
        }
    }

    private fun handleCallState(state: String, number: String?) {
        if (number != null && number.isNotEmpty()) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putString("flutter.current_call_number", number).apply()
        }
        when (state) {
            "IDLE" -> {
                preStartData = null
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().remove("flutter.current_call_number").remove("flutter.last_lookup_result").apply()
                OverlayManager.getInstance(this).hideOverlay()
            }
            "RINGING", "OFFHOOK" -> {
                val overlayManager = OverlayManager.getInstance(this)
                val data = mutableMapOf<String, Any>("status" to state)
                if (number != null) {
                    data["number"] = number
                    // 🚀 Fetch name from phone contacts if available
                    getContactName(this, number)?.let { 
                        Log.d("CallService", "Found contact name in phonebook: $it")
                        data["contactName"] = it 
                    }
                }
                
                // 🛡️ CRITICAL: Always update preStartData so new engines get it immediately
                preStartData = data

                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)) {
                    overlayManager.showOverlay()
                }
                
                if (overlayManager.isOverlayShown) {
                    overlayManager.pushDataToOverlay(data)
                }
            }
        }
    }

    private fun getContactName(context: Context, phoneNumber: String): String? {
        if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.READ_CONTACTS) 
            != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Log.w("CallService", "READ_CONTACTS permission NOT granted")
            return null
        }
        
        // 🛠️ Normalize number for search: Keep only digits and '+'
        val cleanNumber = phoneNumber.replace(Regex("[^0-9+]"), "")
        Log.d("CallService", "Searching contact name for: $phoneNumber (Cleaned: $cleanNumber)")
        
        // Method 1: PhoneLookup (Android's standard way)
        try {
            val uri = android.net.Uri.withAppendedPath(
                android.provider.ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                android.net.Uri.encode(cleanNumber)
            )
            val projection = arrayOf(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME)
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)
                    Log.d("CallService", "Method 1 Success: $name")
                    return name
                }
            }
        } catch (e: Exception) {
            Log.e("CallService", "Method 1 failed: $e")
        }
        
        // Method 2: Manual search using LAST 10 DIGITS (Most reliable for Indian numbers)
        try {
            val digitsOnly = cleanNumber.replace(Regex("[^0-9]"), "")
            if (digitsOnly.length >= 10) {
                val last10 = digitsOnly.takeLast(10)
                Log.d("CallService", "Method 2 trying with last 10 digits: $last10")
                
                val selection = "${android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER} LIKE ?"
                val selectionArgs = arrayOf("%$last10")
                
                context.contentResolver.query(
                    android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    arrayOf(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME),
                    selection, selectionArgs, null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val name = cursor.getString(0)
                        Log.d("CallService", "Method 2 Success: $name")
                        return name
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("CallService", "Method 2 failed: $e")
        }

        Log.d("CallService", "No contact name found in phonebook for $phoneNumber")
        return null
    }

    private fun pushDataToOverlay(data: Map<String, Any>) {
        OverlayManager.getInstance(this).pushDataToOverlay(data)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        OverlayManager.getInstance(this).handleMemoryPressure()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_MODERATE) {
            OverlayManager.getInstance(this).handleMemoryPressure()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::prefs.isInitialized) {
            prefs.unregisterOnSharedPreferenceChangeListener(prefListener)
        }
        instance = null
        CallManager.getInstance(this).stopListening()
        OverlayManager.getInstance(this).destroyFlutterEngine()
        
        // Low RAM devices pe service restart schedule karo
        scheduleServiceRestart()
    }

    private fun scheduleServiceRestart() {
        try {
            val restartIntent = PendingIntent.getService(
                this, 0,
                Intent(this, CallService::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.set(
                AlarmManager.ELAPSED_REALTIME,
                android.os.SystemClock.elapsedRealtime() + 2000,
                restartIntent
            )
        } catch (e: Exception) {
            Log.e("CallService", "Restart schedule failed: $e")
        }
    }

    private fun createNotificationChannel() {
        // NotificationChannel sirf API 26+ pe exist karta hai
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "CallServiceChannel",
                "TFC Nexus Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, "CallServiceChannel")
            .setContentTitle("Call Service Active")
            .setContentText("Listening for incoming calls")
            .setSmallIcon(android.R.drawable.sym_def_app_icon)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
