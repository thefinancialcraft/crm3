package com.example.crm3

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log
import android.os.Build

class CallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED,
                "android.intent.action.QUICKBOOT_POWERON" -> {
                    Log.d("CallReceiver", "Boot received — starting service")
                    startCallService(context, "BOOT", null)
                }

                TelephonyManager.ACTION_PHONE_STATE_CHANGED -> {
                    val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)

                    // EXTRA_INCOMING_NUMBER — API 29+ pe READ_CALL_LOG chahiye
                    // API 29+ pe number CallManager se milega (SharedPrefs ke zariye)
                    val number = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                    } else {
                        // SharedPrefs mein save karo agar mila toh
                        intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                            ?.also { num ->
                                if (num.isNotEmpty()) {
                                    context.getSharedPreferences(
                                        "FlutterSharedPreferences", Context.MODE_PRIVATE)
                                        .edit()
                                        .putString("flutter.current_call_number", num)
                                        .apply()
                                }
                            }
                    }

                    Log.d("CallReceiver", "Phone State: $state, Number: $number")
                    startCallService(context, state, number)
                }

                // ACTION_NEW_OUTGOING_CALL — sirf API 28 aur neeche
                Intent.ACTION_NEW_OUTGOING_CALL -> {
                    if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
                        val number = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
                        Log.d("CallReceiver", "Outgoing (legacy): $number")

                        // SharedPrefs mein save karo — CallManager baad mein use karega
                        if (!number.isNullOrEmpty()) {
                            context.getSharedPreferences(
                                "FlutterSharedPreferences", Context.MODE_PRIVATE)
                                .edit()
                                .putString("flutter.current_call_number", number)
                                .apply()
                        }
                        startCallService(context, "OFFHOOK", number)
                    }
                    // API 29+ pe CallManager ka TelephonyCallback handle karega
                }
            }
        } catch (e: Exception) {
            Log.e("CallReceiver", "Error: ${e.message}")
        }
    }

    private fun startCallService(context: Context, state: String?, number: String?) {
        try {
            val serviceIntent = Intent(context, CallService::class.java).apply {
                putExtra("state", state)
                putExtra("number", number)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e("CallReceiver", "Failed to start service: ${e.message}")
        }
    }
}
