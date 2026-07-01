// Service de calcul du classement des opérateurs par qualité de réseau.
// Agrège les mesures depuis le serveur MongoDB (toutes les mesures) ou
// depuis la base SQLite locale (mesures de cet appareil).
// Le score sur 100 combine débit, latence, gigue et signal RSRP.

import 'dart:convert';
import 'dart:math' show log;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/operator_performance.dart';
import 'queue_service.dart';
import 'sync_service.dart';

class CoverageInsightsService {
  const CoverageInsightsService(); // Pas d'état — const possible

  // Référence de débit DL pour le scaling logarithmique (Mbps)
  // Calibré sur la réalité 4G camerounaise (pas les 100+ Mbps européens)
  static const double _dlRef = 35.0;

  // Seuil de confiance bayésien : nombre de mesures qui valent "demi-confiance"
  // k=30 → avec 30 mesures, on fait confiance à 50% au score observé, 50% à la moyenne
  //         avec 3 mesures, on fait confiance à 9% au score observé, 91% à la moyenne
  //         avec 300 mesures, on fait confiance à 91% au score observé
  static const int _kBayesian = 30;

  // URL du endpoint de classement : /api/rankings
  // Construite depuis API_BASE_URL comme tous les autres services
  static String get _rankingsUrl {
    const base = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://82.29.172.251.nip.io/api/metrics',
    );
    return base.replaceFirst(RegExp(r'/api/metrics.*'), '/api/rankings');
  }

  // ── Classement depuis le serveur MongoDB (mesures de tous les appareils) ───
  // Retourne un tuple vide si le serveur est inaccessible ou répond une erreur.
  Future<({List<OperatorPerformance> operators, int total})> buildRankingsFromServer() async {
    const empty = (operators: <OperatorPerformance>[], total: 0);
    try {
      final response = await http
          .get(Uri.parse(_rankingsUrl), headers: SyncService.headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return empty;

      final body  = jsonDecode(response.body) as Map<String, dynamic>;
      final list  = body['operators']          as List<dynamic>? ?? [];
      final total = (body['totalMeasurements'] as num?)?.toInt() ?? 0;

      // ── Normalisation et fusion des variantes du même opérateur ──────────
      // Ex: "CAMTEL" + "Blue" → fusionnés sous "Blue"
      final merged = <String, Map<String, dynamic>>{};
      for (final raw in list) {
        final m    = raw as Map<String, dynamic>;
        final name = _normalizeOperatorName(m['_id'] as String? ?? '');
        if (name.isEmpty) continue; // Nexttel ou inconnu → exclu
        final count = (m['measurementCount'] as num?)?.toInt() ?? 0;

        // Initialise l'accumulateur si premier segment pour cet opérateur
        if (!merged.containsKey(name)) {
          merged[name] = {
            'count': 0,
            'dlSum': 0.0, 'latSum': 0.0, 'jitterSum': 0.0,
            'signalSum': 0.0, 'signalCount': 0,
            'lastSeen': null,
          };
        }
        final e = merged[name]!;

        // Accumule les sommes pondérées par le nombre de mesures (moyenne pondérée)
        final dl     = (m['avgDownloadMbps'] as num?)?.toDouble();
        final lat    = (m['avgLatencyMs']    as num?)?.toDouble();
        final jitter = (m['avgJitterMs']     as num?)?.toDouble();
        final signal = (m['avgRsrpDbm']      as num?)?.toDouble();
        if (dl     != null) e['dlSum']     = (e['dlSum']     as double) + dl     * count;
        if (lat    != null) e['latSum']    = (e['latSum']    as double) + lat    * count;
        if (jitter != null) e['jitterSum'] = (e['jitterSum'] as double) + jitter * count;
        if (signal != null) {
          e['signalSum']   = (e['signalSum']   as double) + signal * count;
          e['signalCount'] = (e['signalCount'] as int)    + count;
        }
        e['count'] = (e['count'] as int) + count;
        // Garde la date de mesure la plus récente
        final seen = m['lastSeen'] != null ? DateTime.tryParse(m['lastSeen'] as String) : null;
        final prev = e['lastSeen'] as DateTime?;
        if (seen != null && (prev == null || seen.isAfter(prev))) e['lastSeen'] = seen;
      }

      // ── Conversion des accumulateurs en OperatorPerformance ──────────────
      final operators = merged.entries.map((entry) {
        final name     = entry.key;
        final e        = entry.value;
        final count    = e['count']        as int;
        final sigCount = e['signalCount']  as int;
        // Moyennes pondérées finales
        final dl     = count    > 0 ? (e['dlSum']     as double) / count    : null;
        final lat    = count    > 0 ? (e['latSum']    as double) / count    : null;
        final jitter = count    > 0 ? (e['jitterSum'] as double) / count    : null;
        final signal = sigCount > 0 ? (e['signalSum'] as double) / sigCount : null;
        final score = computeScore(
          downloadMbps: dl, latencyMs: lat, jitterMs: jitter, signalRsrpDbm: signal,
        );
        return OperatorPerformance(
          name:             name,
          localScore:       score,
          nationalScore:    score, // Score unique (pas de distinction local/national)
          downloadMbps:     dl,
          latencyMs:        lat,
          jitterMs:         jitter,
          signalRsrpDbm:    signal,
          color:            _operatorColor(name),
          isReference:      false,
          measurementCount: count,
          lastMeasuredAt:   e['lastSeen'] as DateTime?,
        );
      }).toList()..sort((a, b) => b.localScore.compareTo(a.localScore)); // Tri décroissant

      return (operators: _applyBayesian(operators), total: total);
    } catch (_) {
      return empty; // Timeout, réseau indisponible ou JSON invalide
    }
  }

  // ── Classement depuis la base SQLite locale (mesures de cet appareil) ──────
  // Aucune valeur codée en dur — tout vient des vrais JSON collectés.
  Future<List<OperatorPerformance>> buildRankingsFromDB(
    QueueRepository queue,
  ) async {
    final all = await queue.getAll(limit: 500); // 500 dernières mesures locales
    if (all.isEmpty) return [];

    // Accumulateur par opérateur
    final Map<String, _OpStats> byOp = {};
    for (final m in all) {
      try {
        final json = jsonDecode(m.json) as Map<String, dynamic>;
        // Support de deux formats JSON : vraies mesures et données démo
        final operateur = json['operateur'] as Map<String, dynamic>?;
        final rawOp = ((operateur?['nom'] ?? json['nom']) as String?)?.trim() ?? '';
        if (rawOp.isEmpty || rawOp == 'Inconnu') continue; // Filtre les mesures sans opérateur
        final op = _normalizeOperatorName(rawOp);
        if (op.isEmpty) continue; // Opérateur exclu par normalisation (ex: Nexttel)

        // Extrait les métriques de connectivité
        final conn    = json['connectivite_qos'] as Map<String, dynamic>?;
        final dl      = (conn?['debit_descendant_mbps'] as num?)?.toDouble();
        final latency = (conn?['latence_ms']            as num?)?.toDouble();
        final jitter  = (conn?['gigue_ms']              as num?)?.toDouble();

        // Extrait les métriques de signal radio
        final sig    = json['signal_radio'] as Map<String, dynamic>?;
        final signal = (sig?['rsrp_dbm']   as num?)?.toDouble();

        // Ajoute les métriques à l'accumulateur de l'opérateur
        byOp.putIfAbsent(op, () => _OpStats(op)).add(
          dl:            dl,
          latencyMs:     latency,
          jitterMs:      jitter,
          signalRsrpDbm: signal,
          measuredAt:    m.createdAt,
        );
      } catch (_) {
        continue; // JSON corrompu → on ignore cette mesure
      }
    }

    if (byOp.isEmpty) return [];

    // Convertit les accumulateurs en OperatorPerformance, tri décroissant
    final operators = byOp.values.map((stats) {
      final score = computeScore(
        downloadMbps:  stats.avgDl,
        latencyMs:     stats.avgLatency,
        jitterMs:      stats.avgJitter,
        signalRsrpDbm: stats.avgSignal,
      );
      return OperatorPerformance(
        name:             stats.name,
        localScore:       score,
        nationalScore:    score,
        downloadMbps:     stats.avgDl,
        latencyMs:        stats.avgLatency,
        jitterMs:         stats.avgJitter,
        signalRsrpDbm:    stats.avgSignal,
        color:            _operatorColor(stats.name),
        isReference:      false,
        measurementCount: stats.count,
        lastMeasuredAt:   stats.lastAt,
      );
    }).toList()
      ..sort((a, b) => b.localScore.compareTo(a.localScore));

    return _applyBayesian(operators);
  }

  // ── Calcul du score composite sur 100 ─────────────────────────────────────
  // Formule : débit (30pts) + latence (25pts) + gigue (25pts) + signal (20pts)
  // Un composant manquant vaut 0 (pas de pénalité autre que le 0)
  double computeScore({
    required double? downloadMbps,  // Débit descendant en Mbps
    required double? latencyMs,     // Latence en ms (optimal : < 20ms)
    required double? jitterMs,      // Gigue en ms (optimal : < 5ms)
    required double? signalRsrpDbm, // RSRP en dBm (plage : -110 à -44)
  }) {
    // Débit : scaling logarithmique log(1+x)/log(1+ref) × 30 pts
    // Pourquoi log ? Parce que 1→2 Mbps change vraiment la vie, 20→21 Mbps ne change rien.
    // La perception de la vitesse suit une courbe log, pas une droite.
    final s1 = downloadMbps != null
        ? (log(1 + downloadMbps) / log(1 + _dlRef) * 30).clamp(0.0, 30.0)
        : 0.0;
    // Latence : 180ms (0 pt) → 0ms (25 pts) — inversé car moins = mieux
    final s2 = latencyMs != null
        ? ((180 - latencyMs) / 180 * 25).clamp(0.0, 25.0)
        : 0.0;
    // Gigue : 50ms (0 pt) → 0ms (25 pts) — inversé car moins = mieux
    final s3 = jitterMs != null
        ? ((50 - jitterMs) / 50 * 25).clamp(0.0, 25.0)
        : 0.0;
    // Signal RSRP : -110 dBm (0 pt) → -44 dBm (20 pts), plage de 66 dB
    final s4 = signalRsrpDbm != null
        ? ((signalRsrpDbm + 110) / 66 * 20).clamp(0.0, 20.0)
        : 0.0;
    return double.parse((s1 + s2 + s3 + s4).toStringAsFixed(1));
  }

  // ── Correction bayésienne ─────────────────────────────────────────────────
  // Ajuste le score d'un opérateur selon le nombre de mesures disponibles.
  // Avec peu de mesures, on n'est pas sûr → on tire le score vers la moyenne globale.
  // Avec beaucoup de mesures, on est confiant → le score reste proche du score réel.
  double _bayesian(double score, int n, double globalMean) =>
      (_kBayesian * globalMean + n * score) / (_kBayesian + n);

  // Applique la correction bayésienne à toute une liste et re-trie
  List<OperatorPerformance> _applyBayesian(List<OperatorPerformance> ops) {
    if (ops.length < 2) return ops; // Pas de comparaison possible avec 1 seul opérateur
    final mean = ops.map((o) => o.localScore).reduce((a, b) => a + b) / ops.length;
    return ops.map((op) {
      final s = double.parse(
        _bayesian(op.localScore, op.measurementCount, mean).toStringAsFixed(1),
      );
      return OperatorPerformance(
        name:             op.name,
        localScore:       s,
        nationalScore:    s,
        downloadMbps:     op.downloadMbps,
        latencyMs:        op.latencyMs,
        jitterMs:         op.jitterMs,
        signalRsrpDbm:    op.signalRsrpDbm,
        color:            op.color,
        isReference:      op.isReference,
        measurementCount: op.measurementCount,
        lastMeasuredAt:   op.lastMeasuredAt,
      );
    }).toList()..sort((a, b) => b.localScore.compareTo(a.localScore));
  }

  // ── Normalisation du nom d'opérateur ──────────────────────────────────────
  // Fusionne les variantes de noms pour avoir une seule entrée par opérateur
  String _normalizeOperatorName(String name) {
    final n = name.toLowerCase();
    if (n.contains('mtn'))                          return 'MTN Cameroon';
    if (n.contains('orange'))                       return 'Orange Cameroun';
    if (n.contains('camtel') || n.contains('blue')) return 'Blue'; // Blue = réseau mobile Camtel
    if (n.contains('yoomee'))                       return 'Yoomee';
    if (n.contains('nexttel'))                      return '';      // Nexttel disparu → exclu
    return name;
  }

  // Retourne la couleur de marque de l'opérateur pour les graphiques
  Color _operatorColor(String name) {
    final n = name.toLowerCase();
    if (n.contains('mtn'))    return const Color(0xFFF59E0B); // Jaune MTN
    if (n.contains('orange')) return const Color(0xFFFF6B35); // Orange
    if (n.contains('blue'))   return const Color(0xFF0057A8); // Bleu Camtel
    return const Color(0xFF00D4FF); // Cyan par défaut
  }
}

// ─── Accumulateur de statistiques par opérateur ───────────────────────────────
// Agrège les métriques de toutes les mesures d'un même opérateur
class _OpStats {
  final String name;             // Nom normalisé de l'opérateur
  int count = 0;                 // Nombre total de mesures
  DateTime? lastAt;              // Date de la mesure la plus récente
  final List<double> dls        = []; // Liste des débits descendants en Mbps
  final List<double> latencies  = []; // Liste des latences en ms
  final List<double> jitters    = []; // Liste des gigues en ms
  final List<double> signals    = []; // Liste des RSRP en dBm

  _OpStats(this.name);

  // Ajoute une mesure à l'accumulateur
  void add({
    required double? dl,
    required double? latencyMs,
    required double? jitterMs,
    required double? signalRsrpDbm,
    required DateTime measuredAt,
  }) {
    count++;
    // Garde la date la plus récente
    if (lastAt == null || measuredAt.isAfter(lastAt!)) lastAt = measuredAt;
    // N'ajoute que les valeurs disponibles (null = mesure échouée)
    if (dl            != null) dls.add(dl);
    if (latencyMs     != null) latencies.add(latencyMs);
    if (jitterMs      != null) jitters.add(jitterMs);
    if (signalRsrpDbm != null) signals.add(signalRsrpDbm);
  }

  // Getters calculant la moyenne arithmétique de chaque liste
  double? get avgDl      =>
      dls.isEmpty       ? null : dls.reduce((a, b)      => a + b) / dls.length;
  double? get avgLatency =>
      latencies.isEmpty ? null : latencies.reduce((a, b) => a + b) / latencies.length;
  double? get avgJitter  =>
      jitters.isEmpty   ? null : jitters.reduce((a, b)   => a + b) / jitters.length;
  double? get avgSignal  =>
      signals.isEmpty   ? null : signals.reduce((a, b)   => a + b) / signals.length;
}
