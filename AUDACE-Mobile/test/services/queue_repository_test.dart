// test/services/queue_repository_test.dart
// Valide le contrat de FakeQueueRepository (utilisée aussi par
// sync_service_test.dart) par rapport à l'interface QueueRepository.

import 'package:flutter_test/flutter_test.dart';

import 'fake_queue_repository.dart';

void main() {
  group('FakeQueueRepository', () {
    test('enqueue ajoute une mesure en attente', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', {'a': 1});
      expect(await repo.getPendingCount(), 1);
    });

    test('ignore les doublons de metricId (comportement sqflite)', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', {'a': 1});
      await repo.enqueue('m1', {'a': 2});
      expect(await repo.getPendingCount(), 1);
    });

    test('markSent retire la mesure de la liste des en attente', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', {'a': 1});
      final pending = await repo.getPending();
      await repo.markSent(pending.first.id!);
      expect(await repo.getPendingCount(), 0);
      final stats = await repo.getStats();
      expect(stats['sent'], 1);
    });

    test('markFailed incrémente retryCount et marque échouée', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', {'a': 1});
      final pending = await repo.getPending();
      await repo.markFailed(pending.first.id!);
      final stats = await repo.getStats();
      expect(stats['failed'], 1);
      expect(stats['pending'], 0);
    });

    test('requeueFailed remet en attente les échecs sous le seuil de 10', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', {'a': 1});
      final pending = await repo.getPending();
      await repo.markFailed(pending.first.id!);
      await repo.requeueFailed();
      expect(await repo.getPendingCount(), 1);
    });

    test('requeueFailed ne remet pas en attente après 10 échecs', () async {
      final repo = FakeQueueRepository();
      await repo.enqueue('m1', {'a': 1});
      final id = (await repo.getPending()).first.id!;
      for (var i = 0; i < 10; i++) {
        await repo.requeueFailed();
        await repo.markFailed(id);
      }
      await repo.requeueFailed();
      expect(await repo.getPendingCount(), 0);
    });
  });
}
