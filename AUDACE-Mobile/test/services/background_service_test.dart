// test/services/background_service_test.dart
// Vérifie la logique du service background (BackgroundCycleRunner) :
// gestion des erreurs, verrou anti-concurrence, notifications et événements UI.
// Aucun plugin natif requis — toutes les dépendances sont injectées via lambdas.

import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netprobe/services/background_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Double de test pour ServiceInstance
// Enregistre les appels à invoke() et setForegroundNotificationInfo()
// ─────────────────────────────────────────────────────────────────────────────
class FakeServiceInstance extends ServiceInstance {
  final List<({String method, Map<String, dynamic>? args})> invoked = [];
  final List<({String title, String content})> notifications       = [];

  @override
  void invoke(String method, [Map<String, dynamic>? args]) {
    invoked.add((method: method, args: args));
  }

  @override
  Stream<Map<String, dynamic>?> on(String method) => const Stream.empty();

  @override
  Future<void> stopSelf() async {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

// Runner précâblé pour les scénarios de succès
BackgroundCycleRunner _runnerOk({
  int pending = 0,
  int sent    = 5,
}) {
  return BackgroundCycleRunner(
    collect:  () async {},  // collecte instantanée, sans erreur
    getStats: () async => {'pending': pending, 'sent': sent},
    enqueue:  (_, __) async {},
  );
}

// Runner dont la collecte lance une Exception
BackgroundCycleRunner _runnerException() {
  return BackgroundCycleRunner(
    collect:  () async => throw Exception('réseau inaccessible'),
    getStats: () async => {},
    enqueue:  (id, data) async {},
  );
}

// Runner dont la collecte lance un Error Dart (TypeError simulé)
// C'est le cas que "on Exception catch" ne capturait pas avant le fix.
BackgroundCycleRunner _runnerError() {
  return BackgroundCycleRunner(
    collect:  () async => throw StateError('état invalide simulé'),
    getStats: () async => {},
    enqueue:  (id, data) async {},
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  group('BackgroundCycleRunner — cycle réussi', () {
    test('émet l\'événement collectionDone après un cycle réussi', () async {
      final runner  = _runnerOk(pending: 0, sent: 3);
      final service = FakeServiceInstance();

      await runner.runCycle(service);

      final done = service.invoked.where((e) => e.method == 'collectionDone');
      expect(done, hasLength(1));
      expect(done.first.args?['success'], isTrue);
      expect(done.first.args?['offline'], isFalse);
      expect(done.first.args?['sent'],    3);
    });

    test('signale offline=true quand des mesures sont en attente', () async {
      final runner  = _runnerOk(pending: 2, sent: 0);
      final service = FakeServiceInstance();

      await runner.runCycle(service);

      final done = service.invoked.firstWhere((e) => e.method == 'collectionDone');
      expect(done.args?['offline'],  isTrue);
      expect(done.args?['pending'],  2);
      expect(done.args?['success'],  isFalse);
    });

    test('le verrou est libéré après un cycle réussi', () async {
      final runner  = _runnerOk();
      final service = FakeServiceInstance();

      expect(runner.enCours, isFalse);
      await runner.runCycle(service);
      expect(runner.enCours, isFalse);
    });
  });

  group('BackgroundCycleRunner — gestion des erreurs', () {
    test('une Exception dans la collecte n\'empêche pas la libération du verrou',
        () async {
      final runner  = _runnerException();
      final service = FakeServiceInstance();

      await runner.runCycle(service); // ne doit pas lever

      expect(runner.enCours, isFalse,
          reason: 'le verrou doit être libéré même après une Exception');
    });

    test(
      'un Error Dart (StateError) dans la collecte n\'empêche pas la libération du verrou',
      () async {
        // RÉGRESSION : avant le fix, "on Exception catch" laissait propager
        // les Error Dart et pouvait crasher l\'isolat du service.
        final runner  = _runnerError();
        final service = FakeServiceInstance();

        await runner.runCycle(service); // ne doit pas lever

        expect(runner.enCours, isFalse,
            reason: 'le verrou doit être libéré même après un Error Dart');
      },
    );

    test('une Exception dans la collecte n\'émet PAS d\'événement collectionDone',
        () async {
      final runner  = _runnerException();
      final service = FakeServiceInstance();

      await runner.runCycle(service);

      final done = service.invoked.where((e) => e.method == 'collectionDone');
      expect(done, isEmpty,
          reason: 'collectionDone ne doit pas être émis en cas d\'erreur');
    });

    test('les erreurs sont enfilées dans SQLite pour le monitoring', () async {
      final List<String> enqueued = [];
      final runner = BackgroundCycleRunner(
        collect:  () async => throw Exception('timeout'),
        getStats: () async => {},
        enqueue:  (id, _) async => enqueued.add(id),
      );
      final service = FakeServiceInstance();

      await runner.runCycle(service);

      expect(enqueued, hasLength(1));
      expect(enqueued.first, startsWith('bg_error_'));
    });

    test('si l\'enqueue lui-même échoue, le cycle reste silencieux', () async {
      final runner = BackgroundCycleRunner(
        collect:  () async => throw Exception('erreur collecte'),
        getStats: () async => {},
        enqueue:  (_, __) async => throw Exception('SQLite indisponible'),
      );
      final service = FakeServiceInstance();

      // Ne doit pas lever même si enqueue échoue
      await expectLater(runner.runCycle(service), completes);
      expect(runner.enCours, isFalse);
    });
  });

  group('BackgroundCycleRunner — verrou anti-concurrence', () {
    test('un second appel concurrent est rejeté immédiatement', () async {
      final completer = Completer<void>();
      final runner = BackgroundCycleRunner(
        collect:  () => completer.future, // bloque jusqu'à résolution manuelle
        getStats: () async => {'pending': 0, 'sent': 0},
        enqueue:  (_, __) async {},
      );
      final service = FakeServiceInstance();

      // Lance le premier cycle sans l'attendre — il est maintenant bloqué
      final first = runner.runCycle(service);
      expect(runner.enCours, isTrue);

      // Le second appel doit retourner immédiatement (cycle ignoré)
      await runner.runCycle(service);

      // Un seul événement collectionDone au total (le second n'en émet pas)
      final done = service.invoked.where((e) => e.method == 'collectionDone');
      expect(done, isEmpty,
          reason: 'le premier cycle est encore en cours, aucun done attendu');

      // Résout le premier cycle et attend sa fin
      completer.complete();
      await first;
      expect(runner.enCours, isFalse);
    });

    test('deux runners indépendants ont des verrous indépendants', () async {
      final r1 = _runnerOk();
      final r2 = _runnerOk();
      final s1 = FakeServiceInstance();
      final s2 = FakeServiceInstance();

      await Future.wait([r1.runCycle(s1), r2.runCycle(s2)]);

      // Chacun a émis son propre événement collectionDone
      expect(s1.invoked.where((e) => e.method == 'collectionDone'), hasLength(1));
      expect(s2.invoked.where((e) => e.method == 'collectionDone'), hasLength(1));
    });
  });

  group('BackgroundCycleRunner — cycles consécutifs', () {
    test('trois cycles consécutifs réussissent tous', () async {
      final runner  = _runnerOk(pending: 0, sent: 1);
      final service = FakeServiceInstance();

      for (var i = 0; i < 3; i++) {
        await runner.runCycle(service);
      }

      final done = service.invoked.where((e) => e.method == 'collectionDone');
      expect(done, hasLength(3));
      expect(runner.enCours, isFalse);
    });

    test('un cycle réussi après un cycle en erreur s\'exécute normalement',
        () async {
      final service = FakeServiceInstance();

      // Cycle 1 : erreur
      final bad = _runnerException();
      await bad.runCycle(service);
      expect(bad.enCours, isFalse);

      // Cycle 2 : succès (runner frais, pas d'état partagé entre instances)
      final good = _runnerOk(pending: 0, sent: 1);
      await good.runCycle(service);

      final done = service.invoked.where((e) => e.method == 'collectionDone');
      expect(done, hasLength(1));
    });
  });
}
