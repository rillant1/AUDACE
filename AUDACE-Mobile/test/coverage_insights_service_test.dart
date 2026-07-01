import 'package:flutter_test/flutter_test.dart';
import 'package:netprobe/services/coverage_insights_service.dart';

import 'services/fake_queue_repository.dart';

void main() {
  const service = CoverageInsightsService();

  group('computeScore', () {
    // Barème : débit(log) 30pts · latence 25pts · gigue 25pts · signal 20pts
    test('score maximum quand toutes les métriques sont au mieux', () {
      final score = service.computeScore(
        downloadMbps: 35,    // log(36)/log(36)*30 = 30 pts (plafond)
        latencyMs: 0,        // (180-0)/180*25 = 25 pts
        jitterMs: 0,         // (50-0)/50*25 = 25 pts
        signalRsrpDbm: -44,  // (-44+110)/66*20 = 20 pts
      );
      expect(score, 100);
    });

    test('score 0 quand toutes les métriques sont nulles', () {
      final score = service.computeScore(
        downloadMbps: null,
        latencyMs: null,
        jitterMs: null,
        signalRsrpDbm: null,
      );
      expect(score, 0);
    });

    test('score partiel si seulement le débit est disponible', () {
      final score = service.computeScore(
        downloadMbps: 35,
        latencyMs: null,
        jitterMs: null,
        signalRsrpDbm: null,
      );
      expect(score, 30.0); // 35 Mbps = plafond log → 30 pts max
    });

    test('scaling log : 5 Mbps donne plus de points qu\'une règle de 3 simple', () {
      final scoreLog = service.computeScore(
        downloadMbps: 5,
        latencyMs: null, jitterMs: null, signalRsrpDbm: null,
      );
      // Ancienne formule linéaire : 5/35*30 = 4.3 pts
      // Nouvelle formule log : log(6)/log(36)*30 ≈ 15 pts
      // Un débit de 5 Mbps est bon pour le Cameroun, pas nul comme dirait la règle de 3
      expect(scoreLog, greaterThan(10.0));
    });

    test('score partiel débit + latence sans gigue ni signal', () {
      final score = service.computeScore(
        downloadMbps: 35,  // 30 pts
        latencyMs: 0,      // 25 pts
        jitterMs: null,
        signalRsrpDbm: null,
      );
      expect(score, 55.0); // 30 + 25
    });

    test('gigue pénalise correctement (50 ms = 0 pt de gigue)', () {
      final score = service.computeScore(
        downloadMbps: null,
        latencyMs: null,
        jitterMs: 50,
        signalRsrpDbm: null,
      );
      expect(score, 0.0); // 50 ms = limite basse = 0 pt
    });

    test('signal fort (-44 dBm) donne 20 pts', () {
      final score = service.computeScore(
        downloadMbps: null,
        latencyMs: null,
        jitterMs: null,
        signalRsrpDbm: -44,
      );
      expect(score, closeTo(20.0, 0.1));
    });
  });

  group('buildRankingsFromDB', () {
    test('retourne une liste vide si la base est vide', () async {
      final repo = FakeQueueRepository();
      final rankings = await service.buildRankingsFromDB(repo);
      expect(rankings, isEmpty);
    });

    test('classe les opérateurs par score décroissant', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', _mesure('MTN Cameroon', dl: 25, latency: 40, avail: 95));
      await repo.enqueue('m2', _mesure('Camtel', dl: 5, latency: 120, avail: 70));
      await repo.enqueue('m3', _mesure('Orange Cameroun', dl: 15, latency: 65, avail: 88));

      final rankings = await service.buildRankingsFromDB(repo);

      expect(rankings.length, 3);
      expect(rankings[0].name, 'MTN Cameroon');
      expect(rankings[0].localScore, greaterThan(rankings[1].localScore));
      expect(rankings[1].localScore, greaterThan(rankings[2].localScore));
    });

    test('agrège correctement plusieurs mesures du même opérateur', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', _mesure('MTN Cameroon', dl: 20, latency: 50, avail: 90));
      await repo.enqueue('m2', _mesure('MTN Cameroon', dl: 30, latency: 30, avail: 100));

      final rankings = await service.buildRankingsFromDB(repo);

      expect(rankings.length, 1);
      expect(rankings[0].measurementCount, 2);
      expect(rankings[0].downloadMbps, closeTo(25.0, 0.1)); // moyenne de 20 et 30
      expect(rankings[0].latencyMs, closeTo(40.0, 0.1)); // moyenne de 50 et 30
    });

    test('ignore les entrées sans nom d\'opérateur valide', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', _mesure('', dl: 20, latency: 50, avail: 90));
      await repo.enqueue('m2', _mesure('Inconnu', dl: 20, latency: 50, avail: 90));
      await repo.enqueue('m3', _mesure('MTN Cameroon', dl: 20, latency: 50, avail: 90));

      final rankings = await service.buildRankingsFromDB(repo);
      expect(rankings.length, 1);
      expect(rankings[0].name, 'MTN Cameroon');
    });

    test('isReference est toujours false — toutes les données viennent de mesures réelles', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', _mesure('MTN Cameroon', dl: 20, latency: 50, avail: 90));

      final rankings = await service.buildRankingsFromDB(repo);
      expect(rankings.every((op) => op.isReference == false), isTrue);
    });

    // ── Non-régression : vrai format produit par NetworkMetrics.toJson() ─────
    // Le nom de l'opérateur est sous json['operateur']['nom'], pas json['nom'].
    // Ce test a été ajouté après découverte du bug qui faisait ignorer toutes
    // les vraies mesures (seules les données démo, au format plat, s'affichaient).
    test('lit le nom depuis json[operateur][nom] — format réel de NetworkMetrics', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', _mesureReelle('Orange Cameroun', dl: 18, latency: 55, avail: 92));

      final rankings = await service.buildRankingsFromDB(repo);
      expect(rankings.length, 1, reason: 'la mesure réelle doit être lue, pas ignorée');
      expect(rankings[0].name, 'Orange Cameroun');
    });

    test('combine mesures démo (nom à la racine) et mesures réelles (operateur.nom)', () async {
      final repo = FakeQueueRepository();
      // Format démo — utilisé par HexCoverageService.seedDemoData()
      await repo.enqueue('demo', _mesure('MTN Cameroon', dl: 22, latency: 45, avail: 95));
      // Format réel — produit par MetricsService.collectAllMetrics()
      await repo.enqueue('reel', _mesureReelle('Orange Cameroun', dl: 14, latency: 70, avail: 88));

      final rankings = await service.buildRankingsFromDB(repo);
      expect(rankings.length, 2);
      final noms = rankings.map((r) => r.name).toSet();
      expect(noms, containsAll(['MTN Cameroon', 'Orange Cameroun']));
    });

    // ── Non-régression opérateurs Blue et Yoomee ─────────────────────────────
    test('normalise "Camtel" et "Blue" en un seul opérateur "Blue"', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', _mesure('Camtel',    dl: 8, latency: 110, avail: 80));
      await repo.enqueue('m2', _mesure('Blue',      dl: 10, latency: 100, avail: 85));
      await repo.enqueue('m3', _mesure('Blue by Camtel', dl: 9, latency: 105, avail: 82));

      final rankings = await service.buildRankingsFromDB(repo);
      expect(rankings.length, 1, reason: 'Camtel, Blue et Blue by Camtel doivent être fusionnés');
      expect(rankings[0].name, 'Blue');
      expect(rankings[0].measurementCount, 3);
    });

    test('normalise "Yoomee" correctement et le liste séparément', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', _mesure('Yoomee',    dl: 12, latency: 90, avail: 88));
      await repo.enqueue('m2', _mesure('Yoomee SA', dl: 14, latency: 85, avail: 90));
      await repo.enqueue('m3', _mesure('MTN Cameroon', dl: 25, latency: 40, avail: 98));

      final rankings = await service.buildRankingsFromDB(repo);
      expect(rankings.length, 2);
      final noms = rankings.map((r) => r.name).toSet();
      expect(noms, containsAll(['MTN Cameroon', 'Yoomee']));
      // Les deux mesures Yoomee doivent être agrégées
      final yoomee = rankings.firstWhere((r) => r.name == 'Yoomee');
      expect(yoomee.measurementCount, 2);
    });

    // ── Correction bayésienne ─────────────────────────────────────────────────
    // Propriété fondamentale : avec peu de mesures, le score est tiré vers la moyenne.
    // Avec beaucoup de mesures, le score reste proche du score réel.

    test('bayésien : score avec 2 mesures est entre le score brut et la moyenne', () async {
      final repo = FakeQueueRepository();
      // Orange : 2 mesures parfaites (journée exceptionnelle)
      await repo.enqueue('o1', _mesure('Orange Cameroun', dl: 35, latency: 0,  avail: 100));
      await repo.enqueue('o2', _mesure('Orange Cameroun', dl: 35, latency: 0,  avail: 100));
      // MTN : 30 mesures solides mais pas parfaites
      for (var i = 0; i < 30; i++) {
        await repo.enqueue('m$i', _mesure('MTN Cameroon', dl: 18, latency: 60, avail: 90));
      }

      final rankings = await service.buildRankingsFromDB(repo);
      final orange = rankings.firstWhere((r) => r.name == 'Orange Cameroun');
      final mtn    = rankings.firstWhere((r) => r.name == 'MTN Cameroon');

      // Score brut Orange est bien plus élevé (conditions parfaites)
      final rawOrange = service.computeScore(downloadMbps: 35, latencyMs: 0,  jitterMs: null, signalRsrpDbm: null);
      final rawMtn    = service.computeScore(downloadMbps: 18, latencyMs: 60, jitterMs: null, signalRsrpDbm: null);
      expect(rawOrange, greaterThan(rawMtn));

      // Mais le score bayésien d'Orange (2 mesures) doit être tiré vers la moyenne,
      // donc l'écart se réduit nettement par rapport à l'écart brut
      final ecartBrut    = rawOrange - rawMtn;
      final ecartBayesien = orange.localScore - mtn.localScore;
      expect(ecartBayesien, lessThan(ecartBrut),
        reason: 'La correction bayésienne doit réduire l\'écart entre les opérateurs');
    });

    test('bayésien : un opérateur avec 300 mesures conserve presque son score brut', () async {
      final repo = FakeQueueRepository();
      for (var i = 0; i < 300; i++) {
        await repo.enqueue('m$i', _mesure('MTN Cameroon', dl: 20, latency: 50, avail: 95));
      }
      final rankings = await service.buildRankingsFromDB(repo);
      final rawScore = service.computeScore(
        downloadMbps: 20, latencyMs: 50, jitterMs: null, signalRsrpDbm: null,
      );
      // Avec 300 mesures et k=30 : 300/(300+30) = 91% du score reste le score réel
      expect(rankings[0].localScore, closeTo(rawScore, 2.0));
    });

    test('bayésien : réduit avantage d\'un opérateur avec très peu de mesures', () async {
      final repo = FakeQueueRepository();
      // Yoomee : 3 mesures avec score élevé (petit échantillon non représentatif)
      await repo.enqueue('y1', _mesure('Yoomee', dl: 30, latency: 20, avail: 100));
      await repo.enqueue('y2', _mesure('Yoomee', dl: 28, latency: 25, avail: 100));
      await repo.enqueue('y3', _mesure('Yoomee', dl: 32, latency: 18, avail: 100));
      // MTN : 120 mesures avec score légèrement inférieur
      for (var i = 0; i < 120; i++) {
        await repo.enqueue('m$i', _mesure('MTN Cameroon', dl: 20, latency: 55, avail: 92));
      }

      final rankings = await service.buildRankingsFromDB(repo);
      final yoomee = rankings.firstWhere((r) => r.name == 'Yoomee');
      final mtn    = rankings.firstWhere((r) => r.name == 'MTN Cameroon');

      // Le score bayésien de Yoomee (3 mesures) est nettement inférieur à son score brut
      final rawYoomee = service.computeScore(downloadMbps: 30, latencyMs: 21, jitterMs: null, signalRsrpDbm: null);
      expect(yoomee.localScore, lessThan(rawYoomee),
        reason: 'Avec seulement 3 mesures, Yoomee doit être tiré vers la moyenne');
      // Et l'écart entre les deux est inférieur à l'écart brut
      final rawMtn = service.computeScore(downloadMbps: 20, latencyMs: 55, jitterMs: null, signalRsrpDbm: null);
      expect(yoomee.localScore - mtn.localScore, lessThan(rawYoomee - rawMtn));
    });

    test('exclut Nexttel des classements', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', _mesure('Nexttel',      dl: 5, latency: 200, avail: 60));
      await repo.enqueue('m2', _mesure('MTN Cameroon', dl: 25, latency: 40, avail: 98));

      final rankings = await service.buildRankingsFromDB(repo);
      expect(rankings.length, 1);
      expect(rankings[0].name, 'MTN Cameroon');
    });
  });
}

/// Format démo (flat) — utilisé par HexCoverageService.seedDemoData()
Map<String, dynamic> _mesure(
  String operator, {
  required double dl,
  required double latency,
  required double avail,
}) {
  return {
    'identifiant_mesure': 'test-${DateTime.now().microsecondsSinceEpoch}',
    'nom': operator,
    'horodatage': DateTime.now().toIso8601String(),
    'metadonnees_contexte': {
      'h3_index': '88abc123fff',
      'coordonnees': {'latitude': 3.84, 'longitude': 11.50},
    },
    'connectivite_qos': {
      'debit_descendant_mbps': dl,
      'debit_montant_mbps': dl / 3,
      'latence_ms': latency,
    },
    'experience_utilisateur_qoe': {
      'http_success_rate_pct': avail,
    },
  };
}

/// Format réel — produit par NetworkMetrics.toJson() via MetricsService
Map<String, dynamic> _mesureReelle(
  String operator, {
  required double dl,
  required double latency,
  required double avail,
}) {
  return {
    'schema_version': '1.1.0',
    'generated_at': DateTime.now().toIso8601String(),
    'operateur': {
      'nom': operator,
      'mcc': '624',
      'mnc': '02',
      'pays_iso': 'CM',
      'en_roaming': false,
    },
    'session_active': {'type': 'mobile'},
    'signal_radio': {'disponible': true, 'technologie': 'LTE', 'signal_barres': 3},
    'connectivite_qos': {
      'debit_descendant_mbps': dl,
      'debit_montant_mbps': dl / 3,
      'latence_ms': latency,
      'gigue_ms': null,
      'taux_perte_paquets': null,
    },
    'experience_utilisateur_qoe': {
      'http_success_rate_pct': avail,
    },
    'metadonnees_contexte': {
      'h3_index': null,
      'coordonnees': null,
      'horodatage_iso': DateTime.now().toIso8601String(),
      'terminal': {'marque': 'Xiaomi', 'modele': '220233L2G'},
      'systeme': {'type': 'Android', 'version': 'Android 11 (API 30)'},
      'batterie': {'niveau_pct': 82, 'en_charge': false},
      'version_application': '1.0.0',
      'identifiant_anonyme': 'abc123',
    },
    'device_metric_id': 'uuid-test-001',
  };
}
