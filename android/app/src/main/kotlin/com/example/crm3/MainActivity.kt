package com.example.crm3

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.telecom.PhoneAccountHandle
import android.telephony.SubscriptionManager
import android.telephony.SubscriptionInfo
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Method

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.crm3/overlay"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "directCall" -> {
                    val number = call.argument<String>("number")
                    val simId = call.argument<String>("simId")
                    if (number != null) {
                        makeDirectCall(number, simId)
                        result.success(true)
                    } else {
                        result.error("INVALID_NUMBER", "Phone number is null", null)
                    }
                }
                "getSimCards" -> {
                    val simList = getActiveSimCards()
                    result.success(simList)
                }
                "getNativeNumber" -> {
                    result.success(CallService.currentPhoneNumber)
                }
                "disconnectCall" -> {
                    val ok = endActiveCall()
                    result.success(ok)
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
                        }
                        CallService.updateOverlayData(args)
                        startService(intent)
                    }
                    result.success(null)
                }
                "closeOverlay" -> {
                    val intent = Intent(this, CallService::class.java).apply {
                        putExtra("command", "closeOverlay")
                    }
                    startService(intent)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun endActiveCall(): Boolean {
        // Method 1: TelecomManager (Modern way, Android 9+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED) {
                    @Suppress("DEPRECATION")
                    telecomManager.endCall()
                    Log.d("MainActivity", "Call ended via TelecomManager")
                    return true
                } else {
                    Log.w("MainActivity", "Permission ANSWER_PHONE_CALLS missing. Requesting natively...")
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ANSWER_PHONE_CALLS), 101)
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "TelecomManager endCall failed: ${e.message}")
            }
        }

        // Method 2: Reflection on TelephonyManager (Legacy/Manufacturer fallback)
        try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val c = Class.forName(tm.javaClass.name)
            val m: Method = c.getDeclaredMethod("getITelephony")
            m.isAccessible = true
            val telephonyService = m.invoke(tm)
            val telephonyInterface = Class.forName(telephonyService.javaClass.name)
            val endCallMethod: Method = telephonyInterface.getDeclaredMethod("endCall")
            endCallMethod.invoke(telephonyService)
            Log.d("MainActivity", "Call ended via TelephonyManager Reflection")
            return true
        } catch (e: Exception) {
            Log.e("MainActivity", "Reflection endCall failed: ${e.message}")
        }

        return false
    }

    private fun getActiveSimCards(): List<Map<String, Any>> {
        val simList = mutableListOf<Map<String, Any>>()
        try {
            val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                val activeSubscriptionInfoList = subscriptionManager.activeSubscriptionInfoList
                if (activeSubscriptionInfoList != null) {
                    for (subscriptionInfo in activeSubscriptionInfoList) {
                        val simInfo = mutableMapOf<String, Any>()
                        simInfo["id"] = subscriptionInfo.subscriptionId.toString()
                        simInfo["label"] = subscriptionInfo.displayName.toString()
                        simInfo["slotIndex"] = subscriptionInfo.simSlotIndex
                        simList.add(simInfo)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting SIM cards: ${e.message}")
        }
        return simList
    }

    private fun makeDirectCall(number: String, simId: String? = null) {
        try {
            val intent = Intent(Intent.ACTION_CALL)
            intent.data = Uri.parse("tel:$number")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            if (simId != null) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                    val phoneAccounts = telecomManager.callCapablePhoneAccounts
                    for (handle in phoneAccounts) {
                        // On most dual-SIM Android devices, the PhoneAccountHandle ID matches or contains the Subscription ID
                        if (handle.id.contains(simId)) {
                            Log.d("MainActivity", "Using specific SIM account: ${handle.id}")
                            intent.putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                            break
                        }
                    }
                }
            }
            
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
                Log.w("MainActivity", "CALL_PHONE permission not granted. Falling back to DIAL.")
                val dialIntent = Intent(Intent.ACTION_DIAL)
                dialIntent.data = Uri.parse("tel:$number")
                dialIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(dialIntent)
                return
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error making call: ${e.message}")
        }
    }
}
