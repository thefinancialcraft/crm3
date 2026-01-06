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

    companion object {
        var currentPhoneNumber: String? = null
    }

    private val phoneStateListener = object : PhoneStateListener() {
        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
            super.onCallStateChanged(state, phoneNumber)
            if (phoneNumber != null && phoneNumber.isNotEmpty()) {
                currentPhoneNumber = phoneNumber
            }
            val stateStr = when (state) {
                TelephonyManager.CALL_STATE_RINGING -> "RINGING"
                TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
                TelephonyManager.CALL_STATE_IDLE -> {
                    val finalNum = currentPhoneNumber
                    currentPhoneNumber = null // Clear on Idle
                    "IDLE"
                }
                else -> "IDLE"
            }
            Log.d("CallService", "Native State: $stateStr, Number: $phoneNumber | Master: $currentPhoneNumber")
            handleCallState(stateStr, phoneNumber ?: currentPhoneNumber)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(9999, createNotification())
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
        isListening = true
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        initFlutterEngine()
    }

    private fun initFlutterEngine() {
        if (flutterEngine == null) {
            flutterEngine = FlutterEngine(this)
            GeneratedPluginRegistrant.registerWith(flutterEngine!!)
            
            methodChannel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL_NAME)
            methodChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "closeOverlay" -> {
                        hideOverlay()
                        result.success(null)
                    }
                    "getNativeNumber" -> {
                        result.success(currentPhoneNumber)
                    }
                    "updateLookupResult" -> {
                        val data = call.arguments as? Map<String, Any>
                        if (data != null) {
                            methodChannel?.invokeMethod("updateData", data)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

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

    private var lastNumber: String? = null
    private var lastState: String? = null
    private var isIncoming: Boolean = false

    private fun handleCallState(state: String?, number: String?) {
        if (state == lastState && number == lastNumber) return
        
        lastState = state
        lastNumber = number

        if (number != null) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putString("flutter.current_call_number", number).apply()
        }

        when (state) {
            "IDLE", TelephonyManager.EXTRA_STATE_IDLE -> {
                isIncoming = false
                hideOverlay()
            }
            "RINGING", TelephonyManager.EXTRA_STATE_RINGING -> {
                isIncoming = true
                initFlutterEngine()
                showOverlay()
                updateFlutterData(number ?: currentPhoneNumber ?: "Unknown", "RINGING", null)
            }
            "OFFHOOK", TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                initFlutterEngine()
                showOverlay()
                if (!isIncoming) {
                    updateFlutterData(number ?: currentPhoneNumber ?: "Unknown", "DIALING", null)
                } else {
                    updateFlutterData(number ?: currentPhoneNumber ?: "Unknown", "ACTIVE", null)
                }
            }
        }
    }

    private fun updateFlutterData(number: String, status: String, name: String?) {
        val data = hashMapOf(
            "number" to number,
            "status" to status,
            "isPersonal" to true
        )
        if (name != null) data["name"] = name
        methodChannel?.invokeMethod("updateData", data)
    }

    private fun showOverlay() {
        if (isOverlayShown) return
        if (flutterEngine == null) return
        flutterView = FlutterView(this, FlutterTextureView(this))
        flutterView?.attachToFlutterEngine(flutterEngine!!)

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
        layoutParams.y = 100

        flutterView?.setOnTouchListener(object : View.OnTouchListener {
            private var initialY = 0
            private var initialTouchY = 0f
            override fun onTouch(v: View?, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialY = layoutParams.y
                        initialTouchY = event.rawY
                        return false
                    }
                    MotionEvent.ACTION_MOVE -> {
                         layoutParams.y = initialY + (event.rawY - initialTouchY).toInt()
                         windowManager?.updateViewLayout(flutterView, layoutParams)
                         return true
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
