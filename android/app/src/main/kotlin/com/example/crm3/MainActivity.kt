package com.example.crm3

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.crm3/overlay"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNativeNumber" -> {
                    result.success(CallService.currentPhoneNumber)
                }
                "updateLookupResult" -> {
                    val args = call.arguments as? Map<String, Any>
                    if (args != null) {
                        Log.d("MainActivity", "Routing lookup result to overlay: $args")
                        CallService.updateOverlayData(args)
                    }
                    result.success(null)
                }
                "showOverlayWithData" -> {
                    val args = call.arguments as? Map<String, Any>
                    if (args != null) {
                        Log.d("MainActivity", "Routing showOverlayWithData command: $args")
                        val intent = Intent(this, CallService::class.java).apply {
                            putExtra("command", "showOverlayWithData")
                            // We use static update as intent parceling complex maps is messy
                        }
                        CallService.updateOverlayData(args)
                        startService(intent) // Triggers onStartCommand where we can call showOverlay
                    }
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
