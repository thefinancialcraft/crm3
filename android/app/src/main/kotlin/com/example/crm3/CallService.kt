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
import android.view.ViewConfiguration
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
import kotlin.math.abs

class CallService : Service() {

    private val CHANNEL_NAME = "com.example.crm3/overlay"
    private var windowManager: WindowManager? = null
    private var flutterView: FlutterView? = null
    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    private var isOverlayShown = false
    private var layoutParams: WindowManager.LayoutParams? = null

    private lateinit var telephonyManager: TelephonyManager
    private var isListening = false

    companion object {
        var currentPhoneNumber: String? = null
        var preStartData: Map<String, Any>? = null
        private var instance: CallService? = null

        fun updateOverlayData(data: Map<String, Any>) {
            Log.d("CallService", "Requesting overlay update: $data")
            preStartData = data
            instance?.pushDataToOverlay(data)
        }
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
                    currentPhoneNumber = null 
                    "IDLE"
                }
                else -> "IDLE"
            }
            handleCallState(stateStr, phoneNumber ?: currentPhoneNumber)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
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
                    "getNativeNumber" -> result.success(currentPhoneNumber)
                    "getPreStartData" -> result.success(preStartData)
                    "updateLookupResult" -> {
                        val args = call.arguments as? Map<String, Any>
                        if (args != null) updateOverlayData(args)
                        result.success(null)
                    }
                    "showOverlayWithData" -> {
                        val args = call.arguments as? Map<String, Any>
                        if (args != null) {
                            updateOverlayData(args)
                            showOverlay()
                        }
                        result.success(null)
                    }
                    "updateHeight" -> {
                        val height = call.argument<Int>("height") ?: WindowManager.LayoutParams.WRAP_CONTENT
                        layoutParams?.let {
                            it.height = if (height > 0) height else WindowManager.LayoutParams.WRAP_CONTENT
                            if (isOverlayShown && rootLayout != null) {
                                windowManager?.updateViewLayout(rootLayout, it)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

            val flutterLoader = FlutterInjector.instance().flutterLoader()
            flutterLoader.startInitialization(this)
            flutterLoader.ensureInitializationComplete(this, null)
            val entrypoint = DartExecutor.DartEntrypoint(flutterLoader.findAppBundlePath(), "overlayMain")
            flutterEngine!!.dartExecutor.executeDartEntrypoint(entrypoint)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val state = intent?.getStringExtra("state")
        val number = intent?.getStringExtra("number")
        val command = intent?.getStringExtra("command")
        if (command == "showOverlayWithData") showOverlay()
        else if (state != null) handleCallState(state, number)
        return START_STICKY
    }

    private fun handleCallState(state: String?, number: String?) {
        if (number != null) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putString("flutter.current_call_number", number).apply()
        }
        when (state) {
            "IDLE" -> hideOverlay()
            "RINGING", "OFFHOOK" -> initFlutterEngine()
        }
    }

    fun pushDataToOverlay(data: Map<String, Any>) {
        try { methodChannel?.invokeMethod("updateData", data) } catch (e: Exception) {}
    }

    private var rootLayout: android.widget.FrameLayout? = null
    private val DRAG_HANDLE_HEIGHT_DP = 60 

    private fun getStatusBarHeight(): Int {
        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else 0
    }

    private fun showOverlay() {
        if (isOverlayShown || flutterEngine == null) return
        
        flutterView = FlutterView(this, FlutterTextureView(this))
        flutterView?.attachToFlutterEngine(flutterEngine!!)

        rootLayout = android.widget.FrameLayout(this).apply {
            isClickable = false
            isFocusable = false
        }
        rootLayout?.addView(flutterView)

        val displayMetrics = resources.displayMetrics
        val dragZoneHeight = (DRAG_HANDLE_HEIGHT_DP * displayMetrics.density).toInt()

        // 🏗️ PRODUCTION FLAG: WRAP_CONTENT for both width and height is crucial.
        // This ensures the "Window" is only as big as the "Card".
        layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = getStatusBarHeight() + 20 
            // We set a minimum width so it doesn't look weird on first frame
            width = (displayMetrics.widthPixels * 0.95).toInt()
        }

        rootLayout?.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0; private var initialY = 0
            private var initialTouchX = 0f; private var initialTouchY = 0f
            private var isMovementStarted = false
            private val touchSlop = ViewConfiguration.get(this@CallService).scaledTouchSlop

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams?.x ?: 0
                        initialY = layoutParams?.y ?: 0
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isMovementStarted = false
                        flutterView?.dispatchTouchEvent(event)
                        
                        // Decision: Should we intercept for dragging?
                        // Return true only if touch is in drag zone
                        return event.y <= dragZoneHeight
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = abs(event.rawX - initialTouchX)
                        val dy = abs(event.rawY - initialTouchY)

                        if (!isMovementStarted && (dx > touchSlop || dy > touchSlop)) {
                            isMovementStarted = true
                            // Cancel outgoing tap in Flutter
                            val cancelEvent = MotionEvent.obtain(event)
                            cancelEvent.action = MotionEvent.ACTION_CANCEL
                            flutterView?.dispatchTouchEvent(cancelEvent)
                            cancelEvent.recycle()
                        }

                        if (isMovementStarted) {
                            layoutParams?.let {
                                it.x = initialX + (event.rawX - initialTouchX).toInt()
                                it.y = initialY + (event.rawY - initialTouchY).toInt()
                                try {
                                    windowManager?.updateViewLayout(rootLayout, it)
                                } catch (e: Exception) {}
                            }
                            return true
                        } else {
                            flutterView?.dispatchTouchEvent(event)
                        }
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        if (!isMovementStarted) {
                            flutterView?.dispatchTouchEvent(event)
                        }
                        isMovementStarted = false
                        return true
                    }
                }
                return false
            }
        })

        try {
            windowManager?.addView(rootLayout, layoutParams)
            isOverlayShown = true
        } catch (e: Exception) {
            Log.e("CallService", "Error showing overlay", e)
        }
    }

    private fun hideOverlay() {
        if (!isOverlayShown) return
        try {
            windowManager?.removeView(rootLayout)
            flutterView?.detachFromFlutterEngine()
            flutterView = null
            rootLayout = null
            isOverlayShown = false
        } catch (e: Exception) {}
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        if (isListening) telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE)
        flutterEngine?.destroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("CallServiceChannel", "TFC Nexus Service", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, "CallServiceChannel")
            .setContentTitle("TFC Nexus Active").setSmallIcon(android.R.drawable.sym_def_app_icon).build()
    }
}
