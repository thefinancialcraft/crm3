package com.example.crm3

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.os.Build
import android.provider.CallLog
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class CallManager private constructor(private val context: Context) {
    private val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    
    private var isListening = false
    private var phoneStateListener: PhoneStateListener? = null
    private var telephonyCallback: Any? = null // For API 31+
    
    var lastKnownState: String = "IDLE"
    var lastKnownNumber: String? = null
    
    // Callback to notify the UI/Service when call state changes and number is resolved
    var onCallStateChanged: ((state: String, number: String?) -> Unit)? = null

    companion object {
        @Volatile
        private var instance: CallManager? = null

        fun getInstance(context: Context): CallManager {
            return instance ?: synchronized(this) {
                instance ?: CallManager(context.applicationContext).also { instance = it }
            }
        }
    }

    fun startListening() {
        if (isListening) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // API 31+ — number nahi milta callback mein, CallLog se lena hoga
                telephonyCallback = object : TelephonyCallback(),
                    TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) {
                        when (state) {
                            TelephonyManager.CALL_STATE_RINGING,
                            TelephonyManager.CALL_STATE_OFFHOOK -> {
                                // Number SharedPrefs se recover karo (CallReceiver ne save kiya hoga)
                                val prefs = context.getSharedPreferences(
                                    "FlutterSharedPreferences", Context.MODE_PRIVATE)
                                val savedNumber = prefs.getString("flutter.current_call_number", null)
                                lastKnownNumber = savedNumber
                                handleStateChange(state, savedNumber)
                            }
                            TelephonyManager.CALL_STATE_IDLE -> {
                                // IDLE pe CallLog se number fetch karo (1.5s delay — log update hone do)
                                Handler(Looper.getMainLooper()).postDelayed({
                                    val number = fetchLastCallNumber() ?: lastKnownNumber
                                    lastKnownNumber = null
                                    handleStateChange(state, number)
                                }, 1500)
                            }
                        }
                    }
                }
                // Background thread use karo — UI thread block na ho
                telephonyManager.registerTelephonyCallback(
                    Executors.newSingleThreadExecutor(),
                    telephonyCallback as TelephonyCallback
                )
            } else {
                // API 21-30 — PhoneStateListener
                phoneStateListener = object : PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        // API 28+ pe incoming number null aata hai — fallback use karenge
                        val number = if (phoneNumber.isNullOrEmpty()) {
                            val prefs = context.getSharedPreferences(
                                "FlutterSharedPreferences", Context.MODE_PRIVATE)
                            prefs.getString("flutter.current_call_number", null)
                        } else phoneNumber

                        if (!number.isNullOrEmpty()) lastKnownNumber = number
                        handleStateChange(state, number)
                    }
                }
                @Suppress("DEPRECATION")
                telephonyManager.listen(phoneStateListener,
                    PhoneStateListener.LISTEN_CALL_STATE)
            }
            isListening = true
            Log.i("CallManager", "Started listening (API ${Build.VERSION.SDK_INT})")
        } catch (e: Exception) {
            Log.e("CallManager", "Failed to start listening", e)
        }
    }

    fun stopListening() {
        if (!isListening) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyCallback?.let {
                    telephonyManager.unregisterTelephonyCallback(it as TelephonyCallback)
                }
            } else {
                phoneStateListener?.let {
                    telephonyManager.listen(it, PhoneStateListener.LISTEN_NONE)
                }
            }
            isListening = false
        } catch (e: Exception) {
            Log.e("CallManager", "Failed to stop listening", e)
        }
    }

    fun updateState(stateStr: String?, incomingNumber: String?) {
        val state = when (stateStr) {
            TelephonyManager.EXTRA_STATE_RINGING -> TelephonyManager.CALL_STATE_RINGING
            TelephonyManager.EXTRA_STATE_OFFHOOK -> TelephonyManager.CALL_STATE_OFFHOOK
            TelephonyManager.EXTRA_STATE_IDLE -> TelephonyManager.CALL_STATE_IDLE
            "RINGING" -> TelephonyManager.CALL_STATE_RINGING
            "OFFHOOK" -> TelephonyManager.CALL_STATE_OFFHOOK
            "IDLE" -> TelephonyManager.CALL_STATE_IDLE
            else -> return
        }
        handleStateChange(state, incomingNumber)
    }

    private fun handleStateChange(state: Int, incomingNumber: String?) {
        val stateStr = when (state) {
            TelephonyManager.CALL_STATE_RINGING -> "RINGING"
            TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
            TelephonyManager.CALL_STATE_IDLE -> "IDLE"
            else -> "IDLE"
        }

        if (incomingNumber != null && incomingNumber.isNotEmpty()) {
            lastKnownNumber = incomingNumber
        }

        lastKnownState = stateStr

        if (stateStr == "IDLE") {
            // Need to fetch number from CallLog if we didn't get it
            Executors.newSingleThreadScheduledExecutor().schedule({
                val number = fetchLastCallNumber() ?: lastKnownNumber
                lastKnownNumber = null // Reset for next call
                onCallStateChanged?.invoke(stateStr, number)
            }, 1000, TimeUnit.MILLISECONDS)
        } else {
            // We notify immediately for RINGING/OFFHOOK
            onCallStateChanged?.invoke(stateStr, lastKnownNumber)
        }
    }

    private fun fetchLastCallNumber(): String? {
        // READ_CALL_LOG check — READ_PHONE_STATE se alag hai API 29+
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Manifest.permission.READ_CALL_LOG
        } else {
            Manifest.permission.READ_PHONE_STATE
        }

        if (ContextCompat.checkSelfPermission(context, permission)
            != PackageManager.PERMISSION_GRANTED) {
            Log.w("CallManager", "Call log permission not granted")
            return null
        }

        var number: String? = null
        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.TYPE),
                null, null,
                "${CallLog.Calls.DATE} DESC"
            )
            if (cursor != null && cursor.moveToFirst()) {
                val numIdx = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                if (numIdx != -1) {
                    number = cursor.getString(numIdx)
                }
            }
        } catch (e: Exception) {
            Log.e("CallManager", "fetchLastCallNumber failed: ${e.message}")
        } finally {
            cursor?.close()
        }
        return number
    }
}
