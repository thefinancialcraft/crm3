package com.example.crm3

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
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
                    if (number != null) {
                        makeDirectCall(number)
                        result.success(true)
                    } else {
                        result.error("INVALID_NUMBER", "Phone number is null", null)
                    }
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

    private fun makeDirectCall(number: String) {
        try {
            val intent = Intent(Intent.ACTION_CALL)
            intent.data = Uri.parse("tel:$number")
            
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
                Log.w("MainActivity", "CALL_PHONE permission not granted. Falling back to DIAL.")
                val dialIntent = Intent(Intent.ACTION_DIAL)
                dialIntent.data = Uri.parse("tel:$number")
                startActivity(dialIntent)
                return
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error making call: ${e.message}")
        }
    }
}
