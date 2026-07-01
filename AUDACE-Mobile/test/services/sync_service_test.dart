// test/services/sync_service_test.dart
// Vérifie le module de communication et synchronisation : envoi simple,
// échec serveur, mode hors-ligne, envoi par lot, ré-essai des échecs.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netprobe/services/sync_service.dart';

import 'fake_queue_repository.dart';

void main() {
  group('SyncService', () {
    test('envoie une mesure unique avec succès quand le serveur répond 201', () async {
      final repo = FakeQueueRepository();
      String? urlAppelee;
      final client = MockClient((request) async {
        urlAppelee = request.url.toString();
        return http.Response('{"ok": true}', 201);
      });
      final sync = SyncService.test(repo, client);

      final resultat = await sync.syncMetric('m1', {'valeur': 42});

      expect(resultat.success, isTrue);
      expect(resultat.offline, isFalse);
      expect(urlAppelee, Uri.parse(kApiBaseUrl).toString());
      final stats = await repo.getStats();
      expect(stats['sent'], 1);
      expect(stats['pending'], 0);
    });

    test('marque la mesure en échec quand le serveur répond une erreur', () async {
      final repo = FakeQueueRepository();
      final client = MockClient((request) async {
        return http.Response('Erreur interne', 500);
      });
      final sync = SyncService.test(repo, client);

      final resultat = await sync.syncMetric('m1', {'valeur': 42});

      expect(resultat.success, isFalse);
      final stats = await repo.getStats();
      expect(stats['failed'], 1);
    });

    test('ne tente aucun appel réseau en mode hors-ligne', () async {
      final repo = FakeQueueRepository();
      var appelReseau = false;
      final client = MockClient((request) async {
        appelReseau = true;
        return http.Response('{}', 200);
      });
      final sync = SyncService.test(
        repo,
        client,
        isOnline: () async => false,
      );

      final resultat = await sync.syncMetric('m1', {'valeur': 42});

      expect(resultat.offline, isTrue);
      expect(appelReseau, isFalse);
      final stats = await repo.getStats();
      expect(stats['pending'], 1);
    });

    test('envoie par lot quand plusieurs mesures sont en attente', () async {
      final repo = FakeQueueRepository();
      // Pré-remplit la file avec une première mesure hors-ligne, puis une
      // seconde déclenchera l'envoi par lot des deux.
      await repo.enqueue('m1', {'valeur': 1});
      await repo.enqueue('m2', {'valeur': 2});

      var requeteBatchRecue = false;
      var nombreMesuresEnvoyees = 0;
      final client = MockClient((request) async {
        requeteBatchRecue = request.url.toString().endsWith('/batch');
        final corps = jsonDecode(request.body) as Map<String, dynamic>;
        nombreMesuresEnvoyees = (corps['metrics'] as List).length;
        return http.Response(jsonEncode({'inserted': 2}), 201);
      });
      final sync = SyncService.test(repo, client);

      final resultat = await sync.onConnectivityRestored();

      expect(requeteBatchRecue, isTrue);
      expect(nombreMesuresEnvoyees, 2);
      expect(resultat.success, isTrue);
      final stats = await repo.getStats();
      expect(stats['sent'], 2);
    });

    test('ré-essaie les mesures en échec (retryCount = 1)', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', {'valeur': 1});
      final id = (await repo.getPending()).first.id!;
      await repo.markFailed(id); // retryCount = 1, status = failed

      final client = MockClient((request) async {
        return http.Response('{"ok": true}', 200);
      });
      final sync = SyncService.test(repo, client);

      final resultat = await sync.onConnectivityRestored();

      expect(resultat.success, isTrue);
      final stats = await repo.getStats();
      expect(stats['sent'], 1);
    });

    test('ré-essaie AUSSI les mesures bloquées avec retryCount >= 10', () async {
      // Régression : avant le fix, ces mesures restaient coincées pour toujours
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', {'valeur': 1});
      final id = (await repo.getPending()).first.id!;
      // Simule 10 échecs consécutifs (cas background service crashant)
      for (var i = 0; i < 10; i++) {
        await repo.markFailed(id);
      }
      final statsBloques = await repo.getStats();
      expect(statsBloques['failed'], 1);

      final client = MockClient((request) async {
        return http.Response('{"ok": true}', 200);
      });
      final sync = SyncService.test(repo, client);

      final resultat = await sync.onConnectivityRestored();

      expect(resultat.success, isTrue);
      final stats = await repo.getStats();
      expect(stats['sent'], 1);
      expect(stats['failed'], 0);
    });

    test(
      'getSyncStats reflète l\'état courant de la file d\'attente',
      () async {
        final repo = FakeQueueRepository();
        await repo.enqueue('m1', {'valeur': 1});
        final client = MockClient((request) async => http.Response('', 500));
        final sync = SyncService.test(repo, client);

        await sync.onConnectivityRestored();
        final stats = await sync.getSyncStats();

        expect(stats['failed'], 1);
      },
    );
  });
}
