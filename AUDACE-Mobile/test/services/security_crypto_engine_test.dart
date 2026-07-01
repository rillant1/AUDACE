// test/services/security_crypto_engine_test.dart
// Vérifie le module de chiffrement et d'anonymisation locale :
// déterminisme du hash, stabilité du sel persistant, non-réversibilité.

import 'package:flutter_test/flutter_test.dart';
import 'package:netprobe/services/security_crypto_engine.dart';

void main() {
  group('SecurityCryptoEngine', () {
    test('hashDeviceAnonymously est déterministe pour les mêmes entrées', () {
      final engine = SecurityCryptoEngine.test(InMemorySaltStore());
      final h1 = engine.hashDeviceAnonymously('uuid-1', 'sel-1');
      final h2 = engine.hashDeviceAnonymously('uuid-1', 'sel-1');
      expect(h1, equals(h2));
    });

    test('hashDeviceAnonymously change si l\'identifiant change', () {
      final engine = SecurityCryptoEngine.test(InMemorySaltStore());
      final h1 = engine.hashDeviceAnonymously('uuid-1', 'sel-1');
      final h2 = engine.hashDeviceAnonymously('uuid-2', 'sel-1');
      expect(h1, isNot(equals(h2)));
    });

    test('hashDeviceAnonymously change si le sel change', () {
      final engine = SecurityCryptoEngine.test(InMemorySaltStore());
      final h1 = engine.hashDeviceAnonymously('uuid-1', 'sel-1');
      final h2 = engine.hashDeviceAnonymously('uuid-1', 'sel-2');
      expect(h1, isNot(equals(h2)));
    });

    test('produit un hash SHA-256 valide (64 caractères hexadécimaux)', () {
      final engine = SecurityCryptoEngine.test(InMemorySaltStore());
      final hash = engine.hashDeviceAnonymously('uuid-1', 'sel-1');
      expect(hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('le hash ne contient jamais l\'identifiant source en clair', () {
      final engine = SecurityCryptoEngine.test(InMemorySaltStore());
      const installationId = 'identifiant-source-secret';
      final hash = engine.hashDeviceAnonymously(installationId, 'sel-1');
      expect(hash.contains(installationId), isFalse);
    });

    test(
      'getAnonymousDeviceId génère et persiste le couple identifiant+sel',
      () async {
        final store = InMemorySaltStore();
        final engine = SecurityCryptoEngine.test(store);

        expect(await store.readInstallationId(), isNull);
        expect(await store.readSalt(), isNull);

        final id = await engine.getAnonymousDeviceId();

        expect(await store.readInstallationId(), isNotNull);
        expect(await store.readSalt(), isNotNull);
        expect(id.length, 64);
      },
    );

    test(
      'getAnonymousDeviceId retourne le même identifiant à chaque appel '
      '(stabilité du sel persistant)',
      () async {
        final store = InMemorySaltStore();
        final engine = SecurityCryptoEngine.test(store);

        final id1 = await engine.getAnonymousDeviceId();
        final id2 = await engine.getAnonymousDeviceId();

        expect(id1, equals(id2));
      },
    );

    test(
      'deux instances partageant le même store produisent le même identifiant',
      () async {
        final store = InMemorySaltStore();
        final engineA = SecurityCryptoEngine.test(store);
        final engineB = SecurityCryptoEngine.test(store);

        final idA = await engineA.getAnonymousDeviceId();
        final idB = await engineB.getAnonymousDeviceId();

        expect(idA, equals(idB));
      },
    );

    test(
      'deux stores différents produisent des identifiants différents '
      '(pas de fuite entre appareils simulés)',
      () async {
        final engineA = SecurityCryptoEngine.test(InMemorySaltStore());
        final engineB = SecurityCryptoEngine.test(InMemorySaltStore());

        final idA = await engineA.getAnonymousDeviceId();
        final idB = await engineB.getAnonymousDeviceId();

        expect(idA, isNot(equals(idB)));
      },
    );
  });
}
