package com.sbc.sbc_contacts

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAlertsChannel()
    }

    /**
     * The channel every push lands in (the manifest names it as FCM's default,
     * and the backend sends with it). High importance so a new request or
     * message shows as a heads-up banner. Creating it again is a no-op.
     */
    private fun createAlertsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "sbc_alerts",
            "Alertes",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Nouvelles demandes, réponses, messages et membres qui t'enregistrent"
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
