// Modèles de données centraux d'AUDACE — une mesure = une instance NetworkMetrics.

// Modèle principal regroupant toutes les métriques d'une mesure réseau
class NetworkMetrics {
  final RadioSignalMetrics radioSignal;   // Signal cellulaire (RSRP, RSRQ, SINR…)
  final WifiSignalMetrics? wifiSignal;    // Signal WiFi — null si connexion mobile
  final ConnectivityMetrics connectivity; // Débit, latence, gigue, perte de paquets
  final QoEMetrics qoe;                   // Qualité d'expérience (HTTP, navigation web)
  final ContextMetadata context;          // Appareil, batterie, GPS, horodatage
  final String operatorName;             // Nom commercial de l'opérateur (ex: "MTN Cameroon")
  final String operatorMcc;             // Mobile Country Code (ex: "624" = Cameroun)
  final String operatorMnc;             // Mobile Network Code (ex: "01" = MTN)
  final bool isRoaming;                 // true si l'appareil est hors réseau domestique
  final ActiveSession activeSession;    // Type de session active : "WiFi" ou "Mobile"

  const NetworkMetrics({
    required this.radioSignal,
    this.wifiSignal,
    required this.connectivity,
    required this.qoe,
    required this.context,
    required this.operatorName,
    required this.operatorMcc,
    required this.operatorMnc,
    this.isRoaming = false,
    required this.activeSession,
  });

  // Score global de qualité réseau calculé sur 100 points.
  // Formule : RSRP (30pts) + débit descendant (25pts) + latence (25pts) + HTTP QoE (20pts)
  int get score {
    double total = 0;

    // ── Signal RSRP — 30 points maximum ─────────────────────────────────────
    // ≥ -80 dBm = excellent · -90 = bon · -100 = faible · < -100 = très faible
    final rsrp = radioSignal.rsrp;
    if (rsrp != null) {
      if (rsrp >= -80) total += 30;
      else if (rsrp >= -90) total += 20;
      else if (rsrp >= -100) total += 10;
      else total += 4;
    }

    // ── Débit descendant — 25 points maximum ────────────────────────────────
    // ≥ 10 Mbps = plein score · baisse progressive jusqu'à 0,5 Mbps
    final dl = connectivity.downloadMbps;
    if (dl != null) {
      if (dl >= 10) total += 25;
      else if (dl >= 5) total += 20;
      else if (dl >= 2) total += 12;
      else if (dl >= 0.5) total += 6;
    }

    // ── Latence — 25 points maximum ─────────────────────────────────────────
    // ≤ 50 ms = plein score · pénalité progressive jusqu'à > 150 ms
    final lat = connectivity.latencyMs;
    if (lat != null) {
      if (lat <= 50) total += 25;
      else if (lat <= 100) total += 18;
      else if (lat <= 150) total += 10;
      else total += 3;
    }

    // ── Taux de succès HTTP — 20 points maximum ─────────────────────────────
    // ≥ 90% = plein score · pénalité progressive en dessous de 70%
    final http = qoe.httpSuccessRatePct;
    if (http != null) {
      if (http >= 90) total += 20;
      else if (http >= 70) total += 14;
      else if (http >= 50) total += 8;
      else total += 2;
    }

    // Arrondit et bloque entre 0 et 100
    return total.round().clamp(0, 100);
  }

  // Verdict textuel du score : "Excellent" ≥ 75 · "Bon" ≥ 55 · "Moyen" ≥ 35 · "Faible"
  String get scoreVerdict {
    final s = score;
    if (s >= 75) return 'Excellent';
    if (s >= 55) return 'Bon';
    if (s >= 35) return 'Moyen';
    return 'Faible';
  }

  // Sérialise toute la mesure en JSON selon le schéma AUDACE v1.1.0
  Map<String, dynamic> toJson() => {
    'schema_version': '1.1.0',                         // Version du format
    'generated_at': DateTime.now().toIso8601String(),  // Horodatage de génération
    'operateur': {
      'nom': operatorName,     // Nom commercial
      'mcc': operatorMcc,      // Code pays Mobile
      'mnc': operatorMnc,      // Code réseau Mobile
      'pays_iso': 'CM',        // Code ISO du Cameroun
      'en_roaming': isRoaming, // Indicateur d'itinérance
    },
    'session_active': activeSession.toJson(),
    'signal_radio': radioSignal.toJson(),
    if (wifiSignal != null) 'signal_wifi': wifiSignal!.toJson(), // Bloc WiFi facultatif
    'connectivite_qos': connectivity.toJson(),
    'experience_utilisateur_qoe': qoe.toJson(),
    'metadonnees_contexte': context.toJson(),
  };
}

// Décrit la nature de la session réseau active au moment de la mesure
class ActiveSession {
  final String type;        // "WiFi" ou "Mobile"
  final bool hasInternet;   // true si une connexion internet est disponible
  final bool isValidated;   // true si la connexion a été validée (ping réussi)

  const ActiveSession({
    required this.type,
    this.hasInternet = true,
    this.isValidated = true,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'internet_disponible': hasInternet,
    'connexion_validee': isValidated,
  };
}

// Métriques du signal radio cellulaire (LTE, 5G, HSPA…)
class RadioSignalMetrics {
  final double? rsrp;           // Reference Signal Received Power (dBm) — puissance
  final double? rsrq;           // Reference Signal Received Quality (dB) — qualité
  final double? rssi;           // Received Signal Strength Indicator (dBm) — force brute
  final double? sinr;           // Signal / Interference + Noise Ratio (dB)
  final String? cellId;         // Identifiant de la cellule BTS active
  final String? lac;            // Location Area Code (réseaux 2G/3G)
  final String? tac;            // Tracking Area Code (réseaux 4G/5G)
  final NetworkGeneration networkType; // Technologie active (2G, 3G, 4G, 5G)
  final int? signalStrength;    // Nombre de barres affiché (0–4)
  final String? unavailableReason; // Raison si le signal n'a pas pu être lu

  const RadioSignalMetrics({
    this.rsrp,
    this.rsrq,
    this.rssi,
    this.sinr,
    this.cellId,
    this.lac,
    this.tac,
    this.networkType = NetworkGeneration.unknown,
    this.signalStrength,
    this.unavailableReason,
  });

  // true si au moins une métrique est disponible ET qu'aucune erreur n'est survenue
  bool get isAvailable =>
      unavailableReason == null &&
      (rsrp != null || rssi != null || cellId != null);

  Map<String, dynamic> toJson() => {
    'disponible': isAvailable,
    if (!isAvailable && unavailableReason != null)
      'raison_indisponibilite': unavailableReason, // Raison uniquement si indisponible
    'rsrp_dbm': rsrp,
    'rsrq_db': rsrq,
    'rssi_dbm': rssi,
    'sinr_db': sinr,
    'cell_id': cellId,
    'lac': lac,
    'tac': tac,
    'technologie': networkType.label, // ex: "4G (LTE)"
    'signal_barres': signalStrength,
    if (isAvailable) 'interpretation': _interpret(), // Texte seulement si signal dispo
  };

  // Interprétation humaine du RSRP en quatre niveaux
  String _interpret() {
    if (rsrp == null) return 'Non mesurable';
    if (rsrp! >= -80) return 'Excellent';
    if (rsrp! >= -90) return 'Bon';
    if (rsrp! >= -100) return 'Faible';
    return 'Très faible';
  }
}

// Métriques du signal WiFi — renseigné uniquement si connexion WiFi active
class WifiSignalMetrics {
  final String ssid;           // Nom du réseau WiFi (ex: "MTN-Box")
  final String bssid;          // Adresse MAC du point d'accès
  final int rssiDbm;           // Force du signal WiFi en dBm (proche de 0 = meilleur)
  final int qualityPct;        // Qualité convertie en pourcentage (0–100)
  final int linkSpeedMbps;     // Vitesse de liaison négociée avec le point d'accès
  final int frequencyMhz;      // Fréquence utilisée (2400 = 2,4 GHz · 5000+ = 5 GHz)
  final String band;           // Bande radio : "2.4 GHz" ou "5 GHz"
  final String ipAddress;      // Adresse IP locale de l'appareil
  final String gateway;        // Adresse IP de la passerelle (box/routeur)

  const WifiSignalMetrics({
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

  // Qualité du signal WiFi : Excellent ≥ -50 · Bon ≥ -60 · Acceptable ≥ -70 · Faible
  String get interpretation {
    if (rssiDbm >= -50) return 'Excellent';
    if (rssiDbm >= -60) return 'Bon';
    if (rssiDbm >= -70) return 'Acceptable';
    return 'Faible';
  }

  Map<String, dynamic> toJson() => {
    'ssid': ssid,
    'bssid': bssid,
    'rssi_dbm': rssiDbm,
    'qualite_pct': qualityPct,
    'interpretation': interpretation,
    'vitesse_liaison_mbps': linkSpeedMbps,
    'frequence_mhz': frequencyMhz,
    'bande': band,
    'adresse_ip': ipAddress,
    'passerelle': gateway,
  };
}

// Métriques de connectivité mesurées activement (test de débit + ping)
class ConnectivityMetrics {
  final double? downloadMbps;    // Débit descendant (Mbps) — depuis Cloudflare
  final double? uploadMbps;      // Débit montant (Mbps) — vers Cloudflare
  final double? latencyMs;       // Latence moyenne (ms) — ping vers 8.8.8.8
  final double? jitterMs;        // Gigue (ms) — variation entre pings successifs
  final double? packetLossPct;   // Taux de perte de paquets (%)

  const ConnectivityMetrics({
    this.downloadMbps,
    this.uploadMbps,
    this.latencyMs,
    this.jitterMs,
    this.packetLossPct,
  });

  Map<String, dynamic> toJson() => {
    'debit_descendant_mbps': downloadMbps,
    'debit_montant_mbps': uploadMbps,
    'latence_ms': latencyMs,
    'gigue_ms': jitterMs,
    'taux_perte_paquets_pct': packetLossPct,
    'qualite_globale': _qualiteGlobale(), // Appréciation combinée en texte
  };

  // Calcule une appréciation globale à partir des trois métriques principales
  String _qualiteGlobale() {
    int score = 0;

    // Débit : 3 pts ≥ 10 Mbps · 2 pts ≥ 2 Mbps · 1 pt sinon
    if (downloadMbps != null) {
      if (downloadMbps! >= 10)
        score += 3;
      else if (downloadMbps! >= 2)
        score += 2;
      else
        score += 1;
    }

    // Latence : 3 pts ≤ 50 ms · 2 pts ≤ 150 ms · 1 pt sinon
    if (latencyMs != null) {
      if (latencyMs! <= 50)
        score += 3;
      else if (latencyMs! <= 150)
        score += 2;
      else
        score += 1;
    }

    // Perte : 3 pts ≤ 1% · 2 pts ≤ 5% · 1 pt sinon
    if (packetLossPct != null) {
      if (packetLossPct! <= 1)
        score += 3;
      else if (packetLossPct! <= 5)
        score += 2;
      else
        score += 1;
    }

    // Seuils : 7–9 = Excellente · 5–6 = Bonne · 3–4 = Acceptable · <3 = Mauvaise
    if (score >= 7) return 'Excellente';
    if (score >= 5) return 'Bonne';
    if (score >= 3) return 'Acceptable';
    return 'Mauvaise';
  }
}

// Métriques de qualité d'expérience utilisateur (QoE — Quality of Experience)
class QoEMetrics {
  final double? httpSuccessRatePct;    // % de requêtes HTTP réussies (sur 4 URLs testées)
  final double? webBrowsingTimeMs;     // Temps de chargement de art.cm (ms)
  final double? videoStartDelayMs;     // Délai avant démarrage vidéo (non mesuré actuellement)
  final int? videoBufferingCount;      // Nombre d'interruptions de buffering vidéo
  final double? videoBufferingTotalMs; // Durée totale des interruptions vidéo (ms)
  final double? appFailureRatePct;     // % de requêtes ayant échoué (= 100 - httpSuccessRatePct)
  final String? testedUrl;             // URL principale testée (https://www.art.cm)

  const QoEMetrics({
    this.httpSuccessRatePct,
    this.webBrowsingTimeMs,
    this.videoStartDelayMs,
    this.videoBufferingCount,
    this.videoBufferingTotalMs,
    this.appFailureRatePct,
    this.testedUrl,
  });

  Map<String, dynamic> toJson() => {
    'http_success_rate_pct': httpSuccessRatePct,
    'web_browsing_time_ms': webBrowsingTimeMs,
    'video_start_delay_ms': videoStartDelayMs,
    'video_buffering_interruptions': videoBufferingCount,
    'video_buffering_total_ms': videoBufferingTotalMs,
    'app_failure_rate_pct': appFailureRatePct,
    'url_teste': testedUrl,
  };
}

// Métadonnées de contexte — informations sur l'appareil et la position lors de la mesure
class ContextMetadata {
  final String? h3Index;        // Index hexagonal H3 (résolution 8 ≈ 0,5 km²) pour la carte
  final double? latitude;       // Latitude GPS en degrés décimaux
  final double? longitude;      // Longitude GPS en degrés décimaux
  final String timestamp;       // Horodatage ISO 8601 UTC de la mesure
  final String deviceModel;     // Modèle de l'appareil (ex: "SM-A546E")
  final String deviceBrand;     // Marque (ex: "Samsung")
  final String osVersion;       // Version du système (ex: "Android 13 (API 33)")
  final String osType;          // Type d'OS : "Android" ou "iOS"
  final int batteryLevelPct;    // Niveau de batterie en % au moment de la mesure
  final bool isCharging;        // true si l'appareil est en charge
  final String appVersion;      // Version de l'application AUDACE
  final String? anonymousDeviceId; // Identifiant anonyme SHA-256 — jamais l'IMEI

  const ContextMetadata({
    this.h3Index,
    this.latitude,
    this.longitude,
    required this.timestamp,
    required this.deviceModel,
    required this.deviceBrand,
    required this.osVersion,
    required this.osType,
    required this.batteryLevelPct,
    required this.isCharging,
    required this.appVersion,
    this.anonymousDeviceId,
  });

  Map<String, dynamic> toJson() => {
    'h3_index': h3Index,
    // Les coordonnées ne sont incluses que si le GPS a fonctionné
    'coordonnees': latitude != null
        ? {'latitude': latitude, 'longitude': longitude}
        : null,
    'horodatage_iso': timestamp,
    'terminal': {'marque': deviceBrand, 'modele': deviceModel},
    'systeme': {'type': osType, 'version': osVersion},
    'batterie': {'niveau_pct': batteryLevelPct, 'en_charge': isCharging},
    'version_application': appVersion,
    'identifiant_anonyme': anonymousDeviceId,
  };
}

// Énumération des générations réseau mobile supportées
enum NetworkGeneration {
  unknown,      // Technologie non détectée ou indisponible
  gsm,          // 2G GSM
  edge,         // 2G EDGE (données lentes)
  hspa,         // 3G HSPA
  hspaPlus,     // 3G HSPA+ (3,5G)
  lte,          // 4G LTE
  lteAdvanced,  // 4G+ LTE-Advanced (agrégation de porteuses)
  nr5g;         // 5G New Radio

  // Libellé affiché dans l'interface et exporté en JSON
  String get label => switch (this) {
    NetworkGeneration.unknown     => 'Inconnu',
    NetworkGeneration.gsm         => '2G (GSM)',
    NetworkGeneration.edge        => '2G (EDGE)',
    NetworkGeneration.hspa        => '3G (HSPA)',
    NetworkGeneration.hspaPlus    => '3G (HSPA+)',
    NetworkGeneration.lte         => '4G (LTE)',
    NetworkGeneration.lteAdvanced => '4G+ (LTE-A)',
    NetworkGeneration.nr5g        => '5G (NR)',
  };
}
