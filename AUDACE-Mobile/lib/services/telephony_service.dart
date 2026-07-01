// Service de communication avec le code natif Android pour les données téléphoniques.
// Utilise un MethodChannel Dart → Kotlin pour accéder aux APIs Android restreintes :
// TelephonyManager, WifiManager, ConnectivityManager.

import 'package:flutter/services.dart';
import '../models/network_metrics.dart';

class TelephonyService {
  // Canal de communication avec le code natif Kotlin
  // Nom défini dans MainActivity.kt (ou MethodChannelHandler.kt)
  static const _channel = MethodChannel('cm.art.netprobe/telephony');

  // ── Informations de l'opérateur depuis la SIM ─────────────────────────────
  // Lit le nom de l'opérateur, MCC, MNC, pays et statut d'itinérance
  Future<OperatorInfo> getOperatorInfo() async {
    try {
      final Map<dynamic, dynamic> data = await _channel.invokeMethod(
        'getOperatorInfo', // Méthode Kotlin correspondante
      );

      // Lit le nom de l'opérateur — filtre les chaînes vides
      final name =
          (data['operatorName'] as String?)?.trim().takeIf(
            (s) => s.isNotEmpty,
          ) ??
          'Inconnu'; // Fallback si SIM absente ou illisible

      return OperatorInfo(
        name:            name,
        mcc:             data['simMcc']        as String? ?? '624',   // 624 = Cameroun
        mnc:             data['simMnc']        as String? ?? '??',
        countryIso:      data['simCountryIso'] as String? ?? 'CM',
        isRoaming:       data['isRoaming']     as bool?   ?? false,
        // Type de réseau données (LTE, 5G…) codé en entier Android
        dataNetworkType: _parseNetworkTypeInt(data['dataNetworkType'] as int?),
      );
    } catch (_) {
      // Erreur MethodChannel (permission refusée, SIM absente, isolat background…)
      return const OperatorInfo(
        name: 'Inconnu', mcc: '624', mnc: '??',
        countryIso: 'CM', isRoaming: false,
        dataNetworkType: NetworkGeneration.unknown,
      );
    }
  }

  // ── Signal radio cellulaire (RSRP, RSRQ, RSSI, SINR, Cell ID) ─────────────
  // Lit les métriques radio depuis CellInfoLte / CellInfoNr via TelephonyManager
  Future<RadioSignalMetrics> getRadioSignalMetrics() async {
    try {
      final Map<dynamic, dynamic> data = await _channel.invokeMethod(
        'getSignalMetrics',
      );

      // Si Android n'a pas pu lire le signal (permission refusée, pas de cell info)
      if (data['available'] == false || data['error'] != null) {
        return RadioSignalMetrics(
          networkType: NetworkGeneration.unknown,
          unavailableReason:
              data['error'] as String? ?? 'Signal radio non disponible',
        );
      }

      return RadioSignalMetrics(
        rsrp:           (data['rsrp']           as num?)?.toDouble(), // dBm (ex: -85)
        rsrq:           (data['rsrq']           as num?)?.toDouble(), // dB  (ex: -10)
        rssi:           (data['rssi']           as num?)?.toDouble(), // dBm
        sinr:           (data['sinr']           as num?)?.toDouble(), // dB
        cellId:         data['cellId']          as String?,           // Identifiant cellule
        lac:            data['lac']             as String?,           // Location Area Code (2G/3G)
        tac:            data['tac']             as String?,           // Tracking Area Code (4G/5G)
        networkType:    _parseNetworkTypeString(data['networkType'] as String?), // Type réseau
        signalStrength: (data['signalStrength'] as num?)?.toInt(),    // 0–4 barres Android
      );
    } catch (_) {
      // En mode background, TelephonyManager peut être inaccessible
      return RadioSignalMetrics(
        networkType: NetworkGeneration.unknown,
        unavailableReason: 'Signal indisponible (background)',
      );
    }
  }

  // ── Informations WiFi (SSID, BSSID, RSSI, vitesse de lien, fréquence) ─────
  // Retourne null si le WiFi est désactivé ou non connecté
  Future<WifiInfo?> getWifiInfo() async {
    try {
      final Map<dynamic, dynamic> data = await _channel.invokeMethod(
        'getWifiInfo',
      );

      if (data['enabled'] == false) return null; // WiFi éteint

      return WifiInfo(
        ssid:          data['ssid']          as String? ?? 'Inconnu',
        bssid:         data['bssid']         as String? ?? 'Inconnu', // MAC du point d'accès
        rssiDbm:       (data['rssi_dbm']       as num?)?.toInt() ?? 0,  // Signal WiFi en dBm
        qualityPct:    (data['quality_pct']    as num?)?.toInt() ?? 0,  // Qualité 0–100%
        linkSpeedMbps: (data['link_speed_mbps'] as num?)?.toInt() ?? 0, // Vitesse de lien
        frequencyMhz:  (data['frequency_mhz']  as num?)?.toInt() ?? 0,  // Fréquence (2400/5000 MHz)
        band:          data['band']           as String? ?? 'Inconnu', // "2.4 GHz" ou "5 GHz"
        ipAddress:     data['ip_address']     as String? ?? '0.0.0.0',
        gateway:       data['gateway']        as String? ?? '0.0.0.0',
      );
    } catch (_) {
      return null;
    }
  }

  // ── Type de connexion active (WiFi / Mobile / Ethernet / Aucun) ───────────
  Future<ActiveConnectionType> getConnectionType() async {
    try {
      final Map<dynamic, dynamic> data = await _channel.invokeMethod(
        'getConnectionType',
      );

      if (data['isWifi']      == true)  return ActiveConnectionType.wifi;
      if (data['isMobile']    == true)  return ActiveConnectionType.mobile;
      if (data['isConnected'] == false) return ActiveConnectionType.none;
      return ActiveConnectionType.unknown;
    } catch (_) {
      return ActiveConnectionType.unknown;
    }
  }

  // ── Conversion du nom de type réseau (String natif Kotlin) en enum ─────────
  // Les chaînes correspondent aux noms définis dans MethodChannelHandler.kt
  NetworkGeneration _parseNetworkTypeString(String? type) => switch (type) {
    'GSM'              => NetworkGeneration.gsm,
    'EDGE'             => NetworkGeneration.edge,
    'WCDMA' || 'HSPA' => NetworkGeneration.hspa,
    'HSPAP'            => NetworkGeneration.hspaPlus,
    'LTE'              => NetworkGeneration.lte,
    'LTE_CA'           => NetworkGeneration.lteAdvanced,
    'NR'               => NetworkGeneration.nr5g,
    _                  => NetworkGeneration.unknown,
  };

  // ── Conversion de l'entier TelephonyManager.NETWORK_TYPE_* en enum ─────────
  // Constants Android : https://developer.android.com/reference/android/telephony/TelephonyManager
  NetworkGeneration _parseNetworkTypeInt(int? type) => switch (type) {
    1 || 2                  => NetworkGeneration.gsm,        // GPRS, EDGE
    3 || 8 || 9 || 10 || 15 => NetworkGeneration.hspa,       // UMTS, HSDPA, HSUPA, HSPA, HSPA+
    13                      => NetworkGeneration.lte,          // LTE
    19                      => NetworkGeneration.lteAdvanced,  // LTE CA
    20                      => NetworkGeneration.nr5g,         // NR (5G)
    _                       => NetworkGeneration.unknown,
  };
}

// ─── Extension utilitaire sur String ─────────────────────────────────────────
extension _StringTakeIf on String {
  // Retourne this si le prédicat est vrai, sinon null
  // Utilisé pour filtrer les chaînes vides de l'opérateur
  String? takeIf(bool Function(String) predicate) =>
      predicate(this) ? this : null;
}

// ─── Modèles de données téléphoniques ────────────────────────────────────────

// Informations de l'opérateur SIM
class OperatorInfo {
  final String name;           // Nom de l'opérateur (ex: "MTN Cameroon")
  final String mcc;            // Mobile Country Code (ex: "624" pour Cameroun)
  final String mnc;            // Mobile Network Code (ex: "02" pour MTN)
  final String countryIso;     // Code pays ISO 3166-1 (ex: "CM")
  final bool isRoaming;        // true si l'appareil est en itinérance
  final NetworkGeneration dataNetworkType; // Type de réseau données (4G, 5G…)

  const OperatorInfo({
    required this.name,
    required this.mcc,
    required this.mnc,
    required this.countryIso,
    required this.isRoaming,
    required this.dataNetworkType,
  });
}

// Informations du réseau WiFi connecté
class WifiInfo {
  final String ssid;          // Nom du réseau WiFi (ex: "Moov_Home")
  final String bssid;         // Adresse MAC du point d'accès (ex: "AA:BB:CC:DD:EE:FF")
  final int rssiDbm;          // Force du signal WiFi en dBm (ex: -65)
  final int qualityPct;       // Qualité calculée 0–100% (ex: 70)
  final int linkSpeedMbps;    // Vitesse de lien négociée en Mbps (ex: 144)
  final int frequencyMhz;     // Fréquence en MHz (2412 = 2.4GHz, 5180 = 5GHz)
  final String band;          // Bande : "2.4 GHz" ou "5 GHz"
  final String ipAddress;     // Adresse IP de l'appareil sur le réseau local
  final String gateway;       // Adresse IP de la passerelle (routeur)

  const WifiInfo({
    required this.ssid,
    required this.bssid,
    required this.rssiDbm,
    required this.qualityPct,
    required this.linkSpeedMbps,
    required this.frequencyMhz,
    required this.band,
    required this.ipAddress,
    required this.gateway,
  });
}

// Type de connexion réseau active sur l'appareil
enum ActiveConnectionType { wifi, mobile, ethernet, none, unknown }
