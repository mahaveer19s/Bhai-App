package com.bhai.bhai_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import androidx.core.app.NotificationCompat
import android.media.RingtoneManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper

/**
 * Real, production-grade Android BLE SOS & Nearby-Peer Transport.
 * Transmits compact binary packets fitting standard 31-byte legacy BLE advertising limits:
 * - Magic: "BHAI" (4 bytes)
 * - Type: 0x01 (Presence), 0x02 (Emergency Alert), 0x03 (Alert ACK), 0x04 (Direct BLE Chat)
 * - Sender Ephemeral ID (4 bytes)
 * - Target Ephemeral ID (4 bytes)
 * - Payload / Coordinates / Text (8 bytes)
 * - Flag & Sequence / Nonce (2 bytes)
 */
class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.bhai.app/ble_emergency"
    private val eventChannelName = "com.bhai.app/ble_emergency_events"
    private val manufacturerId = 0xFFFF

    private var advertiser: BluetoothLeAdvertiser? = null
    private var scanner: BluetoothLeScanner? = null
    private var eventSink: EventChannel.EventSink? = null
    private var methodChannel: MethodChannel? = null
    private var currentAdvertiseCallback: AdvertiseCallback? = null
    private var isScanningActive = false
    private var currentMyDeviceId: String = ""
    private val lastNativeAlertTimestamps = mutableMapOf<String, Long>()
    private var launchNotificationPayload: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        extractNotificationPayload(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractNotificationPayload(intent)
        launchNotificationPayload?.let { payload ->
            runOnUiThread {
                methodChannel?.invokeMethod("onNotificationOpened", payload)
            }
        }
    }

    private fun extractNotificationPayload(intent: Intent?) {
        if (intent == null) return
        val route = intent.getStringExtra("route")
        if (route != null) {
            val payload = mutableMapOf<String, Any?>("route" to route)
            intent.getStringExtra("emergency_id")?.let { payload["emergency_id"] = it }
            intent.getStringExtra("conversation_id")?.let { payload["conversation_id"] = it }
            intent.getStringExtra("sender_id")?.let { payload["sender_id"] = it }
            launchNotificationPayload = payload
        }
    }

    // Native High-Intensity Siren Generator
    private var toneGenerator: ToneGenerator? = null
    private var sirenHandler: Handler? = null
    private var isSirenPlaying = false
    private var sirenStep = 0

    private val sirenRunnable = object : Runnable {
        override fun run() {
            if (!isSirenPlaying) return
            try {
                if (toneGenerator == null) {
                    toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
                }
                val tone = if (sirenStep % 2 == 0) ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK else ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD
                toneGenerator?.startTone(tone, 450)
                sirenStep++
            } catch (e: Exception) {}
            sirenHandler?.postDelayed(this, 500)
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val record = result.scanRecord ?: return
            val rawBytes = record.getManufacturerSpecificData(manufacturerId) ?: return

            // Verify "BHAI" magic header (0x42, 0x48, 0x41, 0x49)
            if (rawBytes.size >= 5 &&
                rawBytes[0] == 'B'.code.toByte() &&
                rawBytes[1] == 'H'.code.toByte() &&
                rawBytes[2] == 'A'.code.toByte() &&
                rawBytes[3] == 'I'.code.toByte()
            ) {
                val type = rawBytes[4].toInt() and 0xFF
                val senderId = if (rawBytes.size >= 9) bytesToHex(rawBytes, 5, 4) else "UNKNOWN"
                val targetId = if (rawBytes.size >= 13) bytesToHex(rawBytes, 9, 4) else "00000000"

                // Self-packet hardware filter: The device that created the emergency must never receive its own alert
                if (currentMyDeviceId.isNotEmpty() && senderId.equals(currentMyDeviceId, ignoreCase = true)) {
                    return
                }

                var latitude: Double? = null
                var longitude: Double? = null
                var chatText: String? = null
                var messageId: Int = 0
                var chunkIndex: Int = 0
                var totalChunks: Int = 1
                val hasLocation = rawBytes.size >= 22 && rawBytes[21].toInt() == 1

                if (type == 4 && rawBytes.size >= 17) {
                    // Type 4: Direct BLE Framed Chat message payload
                    messageId = if (rawBytes.size >= 15) {
                        ((rawBytes[13].toInt() and 0xFF) shl 8) or (rawBytes[14].toInt() and 0xFF)
                    } else 0
                    val chunkInfo = if (rawBytes.size >= 16) rawBytes[15].toInt() and 0xFF else 0
                    chunkIndex = (chunkInfo shr 4) and 0x0F
                    totalChunks = chunkInfo and 0x0F
                    if (totalChunks == 0) totalChunks = 1

                    val textLen = (rawBytes.size - 17).coerceAtLeast(0).coerceAtMost(10)
                    if (textLen > 0) {
                        val textBytes = ByteArray(textLen)
                        System.arraycopy(rawBytes, 16, textBytes, 0, textLen)
                        chatText = String(textBytes, Charsets.UTF_8).trimEnd('\u0000', ' ')
                    }
                } else if (hasLocation && rawBytes.size >= 21) {
                    val latInt = (rawBytes[13].toInt() shl 24) or
                                 ((rawBytes[14].toInt() and 0xFF) shl 16) or
                                 ((rawBytes[15].toInt() and 0xFF) shl 8) or
                                 (rawBytes[16].toInt() and 0xFF)
                    val lonInt = (rawBytes[17].toInt() shl 24) or
                                 ((rawBytes[18].toInt() and 0xFF) shl 16) or
                                 ((rawBytes[19].toInt() and 0xFF) shl 8) or
                                 (rawBytes[20].toInt() and 0xFF)
                    latitude = latInt / 100000.0
                    longitude = lonInt / 100000.0
                }

                if (type == 2) {
                    showNativeEmergencyAlert(senderId, result.rssi)
                }

                runOnUiThread {
                    eventSink?.success(
                        mapOf(
                            "type" to type,
                            "senderId" to senderId,
                            "targetId" to targetId,
                            "rssi" to result.rssi,
                            "latitude" to latitude,
                            "longitude" to longitude,
                            "hasLocation" to hasLocation,
                            "chatText" to chatText,
                            "messageId" to messageId,
                            "chunkIndex" to chunkIndex,
                            "totalChunks" to totalChunks,
                            "detectedAt" to System.currentTimeMillis()
                        )
                    )
                }
            }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            results?.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
        }

        override fun onScanFailed(errorCode: Int) {
            runOnUiThread {
                eventSink?.error("scan_failed", "BLE scanning failed with code: $errorCode", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result -> handleBleCall(call, result) }
    }

    private fun handleBleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isBluetoothEnabled" -> {
                val adapter = bluetoothAdapter()
                result.success(adapter?.isEnabled == true)
            }
            "requestEnableBluetooth" -> {
                try {
                    val enableIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                    startActivity(enableIntent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("failed", e.message, null)
                }
            }
            "startAdvertising" -> {
                val type = call.argument<Int>("type") ?: 1
                val senderId = call.argument<String>("senderId") ?: "00000000"
                val targetId = call.argument<String>("targetId") ?: "00000000"
                val latitude = call.argument<Double>("latitude") ?: 0.0
                val longitude = call.argument<Double>("longitude") ?: 0.0
                val hasLocation = call.argument<Boolean>("hasLocation") ?: false
                val chatText = call.argument<String>("chatText")
                val messageId = call.argument<Int>("messageId") ?: 0
                val chunkIndex = call.argument<Int>("chunkIndex") ?: 0
                val totalChunks = call.argument<Int>("totalChunks") ?: 1
                startAdvertising(type, senderId, targetId, latitude, longitude, hasLocation, chatText, messageId, chunkIndex, totalChunks, result)
            }
            "stopAdvertising" -> {
                stopAdvertising()
                result.success(null)
            }
            "startScanning" -> startScanning(result)
            "stopScanning" -> {
                stopScanning()
                result.success(null)
            }
            "dialEmergency" -> {
                val number = call.argument<String>("number") ?: "112"
                startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")))
                result.success(null)
            }
            "setMyDeviceId" -> {
                currentMyDeviceId = call.argument<String>("deviceId") ?: ""
                BhaiBleService.myDeviceId = currentMyDeviceId
                result.success(true)
            }
            "getNotificationLaunchPayload" -> {
                val payload = launchNotificationPayload
                launchNotificationPayload = null
                result.success(payload)
            }
            "requestIgnoreBatteryOptimizations" -> {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                        if (pm != null && !pm.isIgnoringBatteryOptimizations(packageName)) {
                            val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "startBackgroundGuard" -> {
                try {
                    BhaiBleService.start(this)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("guard_failed", e.message, null)
                }
            }
            "stopBackgroundGuard" -> {
                try {
                    BhaiBleService.stop(this)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("guard_failed", e.message, null)
                }
            }
            "openGoogleMaps" -> {
                val lat = call.argument<Double>("latitude") ?: 0.0
                val lon = call.argument<Double>("longitude") ?: 0.0
                if (lat == 0.0 && lon == 0.0) {
                    result.error("INVALID_COORDINATES", "Coordinates not available (0.0, 0.0)", null)
                    return
                }
                var launched = false
                // 1. First attempt: Direct Google Maps Navigation turn-by-turn intent
                try {
                    val gmmIntentUri = Uri.parse("google.navigation:q=$lat,$lon&mode=d")
                    val mapIntent = Intent(Intent.ACTION_VIEW, gmmIntentUri).apply {
                        setPackage("com.google.android.apps.maps")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(mapIntent)
                    launched = true
                } catch (e1: Exception) {}

                // 2. Second attempt: Generic geo URI (opens any installed map: Google Maps, OsmAnd, Maps.me, etc.)
                if (!launched) {
                    try {
                        val geoUri = Uri.parse("geo:$lat,$lon?q=$lat,$lon(Bhai+Emergency+Location)")
                        val geoIntent = Intent(Intent.ACTION_VIEW, geoUri).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(geoIntent)
                        launched = true
                    } catch (e2: Exception) {}
                }

                // 3. Third attempt: Web Browser Google Maps route
                if (!launched) {
                    try {
                        val webUri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lon")
                        val browserIntent = Intent(Intent.ACTION_VIEW, webUri).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(browserIntent)
                        launched = true
                    } catch (e3: Exception) {}
                }

                if (launched) {
                    result.success(true)
                } else {
                    result.error("failed_to_open_maps", "Could not open map navigation", null)
                }
            }
            "startEmergencySiren" -> {
                try {
                    if (!isSirenPlaying) {
                        isSirenPlaying = true
                        sirenStep = 0
                        sirenHandler = Handler(Looper.getMainLooper())
                        sirenHandler?.post(sirenRunnable)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("siren_error", e.message, null)
                }
            }
            "stopEmergencySiren" -> {
                try {
                    isSirenPlaying = false
                    sirenHandler?.removeCallbacks(sirenRunnable)
                    sirenHandler = null
                    toneGenerator?.stopTone()
                    toneGenerator?.release()
                    toneGenerator = null
                    result.success(true)
                } catch (e: Exception) {
                    result.error("siren_error", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun showNativeEmergencyAlert(senderId: String, rssi: Int) {
        val now = System.currentTimeMillis()
        val last = lastNativeAlertTimestamps[senderId] ?: 0L
        if (now - last < 10000) return
        lastNativeAlertTimestamps[senderId] = now

        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val channelId = "bhai_emergency_high_priority"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .build()

                val channel = NotificationChannel(
                    channelId,
                    "BHAI High-Priority Emergency Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Critical alerts when a nearby person triggers SOS"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 800)
                    setSound(soundUri, audioAttributes)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                notificationManager.createNotificationChannel(channel)
            }

            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                202,
                launchIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            val builder = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("🚨 EMERGENCY ALERT NEARBY")
                .setContentText("A Bhai user ($senderId) needs immediate help! Tap to assist.")
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

    private fun bluetoothAdapter(): BluetoothAdapter? {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    private fun canUse(permission: String): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun canScan(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        } else {
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun encodeBhaiPayload(
        type: Int,
        senderId: String,
        targetId: String,
        latitude: Double,
        longitude: Double,
        hasLocation: Boolean,
        chatText: String?,
        messageId: Int,
        chunkIndex: Int,
        totalChunks: Int
    ): ByteArray {
        if (type == 4) {
            // Type 4: Direct BLE Framed Chat packet
            val textBytes = (chatText ?: "").toByteArray(Charsets.UTF_8)
            val chunkLen = textBytes.size.coerceAtMost(10)
            val payload = ByteArray(17 + chunkLen)
            payload[0] = 'B'.code.toByte()
            payload[1] = 'H'.code.toByte()
            payload[2] = 'A'.code.toByte()
            payload[3] = 'I'.code.toByte()
            payload[4] = 0x04.toByte()

            val senderBytes = hexToBytes(senderId, 4)
            System.arraycopy(senderBytes, 0, payload, 5, 4)

            val targetBytes = hexToBytes(targetId, 4)
            System.arraycopy(targetBytes, 0, payload, 9, 4)

            // Message ID (2 bytes)
            payload[13] = ((messageId shr 8) and 0xFF).toByte()
            payload[14] = (messageId and 0xFF).toByte()

            // Chunk info: upper 4 bits = chunkIndex, lower 4 bits = totalChunks
            val chunkByte = ((chunkIndex and 0x0F) shl 4) or (totalChunks and 0x0F)
            payload[15] = chunkByte.toByte()

            if (chunkLen > 0) {
                System.arraycopy(textBytes, 0, payload, 16, chunkLen)
            }
            payload[16 + chunkLen] = (System.currentTimeMillis() and 0xFF).toByte()
            return payload
        }

        val payload = ByteArray(23)
        // Magic "BHAI" (4 bytes)
        payload[0] = 'B'.code.toByte()
        payload[1] = 'H'.code.toByte()
        payload[2] = 'A'.code.toByte()
        payload[3] = 'I'.code.toByte()

        // Type (1 byte: 1=Presence, 2=Emergency SOS, 3=ACK)
        payload[4] = (type and 0xFF).toByte()

        // Sender ID (4 bytes)
        val senderBytes = hexToBytes(senderId, 4)
        System.arraycopy(senderBytes, 0, payload, 5, 4)

        // Target ID (4 bytes)
        val targetBytes = hexToBytes(targetId, 4)
        System.arraycopy(targetBytes, 0, payload, 9, 4)

        // Location payload: 4 bytes lat, 4 bytes lon, 1 byte flag
        if (hasLocation && (latitude != 0.0 || longitude != 0.0)) {
            val latInt = (latitude * 100000.0).toInt()
            payload[13] = ((latInt shr 24) and 0xFF).toByte()
            payload[14] = ((latInt shr 16) and 0xFF).toByte()
            payload[15] = ((latInt shr 8) and 0xFF).toByte()
            payload[16] = (latInt and 0xFF).toByte()

            val lonInt = (longitude * 100000.0).toInt()
            payload[17] = ((lonInt shr 24) and 0xFF).toByte()
            payload[18] = ((lonInt shr 16) and 0xFF).toByte()
            payload[19] = ((lonInt shr 8) and 0xFF).toByte()
            payload[20] = (lonInt and 0xFF).toByte()

            payload[21] = 1.toByte() // Location flag: Valid
        } else {
            payload[21] = 0.toByte() // Location flag: Not available
        }

        // Sequence / nonce (1 byte)
        payload[22] = (System.currentTimeMillis() and 0xFF).toByte()
        return payload
    }

    private fun startAdvertising(
        type: Int,
        senderId: String,
        targetId: String,
        latitude: Double,
        longitude: Double,
        hasLocation: Boolean,
        chatText: String? = null,
        messageId: Int = 0,
        chunkIndex: Int = 0,
        totalChunks: Int = 1,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            result.error("unsupported", "BLE advertising requires Android 5.0 or later", null)
            return
        }
        if (!canUse(Manifest.permission.BLUETOOTH_ADVERTISE)) {
            result.error("permission_denied", "Bluetooth advertise permission is required", null)
            return
        }
        val adapter = bluetoothAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("disabled", "Bluetooth is disabled", null)
            return
        }
        if (!adapter.isMultipleAdvertisementSupported) {
            result.error("unsupported", "This device does not support BLE peripheral advertising", null)
            return
        }

        stopAdvertising()

        advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            result.error("unavailable", "Bluetooth LE advertiser is unavailable", null)
            return
        }

        val payload = encodeBhaiPayload(type, senderId, targetId, latitude, longitude, hasLocation, chatText, messageId, chunkIndex, totalChunks)
        val settings = AdvertiseSettings.Builder()

            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .build()

        val data = AdvertiseData.Builder()
            .addManufacturerData(manufacturerId, payload)
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                // Advertising active
            }

            override fun onStartFailure(errorCode: Int) {
                runOnUiThread {
                    eventSink?.error("advertise_failed", "BLE advertising failed with code: $errorCode", null)
                }
            }
        }
        currentAdvertiseCallback = callback

        try {
            advertiser?.startAdvertising(settings, data, callback)
            result.success(null)
        } catch (e: Exception) {
            result.error("advertise_exception", e.message, null)
        }
    }

    private fun stopAdvertising() {
        try {
            if (currentAdvertiseCallback != null && advertiser != null && canUse(Manifest.permission.BLUETOOTH_ADVERTISE)) {
                advertiser?.stopAdvertising(currentAdvertiseCallback)
            }
        } catch (e: Exception) {}
        currentAdvertiseCallback = null
        advertiser = null
    }

    private fun startScanning(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            result.error("unsupported", "BLE scanning requires Android 5.0 or later", null)
            return
        }
        if (!canScan()) {
            result.error("permission_denied", "Bluetooth scan / Location permission is required", null)
            return
        }
        val adapter = bluetoothAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("disabled", "Bluetooth is disabled", null)
            return
        }

        scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            result.error("unavailable", "Bluetooth LE scanner is unavailable", null)
            return
        }

        if (isScanningActive) {
            result.success(null)
            return
        }

        // Hardware-level filtering for "BHAI" magic bytes in Manufacturer Data
        val filter = ScanFilter.Builder()
            .setManufacturerData(
                manufacturerId,
                byteArrayOf('B'.code.toByte(), 'H'.code.toByte(), 'A'.code.toByte(), 'I'.code.toByte()),
                byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte())
            )
            .build()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_BALANCED) // Low battery consumption for 24/7 background guard
            .setReportDelay(0)
            .build()

        try {
            scanner?.startScan(listOf(filter), settings, scanCallback)
            isScanningActive = true
            try {
                BhaiBleService.start(this)
            } catch (e: Exception) {}
            result.success(null)
        } catch (e: Exception) {
            result.error("scan_exception", e.message, null)
        }
    }

    private fun stopScanning() {
        try {
            if (isScanningActive && scanner != null && canUse(Manifest.permission.BLUETOOTH_SCAN)) {
                scanner?.stopScan(scanCallback)
            }
        } catch (e: Exception) {}
        try {
            BhaiBleService.stop(this)
        } catch (e: Exception) {}
        isScanningActive = false
        scanner = null
    }

    override fun onDestroy() {
        stopAdvertising()
        // Note: Do NOT stop BhaiBleService here so background emergency and push guard stay active when swiped from recents!
        super.onDestroy()
    }

    private fun hexToBytes(hex: String, length: Int): ByteArray {
        val clean = hex.replace("[^0-9A-Fa-f]".toRegex(), "").uppercase(Locale.ROOT)
        val result = ByteArray(length)
        for (i in 0 until length) {
            if (i * 2 + 1 < clean.length) {
                result[i] = clean.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            } else {
                result[i] = 0
            }
        }
        return result
    }

    private fun bytesToHex(bytes: ByteArray, offset: Int, length: Int): String {
        val sb = java.lang.StringBuilder()
        for (i in offset until (offset + length).coerceAtMost(bytes.size)) {
            sb.append(String.format("%02X", bytes[i]))
        }
        return sb.toString()
    }
}
