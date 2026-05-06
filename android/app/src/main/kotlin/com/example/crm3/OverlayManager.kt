package com.example.crm3

import android.content.Context
import android.graphics.PixelFormat
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import kotlin.math.abs

class OverlayManager private constructor(private val context: Context) {
    private val ENGINE_ID = "overlay_engine"
    private val CHANNEL_NAME = "com.example.crm3/overlay"

    private var windowManager: WindowManager? = null
    private var flutterView: FlutterView? = null
    private var methodChannel: MethodChannel? = null
    var isOverlayShown = false
        private set
    private var layoutParams: WindowManager.LayoutParams? = null
    private var rootLayout: FrameLayout? = null

    companion object {
        @Volatile
        private var instance: OverlayManager? = null

        fun getInstance(context: Context): OverlayManager {
            return instance ?: synchronized(this) {
                instance ?: OverlayManager(context.applicationContext).also { instance = it }
            }
        }
    }

    init {
        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        initFlutterEngine()
    }

    private fun initFlutterEngine() {
        var flutterEngine = FlutterEngineCache.getInstance().get(ENGINE_ID)
        if (flutterEngine == null) {
            try {
                Log.d("OverlayManager", "Initializing FlutterEngine for overlay")
                flutterEngine = FlutterEngine(context)
                GeneratedPluginRegistrant.registerWith(flutterEngine)
                
                // 🌉 Register the global bridge for the overlay engine
                flutterEngine.plugins.add(CallBridgePlugin())

                FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)

                methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
                setupMethodChannel()

                val flutterLoader = FlutterInjector.instance().flutterLoader()
                flutterLoader.startInitialization(context)
                flutterLoader.ensureInitializationCompleteAsync(context, null, android.os.Handler(android.os.Looper.getMainLooper())) {
                    val entrypoint = DartExecutor.DartEntrypoint(flutterLoader.findAppBundlePath(), "overlayMain")
                    flutterEngine?.dartExecutor?.executeDartEntrypoint(entrypoint)
                }
            } catch (e: Exception) {
                Log.e("OverlayManager", "FlutterEngine init failed", e)
            }
        } else {
            methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            setupMethodChannel()
        }
    }

    private fun setupMethodChannel() {
        Log.d("OverlayManager", "Setting up MethodChannel handler on engine: $ENGINE_ID")
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d("OverlayManager", "Overlay MethodChannel call: ${call.method}")
            when (call.method) {
                "closeOverlay" -> {
                    hideOverlay()
                    result.success(null)
                }
                "getNativeNumber" -> {
                    val number = CallManager.getInstance(context).lastKnownNumber
                    Log.d("OverlayManager", "getNativeNumber returning: $number")
                    result.success(number)
                }
                "getPreStartData" -> result.success(CallService.preStartData)
                "updateHeight" -> {
                    val height = call.argument<Int>("height") ?: WindowManager.LayoutParams.WRAP_CONTENT
                    Log.d("OverlayManager", "updateHeight called with: $height")
                    updateWindowHeight(height)
                    result.success(null)
                }
                else -> {
                    Log.w("OverlayManager", "Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    fun updateHeightFromMain(height: Int) {
        updateWindowHeight(height)
    }

    fun updateWindowHeight(height: Int) {
        layoutParams?.let {
            val displayMetrics = context.resources.displayMetrics
            val maxHeight = (displayMetrics.heightPixels * 0.8).toInt()
            
            it.height = if (height > 0) {
                if (height > maxHeight) maxHeight else height
            } else {
                (200 * displayMetrics.density).toInt()
            }

            if (isOverlayShown && rootLayout != null && rootLayout?.isAttachedToWindow == true) {
                try {
                    windowManager?.updateViewLayout(rootLayout, it)
                } catch (e: Exception) {
                    Log.e("OverlayManager", "Failed to update layout height", e)
                }
            }
        }
    }

    fun showOverlay() {
        try {
            if (isOverlayShown) {
                Log.d("OverlayManager", "Overlay already shown, skipping show call.")
                return
            }
            if (isLowMemoryDevice()) {
                Log.w("OverlayManager", "Low memory device, skipping overlay.")
                return
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
                Log.e("OverlayManager", "SYSTEM_ALERT_WINDOW permission not granted")
                // ColorOS pe direct settings page open karo
                requestOverlayPermissionColoros()
                return
            }

            initFlutterEngine()
            val flutterEngine = FlutterEngineCache.getInstance().get(ENGINE_ID) ?: run {
                Log.e("OverlayManager", "Failed to get/init Flutter engine")
                return
            }

            val displayMetrics = context.resources.displayMetrics
            rootLayout = createTouchLayout(displayMetrics)
            val flutterParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            flutterView = FlutterView(context, FlutterTextureView(context))
            flutterView?.attachToFlutterEngine(flutterEngine)
            rootLayout?.addView(flutterView, flutterParams)
            
            layoutParams = WindowManager.LayoutParams(
                displayMetrics.widthPixels, // 🚀 Changed from MATCH_PARENT to enable X movement
                (200 * displayMetrics.density).toInt(),

                // Correct type — version wise
                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                        @Suppress("DEPRECATION")
                        WindowManager.LayoutParams.TYPE_SYSTEM_ALERT  // API 23-25
                    else ->
                        @Suppress("DEPRECATION")
                        WindowManager.LayoutParams.TYPE_PHONE          // API 21-22
                },

                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.RGBA_8888
            ).apply {
                gravity = Gravity.CENTER
                x = 0
                y = -200
                dimAmount = 0.0f
            }

            rootLayout?.setBackgroundColor(android.graphics.Color.TRANSPARENT)
            windowManager?.addView(rootLayout, layoutParams)
            isOverlayShown = true
            flutterEngine.lifecycleChannel.appIsResumed()
            Log.i("OverlayManager", "Successfully added overlay view to WindowManager")
        } catch (e: Exception) {
            Log.e("OverlayManager", "Critical error in showOverlay: ${e.message}", e)
            isOverlayShown = false
        }
    }

    private fun createTouchLayout(displayMetrics: DisplayMetrics): FrameLayout {
        return object : FrameLayout(context) {
            private var initialX = 0; private var initialY = 0
            private var initialTouchX = 0f; private var initialTouchY = 0f
            private var isDragging = false
            private var isVerticalDrag = false // 🚀 Flag to lock axis
            private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
            private val dismissThreshold = displayMetrics.widthPixels * 0.35f

            override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = this@OverlayManager.layoutParams?.x ?: 0
                        initialY = this@OverlayManager.layoutParams?.y ?: 0
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isDragging = false
                        isVerticalDrag = false // 🚀 Reset on new touch
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = abs(event.rawX - initialTouchX)
                        val dy = abs(event.rawY - initialTouchY)
                        if (dx > touchSlop || dy > touchSlop) {
                            isDragging = true
                            isVerticalDrag = dy > dx // 🚀 Determine axis on start
                            return true
                        }
                    }
                }
                return false
            }

            override fun onTouchEvent(event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_MOVE -> {
                        this@OverlayManager.layoutParams?.let {
                            if (isVerticalDrag) {
                                // 🚀 Vertical move only
                                it.y = initialY + (event.rawY - initialTouchY).toInt()
                            } else {
                                // 🚀 Horizontal move only
                                it.x = initialX + (event.rawX - initialTouchX).toInt()
                            }
                            try { windowManager?.updateViewLayout(this, it) } catch (e: Exception) {}
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (isDragging) {
                            val totalDx = abs(event.rawX - initialTouchX)
                            if (totalDx > dismissThreshold) {
                                // 🚀 Smooth Slide Out Animation (Dismiss)
                                val startX = this@OverlayManager.layoutParams?.x ?: 0
                                val targetX = if (event.rawX > initialTouchX) displayMetrics.widthPixels else -displayMetrics.widthPixels
                                
                                val dismissAnimator = android.animation.ValueAnimator.ofFloat(0f, 1f)
                                dismissAnimator.duration = 250
                                dismissAnimator.addUpdateListener { animation ->
                                    val fraction = animation.animatedValue as Float
                                    this@OverlayManager.layoutParams?.let { lp ->
                                        lp.x = (startX + (targetX - startX) * fraction).toInt()
                                        try { windowManager?.updateViewLayout(this, lp) } catch (e: Exception) {}
                                    }
                                }
                                dismissAnimator.addListener(object : android.animation.AnimatorListenerAdapter() {
                                    override fun onAnimationEnd(animation: android.animation.Animator) {
                                        performHide()
                                    }
                                })
                                dismissAnimator.start()
                            } else {
                                // 🚀 Springy Snap Back Animation
                                val startX = this@OverlayManager.layoutParams?.x ?: 0
                                val startY = this@OverlayManager.layoutParams?.y ?: 0
                                
                                val snapAnimator = android.animation.ValueAnimator.ofFloat(0f, 1f)
                                snapAnimator.duration = 400
                                // 🚀 Higher tension for a more "jumpy" Truecaller-like feel
                                snapAnimator.interpolator = android.view.animation.OvershootInterpolator(1.8f)
                                snapAnimator.addUpdateListener { animation ->
                                    val fraction = animation.animatedValue as Float
                                    this@OverlayManager.layoutParams?.let { lp ->
                                        lp.x = (startX + (0 - startX) * fraction).toInt()
                                        lp.y = (startY + (-200 - startY) * fraction).toInt()
                                        try { windowManager?.updateViewLayout(this, lp) } catch (e: Exception) {}
                                    }
                                }
                                snapAnimator.start()
                            }
                            isDragging = false
                            return true
                        }
                    }
                }
                return super.onTouchEvent(event)
            }
        }
    }

    fun hideOverlay() {
        if (!isOverlayShown) return
        
        val startX = layoutParams?.x ?: 0
        val displayMetrics = context.resources.displayMetrics
        val targetX = displayMetrics.widthPixels // 🚀 Always slide out to the RIGHT
        
        val exitAnimator = android.animation.ValueAnimator.ofFloat(0f, 1f)
        exitAnimator.duration = 300
        exitAnimator.addUpdateListener { animation ->
            val fraction = animation.animatedValue as Float
            layoutParams?.let { lp ->
                lp.x = (startX + (targetX - startX) * fraction).toInt()
                try { windowManager?.updateViewLayout(rootLayout, lp) } catch (e: Exception) {}
            }
        }
        exitAnimator.addListener(object : android.animation.AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: android.animation.Animator) {
                performHide()
            }
        })
        exitAnimator.start()
    }

    private fun performHide() {
        try {
            methodChannel?.invokeMethod("clearData", null)
            if (rootLayout != null && rootLayout?.isAttachedToWindow == true) {
                windowManager?.removeView(rootLayout)
            }
            flutterView?.detachFromFlutterEngine()
            flutterView = null
            rootLayout = null
            isOverlayShown = false
        } catch (e: Exception) {
            Log.e("OverlayManager", "Error in performHide", e)
        }
    }

    fun pushDataToOverlay(data: Map<String, Any>) {
        try { methodChannel?.invokeMethod("updateData", data) } catch (e: Exception) {
            Log.e("OverlayManager", "Failed to push data to overlay", e)
        }
    }

    fun handleMemoryPressure() {
        Log.w("OverlayManager", "Memory pressure detected! Releasing Flutter engine if hidden...")
        if (!isOverlayShown) {
            destroyFlutterEngine()
        }
    }

    fun destroyFlutterEngine() {
        try {
            if (isOverlayShown && rootLayout?.isAttachedToWindow == true) {
                windowManager?.removeView(rootLayout)
            }
        } catch (e: Exception) {
            Log.e("OverlayManager", "Force remove failed: $e")
        } finally {
            // Always reset — chahe exception aaye ya na aaye
            flutterView?.detachFromFlutterEngine()
            flutterView = null
            rootLayout = null
            isOverlayShown = false
        }

        try {
            FlutterEngineCache.getInstance().get(ENGINE_ID)?.destroy()
            FlutterEngineCache.getInstance().remove(ENGINE_ID)
        } catch (e: Exception) {
            Log.e("OverlayManager", "Engine destroy failed: $e")
        }
        methodChannel = null
    }

    private fun requestOverlayPermissionColoros() {
        val manufacturer = Build.MANUFACTURER.lowercase()
        if (manufacturer.contains("oppo") || manufacturer.contains("realme")) {
            // ColorOS ka specific overlay settings page
            try {
                val intent = Intent("com.android.settings.APPLICATION_DETAIL_SETTINGS").apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                // Fallback to generic
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context.packageName}")
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                context.startActivity(intent)
            }
        } else {
            // Generic fallback if called on other devices (shouldn't happen with current logic)
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context.packageName}")
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                context.startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun isLowMemoryDevice(): Boolean {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        return activityManager.isLowRamDevice
    }
}
