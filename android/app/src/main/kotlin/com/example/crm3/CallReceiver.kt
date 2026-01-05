package com.example.crm3

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

class CallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            val action = intent.action
            Log.d("CallReceiver", "Received action: $action")

            if (action == Intent.ACTION_BOOT_COMPLETED || action == "android.intent.action.QUICKBOOT_POWERON") {
                startCallService(context, "BOOT", null)
                return
            }

            if (action == TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
                val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                Log.d("CallReceiver", "Phone State: $state, Number: $number")
                startCallService(context, state, number)
            }
        } catch (e: Exception) {
            Log.e("CallReceiver", "Error in receiver", e)
        }
    }

    private fun startCallService(context: Context, state: String?, number: String?) {
        val serviceIntent = Intent(context, CallService::class.java)
        serviceIntent.putExtra("state", state)
        serviceIntent.putExtra("number", number)
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
