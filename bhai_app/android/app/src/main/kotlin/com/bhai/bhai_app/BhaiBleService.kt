package com.bhai.bhai_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Enterprise-grade Android-compliant Foreground Service.
 * Keeps 2.4GHz BLE radio listener and lightweight background network sync active
 * even when the app is minimized or swiped away from recent apps.
 */
class BhaiBleService : Service() {
    companion object {
        const val GUARD_CHANNEL_ID = "bhai_ble_guard_channel"
        const val EMERGENCY_CHANNEL_ID = "bhai_emergency_high_priority"
        const val CHAT_CHANNEL_ID = "bhai_chat_messages"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "com.bhai.app.START_GUARD"
        const val ACTION_STOP = "com.bhai.app.STOP_GUARD"

        private const val MANUFACTURER_ID = 0xFFFF
        private const val SYNC_INTERVAL_MS = 3500L

        var myDeviceId: String = ""
        var apiBaseUrl: String = "http://10.140.120.82:8000"

        fun start(context: Context) {
            val intent = Intent(context, BhaiBleService::class.java).apply {
                action = ACTION_START
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {}
        }

        fun stop(context: Context) {
            val intent = Intent(context, BhaiBleService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.stopService(intent)
            } catch (e: Exception) {}
        }
    }

    private var scanner: BluetoothLeScanner? = null
    private var isScanning = false
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isSyncRunning = false

    private val handledEmergencies = mutableMapOf<String, Long>()
    private val handledChatMessages = mutableSetOf<String>()

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val record = result.scanRecord ?: return
            val rawBytes = record.getManufacturerSpecificData(MANUFACTURER_ID) ?: return

            if (rawBytes.size >= 5 &&
                rawBytes[0] == 'B'.code.toByte() &&
                rawBytes[1] == 'H'.code.toByte() &&
                rawBytes[2] == 'A'.code.toByte() &&
                rawBytes[3] == 'I'.code.toByte()
            ) {
                val type = rawBytes[4].toInt() and 0xFF
                val senderId = if (rawBytes.size >= 9) bytesToHex(rawBytes, 5, 4) else "UNKNOWN"

                // Self-packet filter
                if (myDeviceId.isNotEmpty() && senderId.equals(myDeviceId, ignoreCase = true)) {
                    return
                }

                if (type == 2) { // Emergency SOS
                    showEmergencyNotification(
                        emergencyId = "BHAI-$senderId",
                        senderId = senderId,
                        title = "🚨 EMERGENCY ALERT NEARBY",
                        body = "A Bhai user ($senderId) needs immediate help! Tap to respond."
                    )
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopBackgroundGuard()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildGuardNotification())
        startBackgroundGuard()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopBackgroundGuard()
        super.onDestroy()
    }

    private fun startBackgroundGuard() {
        startBleScanning()
        startNetworkSync()
    }

    private fun stopBackgroundGuard() {
        stopBleScanning()
        isSyncRunning = false
    }

    private fun startBleScanning() {
        if (isScanning) return
        try {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = manager?.adapter
            if (adapter == null || !adapter.isEnabled) return

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) return
            } else {
                if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) return
            }

            scanner = adapter.bluetoothLeScanner ?: return

            val filter = ScanFilter.Builder()
                .setManufacturerData(
                    MANUFACTURER_ID,
                    byteArrayOf('B'.code.toByte(), 'H'.code.toByte(), 'A'.code.toByte(), 'I'.code.toByte()),
                    byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte())
                )
                .build()

            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
                .setReportDelay(0)
                .build()

            scanner?.startScan(listOf(filter), settings, scanCallback)
            isScanning = true
        } catch (e: Exception) {}
    }

    private fun stopBleScanning() {
        try {
            if (isScanning && scanner != null) {
                scanner?.stopScan(scanCallback)
            }
        } catch (e: Exception) {}
        isScanning = false
        scanner = null
    }

    private fun startNetworkSync() {
        if (isSyncRunning) return
        isSyncRunning = true

        val syncRunnable = object : Runnable {
            override fun run() {
                if (!isSyncRunning) return
                executor.execute {
                    pollActiveEmergencies()
                }
                mainHandler.postDelayed(this, SYNC_INTERVAL_MS)
            }
        }
        mainHandler.post(syncRunnable)
    }

    private fun pollActiveEmergencies() {
        try {
            val url = URL("$apiBaseUrl/emergencies/active")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 2500
            conn.readTimeout = 2500
            conn.requestMethod = "GET"

            if (conn.responseCode == 200) {
                val reader = BufferedReader(InputStreamReader(conn.inputStream))
                val jsonText = reader.readText()
                reader.close()

                val array = JSONArray(jsonText)
                for (i in 0 until array.length()) {
                    val item = array.getJSONObject(i)
                    val emId = item.optString("id", "")
                    val sender = item.optString("sender_id", "")
                    val status = item.optString("status", "")

                    if (sender.isEmpty() || (myDeviceId.isNotEmpty() && sender.equals(myDeviceId, ignoreCase = true))) {
                        continue
                    }

                    if (status.equals("ACTIVE", ignoreCase = true)) {
                        val alertKey = if (emId.isNotEmpty()) emId else "BHAI-$sender"
                        showEmergencyNotification(
                            emergencyId = alertKey,
                            senderId = sender,
                            title = "🚨 ACTIVE EMERGENCY NEARBY",
                            body = "A nearby user ($sender) is in distress. Tap to view location and help."
                        )
                    }
                }
            }
            conn.disconnect()
        } catch (e: Exception) {}
    }

    private fun showEmergencyNotification(emergencyId: String, senderId: String, title: String, body: String) {
        val now = System.currentTimeMillis()
        val last = handledEmergencies[emergencyId] ?: 0L
        if (now - last < 15000L) return // 15s debounce
        handledEmergencies[emergencyId] = now

        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("route", "emergency")
                putExtra("emergency_id", emergencyId)
                putExtra("sender_id", senderId)
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                (emergencyId.hashCode() and 0x7FFFFFFF) % 10000 + 200,
                launchIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            val builder = NotificationCompat.Builder(this, EMERGENCY_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setVibrate(longArrayOf(0, 500, 200, 500, 200, 800))
                .setSound(soundUri)
                .setContentIntent(pendingIntent)
                .setFullScreenIntent(pendingIntent, true)
                .setAutoCancel(true)

            notificationManager.notify(202, builder.build())
        } catch (e: Exception) {}
    }

    private fun buildGuardNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, GUARD_CHANNEL_ID)
            .setContentTitle("BHAI Emergency Guard Active")
            .setContentText("Listening for nearby distress signals & emergency alerts.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

            // 1. Silent persistent guard channel
            val guardChannel = NotificationChannel(
                GUARD_CHANNEL_ID,
                "BHAI Emergency Background Guard",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Bluetooth & network emergency discovery alive in background."
                setShowBadge(false)
            }
            manager.createNotificationChannel(guardChannel)

            // 2. High-priority emergency alarm channel
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()

            val emergencyChannel = NotificationChannel(
                EMERGENCY_CHANNEL_ID,
                "BHAI High-Priority Emergency Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical alerts when a nearby person triggers SOS"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 800)
                setSound(soundUri, audioAttributes)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(emergencyChannel)

            // 3. High-priority chat channel
            val chatChannel = NotificationChannel(
                CHAT_CHANNEL_ID,
                "BHAI Emergency Chat",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Real-time communication during emergency operations."
                enableVibration(true)
            }
            manager.createNotificationChannel(chatChannel)
        }
    }

    private fun bytesToHex(bytes: ByteArray, offset: Int, length: Int): String {
        val sb = StringBuilder()
        for (i in offset until (offset + length).coerceAtMost(bytes.size)) {
            sb.append(String.format("%02X", bytes[i]))
        }
        return sb.toString()
    }
}
