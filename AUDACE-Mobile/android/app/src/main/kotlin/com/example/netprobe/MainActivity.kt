// android/app/src/main/kotlin/com/example/netprobe/MainActivity.kt
package com.example.netprobe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // TelephonyPlugin (enregistré dans GeneratedPluginRegistrant) gère :
    //   cm.art.netprobe/telephony → getOperatorInfo, getSignalMetrics,
    //                               getWifiInfo, getConnectionType, launchUrl
    // Il est disponible dans le FlutterEngine principal ET dans le background engine.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
    }
}
