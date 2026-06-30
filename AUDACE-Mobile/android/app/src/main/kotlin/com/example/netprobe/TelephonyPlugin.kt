// android/app/src/main/kotlin/com/example/netprobe/TelephonyPlugin.kt
package com.example.netprobe

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.telephony.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Plugin enregistré dans tous les FlutterEngine (principal + background).
 * Utilise applicationContext → fonctionne sans Activity (background service inclus).
 * ActivityAware → launchUrl disponible uniquement en foreground.
 */
class TelephonyPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    // ── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "cm.art.netprobe/telephony")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ── ActivityAware ────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding)                  { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges()                              { activity = null }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding)      { activity = b.activity }
    override fun onDetachedFromActivity()                                              { activity = null }

    // ── MethodCallHandler ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getSignalMetrics"  -> result.success(getSignalMetrics())
            "getOperatorInfo"   -> result.success(getOperatorInfo())
            "getWifiInfo"       -> result.success(getWifiInfo())
            "getConnectionType" -> result.success(getConnectionType())
            "launchUrl" -> {
                val url = call.argument<String>("url")
                val act = activity
                when {
                    url == null -> result.error("INVALID_URL", "URL manquante", null)
                    act == null -> result.error("NO_ACTIVITY", "Impossible de lancer l'URL en arrière-plan", null)
                    else -> { act.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))); result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun Int.validOrNull(): Double? =
        if (this == Int.MIN_VALUE || this == Int.MAX_VALUE || this == Int.MAX_VALUE - 1
            || this < -200 || this > 200) null else this.toDouble()

    private fun Long.validOrNull(): String? =
        if (this == Long.MIN_VALUE || this == Long.MAX_VALUE) null else this.toString()

    // ── 1. Opérateur SIM ─────────────────────────────────────────────────────

    private fun getOperatorInfo(): Map<String, Any?> {
        val tm  = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val simOp = tm.simOperator ?: ""
        val netOp = tm.networkOperator ?: ""
        val simName = tm.simOperatorName?.trim()?.takeIf { it.isNotEmpty() }
        val netName = tm.networkOperatorName?.trim()?.takeIf { it.isNotEmpty() }
        val operatorName = simName ?: netName ?: "Inconnu"
        val mcc = simOp.take(3).ifEmpty { netOp.take(3) }.ifEmpty { "624" }
        val mnc = simOp.drop(3).ifEmpty { netOp.drop(3) }.ifEmpty { "??" }
        val dataType = try { tm.dataNetworkType } catch (e: Exception) { -1 }
        return mapOf(
            "operatorName"    to operatorName,
            "simMcc"          to mcc,
            "simMnc"          to mnc,
            "simCountryIso"   to (tm.simCountryIso?.uppercase() ?: "CM"),
            "isRoaming"       to tm.isNetworkRoaming,
            "dataNetworkType" to dataType,
            "simState"        to tm.simState,
        )
    }

    // ── 2. Signal radio ──────────────────────────────────────────────────────

    private fun getSignalMetrics(): Map<String, Any?> {
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val metrics = mutableMapOf<String, Any?>()
        try {
            val cellInfoList = tm.allCellInfo
                ?: return mapOf("available" to false, "error" to "allCellInfo null")
            val registered = cellInfoList.firstOrNull { it.isRegistered }
                ?: return mapOf("available" to false, "error" to "Aucune cellule enregistrée")
            metrics["available"] = true
            when (registered) {
                is CellInfoLte -> {
                    val ss = registered.cellSignalStrength; val ci = registered.cellIdentity
                    metrics["networkType"]    = "LTE"
                    metrics["rsrp"]           = ss.rsrp.validOrNull()
                    metrics["rsrq"]           = ss.rsrq.validOrNull()
                    metrics["rssi"]           = if (Build.VERSION.SDK_INT >= 29) ss.rssi.validOrNull() else null
                    metrics["sinr"]           = ss.rssnr.takeIf { it != Int.MIN_VALUE && it != Int.MAX_VALUE && it != Int.MAX_VALUE - 1 && it in -200..200 }?.toDouble()
                    metrics["cellId"]         = ci.ci.takeIf { it != Int.MIN_VALUE && it > 0 }?.toString()
                    metrics["tac"]            = ci.tac.takeIf { it != Int.MIN_VALUE && it > 0 }?.toString()
                    metrics["signalStrength"] = ss.level; metrics["dbm"] = ss.dbm
                }
                is CellInfoNr -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val ss = registered.cellSignalStrength as CellSignalStrengthNr
                        val ci = registered.cellIdentity as CellIdentityNr
                        metrics["networkType"]    = "NR"
                        metrics["rsrp"]           = ss.ssRsrp.validOrNull(); metrics["rsrq"] = ss.ssRsrq.validOrNull()
                        metrics["sinr"]           = ss.ssSinr.validOrNull(); metrics["cellId"] = ci.nci.validOrNull()
                        metrics["tac"]            = ci.tac.validOrNull()
                        metrics["signalStrength"] = ss.level; metrics["dbm"] = ss.dbm
                    }
                }
                is CellInfoWcdma -> {
                    val ss = registered.cellSignalStrength; val ci = registered.cellIdentity
                    metrics["networkType"]    = "WCDMA"; metrics["rssi"] = ss.dbm.validOrNull()
                    metrics["cellId"]         = ci.cid.takeIf { it != Int.MIN_VALUE && it > 0 }?.toString()
                    metrics["lac"]            = ci.lac.takeIf { it != Int.MIN_VALUE && it > 0 }?.toString()
                    metrics["signalStrength"] = ss.level; metrics["dbm"] = ss.dbm
                }
                is CellInfoGsm -> {
                    val ss = registered.cellSignalStrength; val ci = registered.cellIdentity
                    metrics["networkType"]    = "GSM"; metrics["rssi"] = ss.dbm.validOrNull()
                    metrics["cellId"]         = ci.cid.takeIf { it != Int.MIN_VALUE && it > 0 }?.toString()
                    metrics["lac"]            = ci.lac.takeIf { it != Int.MIN_VALUE && it > 0 }?.toString()
                    metrics["signalStrength"] = ss.level; metrics["dbm"] = ss.dbm
                }
            }
        } catch (e: SecurityException) {
            metrics["available"] = false; metrics["error"] = "Permission READ_PHONE_STATE manquante"
        } catch (e: Exception) {
            metrics["available"] = false; metrics["error"] = e.message
        }
        return metrics
    }

    // ── 3. WiFi ──────────────────────────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun getWifiInfo(): Map<String, Any?> {
        val wm = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wm.isWifiEnabled) return mapOf("enabled" to false)
        val info = wm.connectionInfo; val dhcp = wm.dhcpInfo
        fun intToIp(ip: Int) = "${ip and 0xFF}.${(ip shr 8) and 0xFF}.${(ip shr 16) and 0xFF}.${(ip shr 24) and 0xFF}"
        val rssi = info.rssi; val freq = info.frequency
        return mapOf(
            "enabled" to true,
            "ssid"            to (info.ssid?.removeSurrounding("\"") ?: "Inconnu"),
            "bssid"           to (info.bssid ?: "Inconnu"),
            "rssi_dbm"        to rssi,
            "quality_pct"     to ((rssi + 90).coerceIn(0, 60) * 100.0 / 60).toInt(),
            "link_speed_mbps" to info.linkSpeed,
            "frequency_mhz"   to freq,
            "band"            to when { freq in 2400..2500 -> "2.4 GHz"; freq in 4900..5900 -> "5 GHz"; freq >= 5925 -> "6 GHz"; else -> "Inconnu" },
            "ip_address"      to intToIp(info.ipAddress),
            "gateway"         to intToIp(dhcp.gateway),
        )
    }

    // ── 4. Type de connexion ─────────────────────────────────────────────────

    private fun getConnectionType(): Map<String, Any?> {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
            mapOf(
                "isConnected" to (caps != null),
                "isWifi"      to (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true),
                "isMobile"    to (caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true),
                "isValidated" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            )
        } else {
            @Suppress("DEPRECATION")
            val info = cm.activeNetworkInfo
            mapOf(
                "isConnected" to (info?.isConnected == true),
                "isWifi"      to (info?.type == ConnectivityManager.TYPE_WIFI),
                "isMobile"    to (info?.type == ConnectivityManager.TYPE_MOBILE),
            )
        }
    }
}
