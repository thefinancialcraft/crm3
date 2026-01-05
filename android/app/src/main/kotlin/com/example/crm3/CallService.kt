package com.example.crm3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.util.Log
import androidx.core.app.NotificationCompat

import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class CallService : Service() {

    private val CHANNEL_NAME = "com.example.crm3/overlay"
    private var windowManager: WindowManager? = null
    private var flutterView: FlutterView? = null
    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    private var isOverlayShown = false

    private lateinit var telephonyManager: TelephonyManager
    private var isListening = false

    private val phoneStateListener = object : PhoneStateListener() {
        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
            super.onCallStateChanged(state, phoneNumber)
            val stateStr = when (state) {
                TelephonyManager.CALL_STATE_RINGING -> "RINGING"
                TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
                TelephonyManager.CALL_STATE_IDLE -> "IDLE"
                else -> "IDLE"
            }
            Log.d("CallService", "State: $stateStr, Number: $phoneNumber")
            handleCallState(stateStr, phoneNumber)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onCreate() {
        super.onCreate()
        Log.d("CallService", "onCreate")
        
        // 1. Foreground Notification
        createNotificationChannel()
        startForeground(9999, createNotification())

        // 2. Setup Telephony
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
        isListening = true

        // 3. Setup WindowManager
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        
        // 4. Pre-warm Flutter Engine
        initFlutterEngine()
    }

    private fun initFlutterEngine() {
        if (flutterEngine == null) {
            Log.d("CallService", "Initializing FlutterEngine")
            flutterEngine = FlutterEngine(this)
            
            // Register Plugins (Crucial for SharedPreferences, etc.)
            GeneratedPluginRegistrant.registerWith(flutterEngine!!)
            
            // Setup MethodChannel
            methodChannel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL_NAME)
            methodChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "closeOverlay" -> {
                        hideOverlay()
                        result.success(null)
                    }
                    "resizeOverlay" -> {
                        // Handle resize if needed
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

            // Execute Entrypoint
            val flutterLoader = FlutterInjector.instance().flutterLoader()
            flutterLoader.startInitialization(this)
            flutterLoader.ensureInitializationComplete(this, null)
            
            val entrypoint = DartExecutor.DartEntrypoint(
                flutterLoader.findAppBundlePath(), 
                "overlayMain"
            )
            flutterEngine!!.dartExecutor.executeDartEntrypoint(entrypoint)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val state = intent?.getStringExtra("state")
        val number = intent?.getStringExtra("number")
        if (state != null) {
            handleCallState(state, number)
        }
        return START_STICKY
    }

    private fun handleCallState(state: String?, number: String?) {
        if (state == "IDLE" || state == TelephonyManager.EXTRA_STATE_IDLE) {
            hideOverlay()
        } else if (state == "RINGING" || state == "OFFHOOK" || state == TelephonyManager.EXTRA_STATE_RINGING || state == TelephonyManager.EXTRA_STATE_OFFHOOK) {
            initFlutterEngine()
            showOverlay()
            
            val callType = if (state == "RINGING" || state == TelephonyManager.EXTRA_STATE_RINGING) "Incoming Call" else "Active Call"
            val contactName = if (number != null) getContactName(number) else null
            
            updateFlutterData(number ?: "Unknown", callType, contactName)
        }
    }

    private fun updateFlutterData(number: String, status: String, name: String?) {
        val data = hashMapOf(
            "number" to number,
            "status" to status,
            "isPersonal" to (name != null) // If visible in contacts, it's 'Personal' usually? Or logic implies CRM vs Personal. 
        )
        if (name != null) data["name"] = name
        
        methodChannel?.invokeMethod("updateData", data)
    }

    private fun getContactName(phoneNumber: String): String? {
        try {
            val uri = android.net.Uri.withAppendedPath(android.provider.ContactsContract.PhoneLookup.CONTENT_FILTER_URI, android.net.Uri.encode(phoneNumber))
            val projection = arrayOf(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME)
            val cursor = contentResolver.query(uri, projection, null, null, null)
            var name: String? = null
            if (cursor != null) {
                if (cursor.moveToFirst()) {
                    name = cursor.getString(0)
                }
                cursor.close()
            }
            return name
        } catch (e: Exception) {
            Log.e("CallService", "Error looking up contact", e)
            return null
        }
    }

    private fun showOverlay() {
        if (isOverlayShown) return
        if (flutterEngine == null) return

        Log.d("CallService", "Showing Overlay")

        // Create FlutterView
        flutterView = FlutterView(this, FlutterTextureView(this))
        flutterView?.attachToFlutterEngine(flutterEngine!!)

        // Window Params
        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        layoutParams.gravity = Gravity.TOP
        layoutParams.y = 100 // Top margin

        // Drag Handling
        flutterView?.setOnTouchListener(object : View.OnTouchListener {
            private var initialY = 0
            private var initialTouchY = 0f

            override fun onTouch(v: View?, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialY = layoutParams.y
                        initialTouchY = event.rawY
                        return false // Let Flutter handle clicks
                    }
                    MotionEvent.ACTION_MOVE -> {
                         // Simple vertical drag
                         layoutParams.y = initialY + (event.rawY - initialTouchY).toInt()
                         windowManager?.updateViewLayout(flutterView, layoutParams)
                         return true // Consume drag
                    }
                }
                return false
            }
        })

        try {
            windowManager?.addView(flutterView, layoutParams)
            isOverlayShown = true
        } catch (e: Exception) {
            Log.e("CallService", "Error showing overlay", e)
        }
    }

    private fun hideOverlay() {
        if (!isOverlayShown) return
        try {
            Log.d("CallService", "Hiding Overlay")
            windowManager?.removeView(flutterView)
            flutterView?.detachFromFlutterEngine()
            flutterView = null
            isOverlayShown = false
        } catch (e: Exception) {
            Log.e("CallService", "Error hiding overlay", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isListening) {
            telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE)
        }
        flutterEngine?.destroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "CallServiceChannel",
                "TFC Nexus Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, "CallServiceChannel")
            .setContentTitle("TFC Nexus Active")
            .setContentText("Ready to display caller info")
            .setSmallIcon(android.R.drawable.sym_def_app_icon)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
