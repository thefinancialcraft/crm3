package com.example.crm3

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.crm3/main"

    override fun onResume() {
        super.onResume()
        // Force the engine to resume its UI state
        flutterEngine?.lifecycleChannel?.appIsResumed()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 🌉 Register the global bridge for this engine
        // This handles commands across Main App and Background Isolate
        flutterEngine.plugins.add(CallBridgePlugin())
        
        // We still keep a small channel handler here for Activity-specific things 
        // if any, but currently most are in the Plugin.
    }

    companion object {
        fun checkInstallPermission(context: Context): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.packageManager.canRequestPackageInstalls()
            } else {
                true
            }
        }

        fun openUnknownSourcesSettings(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            }
        }

        fun getActiveSimCards(context: Context): List<Map<String, Any>> {
            val simList = mutableListOf<Map<String, Any>>()
            try {
                val subscriptionManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                
                val hasPhoneState = ActivityCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
                val hasLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                } else {
                    ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                }

                if (hasPhoneState) {
                    val activeSubscriptionInfoList = subscriptionManager.activeSubscriptionInfoList
                    if (activeSubscriptionInfoList != null) {
                        for (subscriptionInfo in activeSubscriptionInfoList) {
                            val simInfo = mutableMapOf<String, Any>()
                            simInfo["id"] = subscriptionInfo.subscriptionId.toString()
                            simInfo["label"] = subscriptionInfo.displayName.toString()
                            simInfo["slotIndex"] = subscriptionInfo.simSlotIndex
                            
                            var mcc = ""
                            var mnc = ""
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                mcc = subscriptionInfo.mccString ?: ""
                                mnc = subscriptionInfo.mncString ?: ""
                            } else {
                                @Suppress("DEPRECATION")
                                mcc = subscriptionInfo.mcc.toString()
                                @Suppress("DEPRECATION")
                                mnc = subscriptionInfo.mnc.toString()
                            }
                            simInfo["mcc"] = mcc
                            simInfo["mnc"] = mnc
                            simList.add(simInfo)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to get SIM cards: ${e.message}")
            }
            return simList
        }

        fun makeDirectCall(context: Context, number: String, simId: String?, slotIndex: Int?) {
            try {
                val intent = Intent(Intent.ACTION_CALL)
                intent.data = Uri.parse("tel:${Uri.encode(number)}")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

                if (simId != null && simId.isNotEmpty()) {
                    val extras = Bundle()
                    extras.putInt("subscription", simId.toInt())
                    extras.putInt("android.telecom.extra.PHONE_ACCOUNT_HANDLE", simId.toInt())
                    intent.putExtras(extras)
                    
                    // Various OEM keys for SIM selection
                    intent.putExtra("com.android.phone.force.slot", true)
                    intent.putExtra("Cdma_Phone_Number", number)
                    intent.putExtra("simSlot", slotIndex ?: 0)
                    intent.putExtra("subscription", simId.toInt())
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to make call: ${e.message}")
            }
        }

        fun endActiveCall(context: Context): Boolean {
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as android.telecom.TelecomManager
                    if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED) {
                        telecomManager.endCall()
                        true
                    } else false
                } else {
                    false
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to end call: ${e.message}")
                false
            }
        }

        fun requestBatteryOptimizationBypass(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:${context.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                } catch (e: Exception) {
                    Log.e("MainActivity", "Failed to request battery bypass: ${e.message}")
                }
            }
        }

        fun requestAutoStartPermission(context: Context) {
            val manufacturer = Build.MANUFACTURER.lowercase()
            val intent = Intent()
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            when {
                manufacturer.contains("xiaomi") -> {
                    intent.component = ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity"
                    )
                }
                manufacturer.contains("oppo") -> {
                    listOf(
                        "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                        "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity"
                    ).forEach { (pkg, cls) ->
                        try {
                            intent.component = ComponentName(pkg, cls)
                            if (context.packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY).isNotEmpty()) {
                                context.startActivity(intent); return
                            }
                        } catch (_: Exception) {}
                    }
                    return
                }
                manufacturer.contains("vivo") -> {
                    intent.component = ComponentName(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                    )
                }
                manufacturer.contains("samsung") -> {
                    intent.component = ComponentName(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.ui.battery.BatteryActivity"
                    )
                }
                else -> return
            }

            try {
                if (context.packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY).isNotEmpty()) {
                    context.startActivity(intent)
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Auto-start launch failed: $e")
            }
        }

        fun installApkNative(context: Context, path: String) {
            try {
                val file = File(path)
                val uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    file
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to install APK: ${e.message}")
            }
        }
    }
}
