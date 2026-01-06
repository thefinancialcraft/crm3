package com.example.crm3

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL_NAME = "com.example.crm3/overlay"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 🌉 GLOBAL BRIDGE: Register the same channel in the Main App Engine
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNativeNumber" -> {
                    // Pull from the Static Hub in CallService
                    result.success(CallService.currentPhoneNumber)
                }
                "updateLookupResult" -> {
                    // This is handled by CallService if it's running, 
                    // but we acknowledge it here to avoid MissingPluginException
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
