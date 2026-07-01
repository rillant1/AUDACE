// lib/services/metrics_service.dart
// Service principal de collecte de toutes les métriques réseau.
// Orchestre 14 étapes de collecte (permissions → GPS → signal → débit → QoE)
// et retourne un objet NetworkMetrics complet prêt à être sérialisé et envoyé.

import 'dart:io';
import 'dart:math' as math;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dart_ping/dart_ping.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/network_metrics.dart';
import 'telephony_service.dart';
import 'permission_service.dart';
import 'location_service.dart';
import 'sync_service.dart';
import 'security_crypto_engine.dart';
import 'wifi_operator_service.dart';
import 'last_known_context.dart';

class MetricsService {
  // Singleton — une seule instance dans toute l'application
  static final MetricsService _instance = MetricsService._internal();
  factory MetricsService() => _instance;
  MetricsService._internal();

  // Services nécessaires à la collecte
  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final TelephonyService _telephony = TelephonyService();
  final PermissionService _permissions = PermissionService();
  final LocationService _location = LocationService();
  final SyncService _sync = SyncService();
  final SecurityCryptoEngine _crypto = SecurityCryptoEngine();

  // ── Constantes de configuration des tests ────────────────────────────────
  static const String _referenceUrl = 'https://www.art.cm'; // URL de référence QoE
  static const String _pingHost = '8.8.8.8';               // DNS Google (toujours joignable)
  // Ping count = 3 en mode test (10 en production)
  // TODO: remettre _pingCount=10, _downloadTimeout=60s, _uploadTimeout=45s en prod
  static const int _pingCount = 3;
  static const _downloadTimeout = Duration(seconds: 15);
  static const _uploadTimeout   = Duration(seconds: 10);
  static const _browsingTimeout = Duration(seconds: 10);
  static const _headTimeout     = Duration(seconds: 8);
  // Cloudflare : 500 Ko de données aléatoires → mesure du débit descendant
  static const _downloadUrl = 'https://speed.cloudflare.com/__down?bytes=500000';
  static const _uploadSize  = 100000; // 100 Ko de payload montant

  // ── Collecte complète des métriques (14 étapes) ───────────────────────────
  // onProgress : callback pour mettre à jour l'UI avec la progression (étape, 0.0–1.0)
  Future<NetworkMetrics> collectAllMetrics({
    void Function(String step, double progress)? onProgress,
  }) async {
    onProgress?.call('Initialisation...', 0.0);
    // Horodatage UTC de la collecte (format ISO 8601)
    final timestamp = DateFormat(
      "yyyy-MM-dd'T'HH:mm:ss'Z'",
    ).format(DateTime.now().toUtc());

    // ── Étape 1 : Permissions ─────────────────────────────────────────────
    onProgress?.call('Demande des permissions...', 0.05);
    final permResult = await _permissions.requestAllPermissions();

    // ── Étape 2 : Infos appareil ──────────────────────────────────────────
    onProgress?.call('Lecture des infos appareil...', 0.10);
    final deviceData = await _getDeviceInfo();

    // ── Étape 3 : Batterie ────────────────────────────────────────────────
    // Peut lever MissingPluginException dans un isolat background (service)
    onProgress?.call('Vérification batterie...', 0.14);
    int batteryLevel  = -1;           // -1 = inconnu
    BatteryState batteryState = BatteryState.unknown;
    try {
      batteryLevel  = await _battery.batteryLevel;  // 0–100 %
      batteryState  = await _battery.batteryState;  // charging, discharging, full, unknown
    } catch (_) {} // Silencieux : en background, ce plugin ne fonctionne pas

    // ── Étape 4 : Type de connexion ───────────────────────────────────────
    onProgress?.call('Détection du réseau...', 0.18);
    ActiveConnectionType connType = ActiveConnectionType.none;
    try {
      connType = await _telephony.getConnectionType();
    } catch (_) {}
    final isWifi = connType == ActiveConnectionType.wifi;
    // Inclut unknown : certains modems ou VPN font retourner "unknown" alors que
    // l'appareil est réellement connecté via WiFi. Tenter la détection WiFi dans
    // ce cas est sans risque — si aucune méthode ne trouve d'opérateur, on garde
    // le nom SIM.
    final shouldDetectWifiOp = isWifi || connType == ActiveConnectionType.unknown;

    // ── Étape 5 : Identification de l'opérateur ───────────────────────────
    onProgress?.call('Lecture de la carte SIM...', 0.22);
    OperatorInfo operatorInfo = const OperatorInfo(
      name: '', mcc: '', mnc: '', countryIso: '',
      isRoaming: false, dataNetworkType: NetworkGeneration.unknown,
    );
    try {
      operatorInfo = await _telephony.getOperatorInfo();
    } catch (_) {}

    String operatorName = operatorInfo.name;
    if (shouldDetectWifiOp) {
      // Sur WiFi, la SIM peut appartenir à un opérateur différent de la box 4G.
      // On interroge d'abord l'API locale du modem Huawei (la plus fiable),
      // puis l'ASN de l'IP publique, puis le SSID.
      onProgress?.call('Identification de l\'opérateur WiFi...', 0.25);
      final wifiOp = await WifiOperatorService().detectOperator();
      // N'écrase le nom SIM que si une méthode concrète a réussi
      if (wifiOp.source != WifiDetectionSource.inconnu) {
        operatorName = wifiOp.name;
      }
    }

    // Fallback background : si le canal natif n'est pas disponible (isolat background),
    // réutilise le dernier opérateur connu sauvegardé lors de la dernière collecte foreground.
    if (operatorName.isEmpty || operatorName == 'Inconnu') {
      final cached = await LastKnownContext.getOperator();
      if (cached.isNotEmpty) {
        operatorName = cached;
        operatorInfo = OperatorInfo(
          name:        cached,
          mcc:         await LastKnownContext.getMcc(),
          mnc:         await LastKnownContext.getMnc(),
          countryIso:  operatorInfo.countryIso.isEmpty ? 'CM' : operatorInfo.countryIso,
          isRoaming:   operatorInfo.isRoaming,
          dataNetworkType: operatorInfo.dataNetworkType,
        );
      }
    }

    // ── Étape 6 : GPS ─────────────────────────────────────────────────────
    onProgress?.call('Acquisition de la position GPS...', 0.27);
    LocationResult? locationResult;
    if (permResult.locationGranted) {
      locationResult = await _location.getCurrentLocation();
    }
    // Fallback GPS background : réutilise la dernière position connue (foreground)
    if (locationResult == null) {
      final lat = await LastKnownContext.getLat();
      final lon = await LastKnownContext.getLon();
      final h3  = await LastKnownContext.getH3();
      if (lat != null && lon != null && h3 != null) {
        locationResult = LocationResult(
          latitude:  lat,
          longitude: lon,
          accuracy:  999.0, // Position mise en cache — précision inconnue
          h3Index:   h3,
        );
      }
    }

    // ── Étape 7 : Signal radio cellulaire ─────────────────────────────────
    onProgress?.call(
      isWifi ? 'Signal radio (WiFi actif)...' : 'Lecture du signal radio...',
      0.33,
    );
    RadioSignalMetrics radioMetrics = const RadioSignalMetrics();
    try {
      radioMetrics = await _telephony.getRadioSignalMetrics();
    } catch (_) {}

    // ── Étape 8 : Infos WiFi (uniquement si connecté en WiFi) ─────────────
    WifiSignalMetrics? wifiMetrics;
    if (isWifi) {
      onProgress?.call('Lecture des infos WiFi...', 0.38);
      final wifiInfo = await _telephony.getWifiInfo();
      if (wifiInfo != null) {
        wifiMetrics = WifiSignalMetrics(
          ssid:          wifiInfo.ssid,
          bssid:         wifiInfo.bssid,
          rssiDbm:       wifiInfo.rssiDbm,
          qualityPct:    wifiInfo.qualityPct,
          linkSpeedMbps: wifiInfo.linkSpeedMbps,
          frequencyMhz:  wifiInfo.frequencyMhz,
          band:          wifiInfo.band,
          ipAddress:     wifiInfo.ipAddress,
          gateway:       wifiInfo.gateway,
        );
      }
    }

    // ── Étape 9 : Ping (latence + gigue + perte de paquets) ──────────────
    onProgress?.call('Mesure de la latence (ping)...', 0.44);
    final pingResult = await _measurePing();

    // ── Étape 10 : Débit descendant (download) ────────────────────────────
    // Cloudflare : télécharge 500 Ko et mesure le temps
    onProgress?.call('Test du débit descendant (2 MB)...', 0.57);
    final downloadMbps = await _measureDownload();

    // ── Étape 11 : Débit montant (upload) ────────────────────────────────
    // Envoie 100 Ko vers Cloudflare et mesure le temps
    onProgress?.call('Test du débit montant (500 Ko)...', 0.70);
    final uploadMbps = await _measureUpload();

    // ── Étape 12 : QoE (qualité d'expérience utilisateur) ────────────────
    // GET art.cm + HEAD google/orange/mtn
    onProgress?.call('Test de navigation web...', 0.82);
    final qoeResult = await _measureQoE();

    // ── Étape 13 : Assemblage du rapport NetworkMetrics ───────────────────
    onProgress?.call('Assemblage du rapport...', 0.92);
    String appVersion = '?';
    try {
      appVersion = (await PackageInfo.fromPlatform()).version; // Ex: "1.2.0"
    } catch (_) {}
    // Identifiant anonyme SHA-256(UUID:sel) — calculé une seule fois par installation
    final anonymousDeviceId = await _crypto.getAnonymousDeviceId();

    // Estimation du délai de démarrage vidéo à partir du débit descendant.
    // Un vrai test vidéo nécessite un serveur de streaming dédié — on approche
    // via le débit : ≥5 Mbps = HD fluide, ≥1.5 Mbps = SD acceptable, sinon difficile.
    double? videoStartDelayMs;
    if (downloadMbps != null) {
      if (downloadMbps >= 5.0)       videoStartDelayMs = 700;
      else if (downloadMbps >= 1.5)  videoStartDelayMs = 2200;
      else                           videoStartDelayMs = 4500;
    }

    final metrics = NetworkMetrics(
      radioSignal:  radioMetrics,
      wifiSignal:   wifiMetrics,
      connectivity: ConnectivityMetrics(
        downloadMbps:   downloadMbps,
        uploadMbps:     uploadMbps,
        latencyMs:      pingResult['latency'],
        jitterMs:       pingResult['jitter'],
        packetLossPct:  pingResult['packetLoss'],
      ),
      qoe: QoEMetrics(
        httpSuccessRatePct: qoeResult['httpSuccess'],
        webBrowsingTimeMs:  qoeResult['browsingTime'],
        videoStartDelayMs:  videoStartDelayMs,
        appFailureRatePct:  qoeResult['appFailureRate'],
        testedUrl:          _referenceUrl,
      ),
      context: ContextMetadata(
        h3Index:           locationResult?.h3Index,
        latitude:          locationResult?.latitude,
        longitude:         locationResult?.longitude,
        timestamp:         timestamp,
        deviceModel:       deviceData['model']     ?? 'Inconnu',
        deviceBrand:       deviceData['brand']     ?? 'Inconnu',
        osVersion:         deviceData['osVersion'] ?? 'Inconnu',
        osType:            deviceData['osType']    ?? Platform.operatingSystem,
        batteryLevelPct:   batteryLevel,
        isCharging:
            batteryState == BatteryState.charging ||
            batteryState == BatteryState.full,     // full = chargé à 100%
        appVersion:        appVersion,
        anonymousDeviceId: anonymousDeviceId,
      ),
      operatorName: operatorName,
      operatorMcc:  operatorInfo.mcc,
      operatorMnc:  operatorInfo.mnc,
      isRoaming:    operatorInfo.isRoaming,
      activeSession: ActiveSession(type: isWifi ? 'WiFi' : 'Mobile'),
    );

    // Sauvegarde le contexte dans SharedPreferences pour les collectes background suivantes
    try {
      if (operatorName.isNotEmpty && operatorName != 'Inconnu') {
        await LastKnownContext.save(
          operatorName: operatorName,
          mcc:          operatorInfo.mcc,
          mnc:          operatorInfo.mnc,
          latitude:     locationResult?.latitude,
          longitude:    locationResult?.longitude,
          h3Index:      locationResult?.h3Index,
        );
      }
    } catch (_) {}

    // ── Étape 14 : Envoi vers le serveur (ou file si hors ligne) ─────────
    onProgress?.call('Envoi vers le serveur...', 0.96);
    try {
      final metricId = const Uuid().v4(); // UUID unique de cette mesure
      final jsonData = metrics.toJson();
      jsonData['device_metric_id'] = metricId; // ID de déduplication côté serveur
      await _sync.syncMetric(metricId, jsonData);
    } catch (_) {
      // Échec silencieux — la mesure est déjà dans la file SQLite locale
    }

    onProgress?.call('Terminé !', 1.0);
    return metrics;
  }

  // ── Infos sur l'appareil (Android / iOS) ──────────────────────────────────
  Future<Map<String, String>> _getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return {
          'model':     info.model,
          'brand':     info.brand,
          'osVersion': 'Android ${info.version.release} (API ${info.version.sdkInt})',
          'osType':    'Android',
        };
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return {
          'model':     info.utsname.machine,   // Ex: "iPhone14,4"
          'brand':     'Apple',
          'osVersion': 'iOS ${info.systemVersion}',
          'osType':    'iOS',
        };
      }
    } catch (_) {}
    return {
      'model':     'Inconnu',
      'brand':     'Inconnu',
      'osVersion': 'Inconnu',
      'osType':    'Inconnu',
    };
  }

  // ── Mesure de la latence via ICMP ping ────────────────────────────────────
  // 3 pings vers 8.8.8.8 (Google DNS) — timeout 8s par ping
  // Gigue = racine carrée de la variance des RTTs (approximation de l'écart-type)
  Future<Map<String, double?>> _measurePing() async {
    try {
      final ping    = Ping(_pingHost, count: _pingCount, timeout: 8);
      final results = <double>[]; // RTTs en ms
      int lost = 0;               // Paquets perdus

      await for (final data in ping.stream) {
        if (data.response != null) {
          // RTT en microsecondes → millisecondes avec décimale
          results.add(data.response!.time!.inMicroseconds / 1000.0);
        } else if (data.error != null) {
          lost++; // Timeout ou ICMP unreachable
        }
      }

      if (results.isEmpty) {
        return {'latency': null, 'jitter': null, 'packetLoss': 100.0};
      }

      // Latence moyenne
      final avg = results.reduce((a, b) => a + b) / results.length;
      // Gigue = écart-type des RTTs : sqrt(E[(X - μ)²])
      final variance =
          results.map((r) => (r - avg) * (r - avg)).reduce((a, b) => a + b) /
          results.length;
      final jitter = math.sqrt(variance > 0 ? variance : 0.0);
      return {
        'latency':    double.parse(avg.toStringAsFixed(2)),
        'jitter':     double.parse(jitter.toStringAsFixed(2)),
        'packetLoss': double.parse(((lost / _pingCount) * 100).toStringAsFixed(1)),
      };
    } catch (_) {
      return {'latency': null, 'jitter': null, 'packetLoss': null};
    }
  }

  // ── Mesure du débit descendant ────────────────────────────────────────────
  // Télécharge 500 Ko depuis Cloudflare et calcule le débit en Mbps
  Future<double?> _measureDownload() async {
    try {
      final sw = Stopwatch()..start(); // Démarre le chronomètre avant la requête
      final response = await http
          .get(Uri.parse(_downloadUrl))
          .timeout(_downloadTimeout);
      sw.stop();
      if (response.statusCode == 200) {
        final seconds = sw.elapsedMilliseconds / 1000;
        // Formule : (octets × 8 bits) / (secondes × 1_000_000 bits/Mbps)
        return double.parse(
          ((response.bodyBytes.length * 8) / (seconds * 1_000_000))
              .toStringAsFixed(2),
        );
      }
    } catch (_) {}
    return null; // Timeout ou erreur réseau
  }

  // ── Mesure du débit montant ───────────────────────────────────────────────
  // Envoie 100 Ko de zéros vers Cloudflare et calcule le débit en Mbps
  Future<double?> _measureUpload() async {
    try {
      final payload = List<int>.filled(_uploadSize, 0); // 100 Ko de données vides
      final sw = Stopwatch()..start();
      final response = await http
          .post(
            Uri.parse('https://speed.cloudflare.com/__up'),
            body:    payload,
            headers: {'Content-Type': 'application/octet-stream'},
          )
          .timeout(_uploadTimeout);
      sw.stop();
      if (response.statusCode == 200) {
        final seconds = sw.elapsedMilliseconds / 1000;
        return double.parse(
          ((payload.length * 8) / (seconds * 1_000_000)).toStringAsFixed(2),
        );
      }
    } catch (_) {}
    return null;
  }

  // ── Mesure de la qualité d'expérience (QoE) ─────────────────────────────
  // Test principal : GET vers art.cm (temps de navigation)
  // Tests secondaires : HEAD vers google.com, orange.cm, mtn.cm (disponibilité)
  Future<Map<String, double?>> _measureQoE() async {
    double? browsingTime; // Temps de chargement de art.cm en ms
    double httpSuccess = 0;
    try {
      final sw = Stopwatch()..start();
      final response = await http
          .get(Uri.parse(_referenceUrl))
          .timeout(_browsingTimeout);
      sw.stop();
      if (response.statusCode >= 200 && response.statusCode < 400) {
        browsingTime = sw.elapsedMilliseconds.toDouble(); // Temps en ms
        httpSuccess  = 100.0; // art.cm disponible
      }
    } catch (_) {}

    // Tests de disponibilité des 3 endpoints supplémentaires
    final endpoints = [
      'https://www.google.com',  // Disponibilité Internet générale
      'https://www.orange.cm',   // Site opérateur Orange
      'https://www.mtn.cm',      // Site opérateur MTN
    ];
    int successes = httpSuccess > 0 ? 1 : 0; // Compte art.cm si disponible
    for (final url in endpoints) {
      try {
        final resp = await http.head(Uri.parse(url)).timeout(_headTimeout);
        if (resp.statusCode < 400) successes++; // HEAD < 400 = site accessible
      } catch (_) {}
    }

    // Taux de succès sur 4 endpoints au total
    final total = endpoints.length + 1; // 3 endpoints + art.cm
    httpSuccess = (successes / total) * 100;
    return {
      'httpSuccess':    double.parse(httpSuccess.toStringAsFixed(1)),
      'browsingTime':   browsingTime,
      // Taux d'échec = 100% - taux de succès (pour le champ appFailureRatePct)
      'appFailureRate': double.parse((100 - httpSuccess).toStringAsFixed(1)),
    };
  }
}
