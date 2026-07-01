// Service de gestion des cellules hexagonales de couverture réseau.
// Charge les données depuis le serveur MongoDB ou les agrège depuis SQLite local.
// Chaque cellule H3 représente une zone géographique (~0.46 km² à résolution 8)
// avec les métriques moyennes (débit, latence, disponibilité) et l'opérateur dominant.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import 'h3_index_provider.dart';
import 'queue_service.dart';
import 'sync_service.dart';

// ─── Modèle d'une cellule hexagonale H3 ──────────────────────────────────────
class HexCoverageCell {
  final String h3Index;           // Index H3 en hexadécimal (ex: "88ac7d3a8dfffff")
  final double centerLat;         // Latitude du centre de la cellule
  final double centerLon;         // Longitude du centre de la cellule
  final double qualityScore;      // Score de qualité 0–100
  final String bestOperator;      // Opérateur avec le plus de mesures dans la cellule
  final double? avgDownloadMbps;  // Débit descendant moyen en Mbps
  final double? avgLatencyMs;     // Latence moyenne en ms
  final double? avgAvailabilityPct; // Taux de disponibilité moyen en %
  final int measurementCount;     // Nombre de mesures dans cette cellule
  final List<LatLng>? _boundary;  // Sommets du polygone hexagonal (null = approx)

  HexCoverageCell({
    required this.h3Index,
    required this.centerLat,
    required this.centerLon,
    required this.qualityScore,
    required this.bestOperator,
    required this.measurementCount,
    this.avgDownloadMbps,
    this.avgLatencyMs,
    this.avgAvailabilityPct,
    List<LatLng>? boundary,
  }) : _boundary = boundary;

  // Couleur de la cellule selon le score : vert ≥70, orange ≥45, rouge <45
  Color get color {
    if (qualityScore >= 70) return const Color(0xFF10B981); // Vert
    if (qualityScore >= 45) return const Color(0xFFF59E0B); // Orange
    return const Color(0xFFEF4444);                          // Rouge
  }

  // Sommets réels via librairie H3 si disponibles, sinon hexagone approximatif de 450m
  // 450m < circumrayon H3 résolution 8 (~461m) pour éviter les chevauchements
  List<LatLng> get hexBoundary => _boundary ?? _flatTopHex(centerLat, centerLon, 450);
}

// ─── Hexagone "flat top" (comme H3) avec 6 sommets ───────────────────────────
// Calcule les 6 sommets d'un hexagone centré en (lat, lon) avec un rayon en mètres.
// Les angles sont 0°, 60°, 120°, 180°, 240°, 300° (hexagone plat).
List<LatLng> _flatTopHex(double lat, double lon, double radiusM) {
  const metersPerDegLat = 111320.0; // Mètres par degré de latitude (constant)
  // Mètres par degré de longitude (varie avec la latitude via cosinus)
  final metersPerDegLon = metersPerDegLat * math.cos(lat * math.pi / 180);
  final dLat = radiusM / metersPerDegLat; // Conversion rayon en degrés lat
  final dLon = radiusM / metersPerDegLon; // Conversion rayon en degrés lon
  // Génère les 6 sommets en tournant de 60° à chaque fois
  return List.generate(6, (i) {
    final angle = i * math.pi / 3; // Angle en radians (0, π/3, 2π/3…)
    return LatLng(lat + dLat * math.sin(angle), lon + dLon * math.cos(angle));
  });
}

// ─── Service de chargement et d'agrégation des cellules ──────────────────────
class HexCoverageService {
  // Provider H3 avec repli automatique sur approximation
  final H3IndexProvider _h3 = SafeH3IndexProvider();
  static const _uuid = Uuid(); // Générateur d'UUID pour les données de démo

  // URL du endpoint de couverture : /api/coverage
  static String get _coverageUrl {
    const base = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://82.29.172.251.nip.io/api/metrics',
    );
    return base.replaceFirst(RegExp(r'/api/metrics.*'), '/api/coverage');
  }

  // ── Chargement depuis MongoDB (mesures de tous les appareils) ─────────────
  // Retourne les cellules triées et enrichies avec les vrais contours H3.
  Future<List<HexCoverageCell>> loadCellsFromServer() async {
    try {
      final response = await http
          .get(Uri.parse(_coverageUrl), headers: SyncService.headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body['cells'] as List<dynamic>? ?? [];

      // Tente de charger la vraie librairie H3 pour les contours précis
      H3? h3;
      try { h3 = const H3Factory().load(); } catch (_) {} // null si lib native indisponible

      return list.map((raw) {
        final m = raw as Map<String, dynamic>;
        final h3Index = m['_id'] as String? ?? '';
        if (h3Index.isEmpty) return null; // Entrée invalide → ignorée

        var centerLat = (m['centerLat'] as num?)?.toDouble() ?? 0.0;
        var centerLon = (m['centerLon'] as num?)?.toDouble() ?? 0.0;
        List<LatLng>? boundary;

        // Recalcule le centre et les contours réels via H3 si disponible
        if (h3 != null) {
          try {
            final cell = BigInt.parse(h3Index, radix: 16); // Index H3 en BigInt
            final geo  = h3.cellToGeo(cell);                // Centre précis
            centerLat  = geo.lat;
            centerLon  = geo.lon;
            // Contour exact de l'hexagone (liste de GeoCoord → LatLng)
            boundary   = h3.cellToBoundary(cell)
                .map((c) => LatLng(c.lat, c.lon))
                .toList();
          } catch (_) {} // Si le parsing échoue, on garde les valeurs du serveur
        }

        final dl    = (m['avgDownloadMbps']    as num?)?.toDouble();
        final lat   = (m['avgLatencyMs']       as num?)?.toDouble();
        final avail = (m['avgAvailabilityPct'] as num?)?.toDouble();
        // Score composite : débit (40%) + latence (40%) + dispo (20%)
        final score = _qualityScore(dl, lat, avail);

        return HexCoverageCell(
          h3Index:            h3Index,
          centerLat:          centerLat,
          centerLon:          centerLon,
          qualityScore:       score,
          bestOperator:       m['bestOperator']    as String? ?? 'Inconnu',
          measurementCount:   (m['measurementCount'] as num?)?.toInt() ?? 0,
          avgDownloadMbps:    dl,
          avgLatencyMs:       lat,
          avgAvailabilityPct: avail,
          boundary:           boundary,
        );
      }).whereType<HexCoverageCell>().toList(); // Filtre les null
    } catch (_) {
      return []; // Timeout, réseau indisponible ou JSON invalide
    }
  }

  // Score composite pour les données serveur : débit (40pts) + latence (40pts) + dispo (20pts)
  static double _qualityScore(double? dl, double? latencyMs, double? availPct) {
    final s1 = dl        != null ? (dl / 35 * 40).clamp(0.0, 40.0)                : 0.0;
    final s2 = latencyMs != null ? ((180 - latencyMs) / 180 * 40).clamp(0.0, 40.0) : 0.0;
    final s3 = availPct  != null ? (availPct / 100 * 20).clamp(0.0, 20.0)          : 0.0;
    return (s1 + s2 + s3).clamp(0.0, 100.0);
  }

  // ── Insertion de données de démo dans SQLite ───────────────────────────────
  // Crée 3 mesures fictives si la file est vide, pour le test visuel de la carte.
  Future<void> seedDemoData(QueueRepository queue) async {
    final existing = await queue.getAll(limit: 10);
    if (existing.isNotEmpty) return; // Déjà des données → on ne sème pas

    final now = DateTime.now().toUtc();
    // 3 opérateurs camerounais à des positions différentes dans Yaoundé
    final demo = [
      _demoEntry(id: _uuid.v4(), operator: 'MTN Cameroon',    lat: 3.8400, lon: 11.4960, dl: 22.5, ul: 8.3, latency: 45.0, avail: 95.0, timestamp: now.subtract(const Duration(hours: 2))),
      _demoEntry(id: _uuid.v4(), operator: 'Orange Cameroun', lat: 3.8360, lon: 11.5120, dl: 14.2, ul: 5.1, latency: 68.0, avail: 88.0, timestamp: now.subtract(const Duration(hours: 1))),
      _demoEntry(id: _uuid.v4(), operator: 'Camtel',          lat: 3.8300, lon: 11.5040, dl:  6.8, ul: 2.4, latency: 95.0, avail: 76.0, timestamp: now.subtract(const Duration(minutes: 30))),
    ];

    for (final entry in demo) {
      await queue.enqueue(entry['identifiant_mesure'] as String, entry);
    }
  }

  // ── Agrégation depuis SQLite local (mesures de cet appareil) ─────────────
  // Groupe les mesures par cellule H3 et calcule les moyennes de chaque groupe.
  Future<List<HexCoverageCell>> loadCells(QueueRepository queue) async {
    final all = await queue.getAll(limit: 500);
    if (all.isEmpty) return [];

    // Tente de charger la librairie H3 pour les contours précis
    H3? h3;
    try { h3 = const H3Factory().load(); } catch (_) {}

    // ── Groupage des mesures par cellule H3 ──────────────────────────────
    final Map<String, List<Map<String, dynamic>>> byCell = {};
    for (final m in all) {
      try {
        final json = jsonDecode(m.json) as Map<String, dynamic>;
        final ctx  = json['metadonnees_contexte'] as Map<String, dynamic>?;
        if (ctx == null) continue;

        final coords = ctx['coordonnees'] as Map<String, dynamic>?;
        final lat    = (coords?['latitude']  as num?)?.toDouble();
        final lon    = (coords?['longitude'] as num?)?.toDouble();
        if (lat == null || lon == null) continue; // Mesure sans GPS → ignorée

        // Utilise l'index H3 stocké ou le recalcule depuis les coordonnées
        final h3Index = ctx['h3_index'] as String? ?? _h3.compute(lat, lon);

        byCell.putIfAbsent(h3Index, () => []).add(json);
      } catch (_) {
        continue; // JSON corrompu → on ignore cette mesure
      }
    }

    // ── Calcul des métriques agrégées par cellule ─────────────────────────
    final cells = <HexCoverageCell>[];
    for (final entry in byCell.entries) {
      final h3Index  = entry.key;
      final measures = entry.value;

      // Accumulateurs pour le calcul des moyennes
      double sumLat = 0, sumLon = 0;
      final Map<String, int> operatorCount = {}; // Compteur par opérateur
      final List<double> dls = [], latencies = [], availabilities = [];

      for (final json in measures) {
        final ctx    = json['metadonnees_contexte'] as Map<String, dynamic>?;
        final coords = ctx?['coordonnees']          as Map<String, dynamic>?;
        sumLat += (coords?['latitude']  as num?)?.toDouble() ?? 0;
        sumLon += (coords?['longitude'] as num?)?.toDouble() ?? 0;

        // Support des deux formats JSON : vraies mesures et données de démo
        final operateur = json['operateur'] as Map<String, dynamic>?;
        final op = ((operateur?['nom'] ?? json['nom']) as String?) ?? 'Inconnu';
        operatorCount[op] = (operatorCount[op] ?? 0) + 1;

        // Métriques de connectivité
        final conn = json['connectivite_qos'] as Map<String, dynamic>?;
        final dl   = (conn?['debit_descendant_mbps'] as num?)?.toDouble();
        final lat  = (conn?['latence_ms']            as num?)?.toDouble();
        if (dl  != null) dls.add(dl);
        if (lat != null) latencies.add(lat);

        // Taux de disponibilité depuis les métriques QoE
        final qoe   = json['experience_utilisateur_qoe'] as Map<String, dynamic>?;
        final avail = (qoe?['http_success_rate_pct'] as num?)?.toDouble();
        if (avail != null) availabilities.add(avail);
      }

      final n = measures.length;
      double centerLat = sumLat / n; // Centroïde des mesures
      double centerLon = sumLon / n;

      // Opérateur dominant = celui avec le plus grand nombre de mesures
      final bestOp = operatorCount.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;

      // Moyennes arithmétiques des métriques
      final avgDl    = dls.isEmpty           ? null : dls.reduce((a, b)           => a + b) / dls.length;
      final avgLat   = latencies.isEmpty     ? null : latencies.reduce((a, b)     => a + b) / latencies.length;
      final avgAvail = availabilities.isEmpty ? null : availabilities.reduce((a, b) => a + b) / availabilities.length;

      // Score composite avec disponibilité : dl(40%) + latence(30%) + dispo(30%)
      final score = _computeScore(avgDl, avgLat, avgAvail);

      // Essaie d'obtenir le centre réel H3 et la frontière exacte
      List<LatLng>? boundary;
      if (h3 != null) {
        try {
          final cell   = BigInt.parse(h3Index, radix: 16);
          final center = h3.cellToGeo(cell);
          centerLat    = center.lat; // Centre précis (remplace le centroïde)
          centerLon    = center.lon;
          boundary     = h3.cellToBoundary(cell)
              .map((c) => LatLng(c.lat, c.lon))
              .toList();
        } catch (_) {} // Si échec, garde le centroïde et l'hexagone approximatif
      }

      cells.add(HexCoverageCell(
        h3Index:            h3Index,
        centerLat:          centerLat,
        centerLon:          centerLon,
        qualityScore:       score,
        bestOperator:       bestOp,
        avgDownloadMbps:    avgDl,
        avgLatencyMs:       avgLat,
        avgAvailabilityPct: avgAvail,
        measurementCount:   n,
        boundary:           boundary,
      ));
    }

    // Trie par score croissant : les mauvaises cellules sont rendues en premier
    // (les bonnes les recouvrent) → les zones de bonne qualité restent visibles
    cells.sort((a, b) => a.qualityScore.compareTo(b.qualityScore));
    return cells;
  }

  // Score local avec disponibilité : dl(40%) + latence(30%) + dispo(30%)
  double _computeScore(double? dl, double? latency, double? avail) {
    final s1 = dl      != null ? (dl / 35 * 40).clamp(0.0, 40.0)              : 0.0;
    final s2 = latency != null ? ((180 - latency) / 180 * 30).clamp(0.0, 30.0) : 0.0;
    final s3 = avail   != null ? (avail / 100 * 30).clamp(0.0, 30.0)          : 0.0;
    return s1 + s2 + s3;
  }

  // Construit un JSON de mesure fictif pour les données de démonstration
  Map<String, dynamic> _demoEntry({
    required String id,
    required String operator,
    required double lat,
    required double lon,
    required double dl,
    required double ul,
    required double latency,
    required double avail,
    required DateTime timestamp,
  }) {
    final h3Index = _h3.compute(lat, lon); // Index H3 de la position de démo
    return {
      'identifiant_mesure': id,
      'nom': operator,
      'horodatage': timestamp.toIso8601String(),
      'metadonnees_contexte': {
        'h3_index': h3Index,
        'coordonnees': {'latitude': lat, 'longitude': lon},
        'precision_gps': 12.0,
        'horodatage_contexte': timestamp.toIso8601String(),
        'identifiant_anonyme': null,
      },
      'connectivite_qos': {
        'debit_descendant_mbps': dl,
        'debit_montant_mbps':    ul,
        'latence_ms':            latency,
        'gigue_ms':              null,
        'taux_perte_paquets':    null,
      },
      'experience_utilisateur_qoe': {
        'http_success_rate_pct': avail,
      },
      'signal_radio': {
        'available':   true,
        'networkType': 'LTE',
        'rsrp':        -82.0,
      },
      'session_active': {'type': 'mobile'},
    };
  }
}
