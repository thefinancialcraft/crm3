package com.example.crm3

import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 🌉 Global bridge that handles telephony commands across ALL Flutter engines
 * (Main App, Background Service, and Overlay)
 */
class CallBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    companion object {
        const val CHANNEL_NAME = "com.example.crm3/main"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        Log.d("CallBridgePlugin", "Attached to engine: ${binding.binaryMessenger}")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateLookupResult" -> {
                val args = call.arguments as? Map<String, Any>
                if (args != null) {
                    Log.d("CallBridgePlugin", "Routing lookup result to overlay: $args")
                    CallService.updateOverlayData(args)
                }
                result.success(null)
            }
            "showOverlayWithData" -> {
                val args = call.arguments as? Map<String, Any>
                if (args != null) {
                    Log.d("CallBridgePlugin", "Routing showOverlayWithData command: $args")
                    val intent = Intent(context, CallService::class.java).apply {
                        putExtra("command", "showOverlayWithData")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    CallService.updateOverlayData(args)
                    context.startService(intent)
                }
                result.success(null)
            }
            "closeOverlay" -> {
                val intent = Intent(context, CallService::class.java).apply {
                    putExtra("command", "closeOverlay")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startService(intent)
                result.success(null)
            }
            "getNativeNumber" -> {
                result.success(CallManager.getInstance(context).lastKnownNumber)
            }
            "getSimCards" -> {
                // We'll need to move getActiveSimCards to a utility class or companion
                result.success(MainActivity.getActiveSimCards(context))
            }
            "directCall" -> {
                val number = call.argument<String>("number")
                val simId = call.argument<String>("simId")
                val slotIndex = call.argument<Int>("slotIndex")
                if (number != null) {
                    MainActivity.makeDirectCall(context, number, simId, slotIndex)
                    result.success(true)
                } else {
                    result.error("INVALID_NUMBER", "Phone number is null", null)
                }
            }
            "disconnectCall" -> {
                result.success(MainActivity.endActiveCall(context))
            }
            "requestBatteryOptimizationBypass" -> {
                MainActivity.requestBatteryOptimizationBypass(context)
                result.success(true)
            }
            "checkBatteryOptimizationBypass" -> {
                val pm = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
            }
            "requestAutoStartPermission" -> {
                MainActivity.requestAutoStartPermission(context)
                result.success(true)
            }
            "checkOverlayPermission" -> {
                val hasPermission = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    android.provider.Settings.canDrawOverlays(context)
                } else {
                    true
                }
                result.success(hasPermission)
            }
            "requestOverlayPermission" -> {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    if (!android.provider.Settings.canDrawOverlays(context)) {
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:${context.packageName}"))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                        } catch (e: Exception) {
                            Log.e("CallBridgePlugin", "Failed to open overlay settings: ${e.message}")
                        }
                    }
                }
                result.success(true)
            }
            "checkInstallPermission" -> {
                result.success(MainActivity.checkInstallPermission(context))
            }
            "openUnknownSourcesSettings" -> {
                MainActivity.openUnknownSourcesSettings(context)
                result.success(null)
            }
            "installApkNative" -> {
                val path = call.argument<String>("path")
                if (path != null) {
                    MainActivity.installApkNative(context, path)
                    result.success(true)
                } else {
                    result.error("INVALID_PATH", "APK path is null", null)
                }
            }
            "getPreStartData" -> {
                result.success(CallService.preStartData)
            }
            else -> result.notImplemented()
        }
    }
}
