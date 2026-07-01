// test/services/h3_index_provider_test.dart
// Vérifie le module de cartographie H3 : l'approximation reste stable et
// bien formée, et le repli sécurisé fonctionne quand le calcul réel échoue.

import 'package:flutter_test/flutter_test.dart';
import 'package:netprobe/services/h3_index_provider.dart';

/// Double de test simulant un échec systématique du calcul H3 réel
/// (ex. librairie native introuvable sur l'appareil).
class FailingH3IndexProvider implements H3IndexProvider {
  @override
  String compute(double lat, double lon, {int resolution = kDefaultH3Resolution}) {
    throw Exception('Librairie native H3 indisponible');
  }
}

/// Double de test simulant un calcul H3 réel qui réussit, pour vérifier
/// que SafeH3IndexProvider l'utilise en priorité.
class SucceedingH3IndexProvider implements H3IndexProvider {
  @override
  String compute(double lat, double lon, {int resolution = kDefaultH3Resolution}) {
    return 'index-h3-reel';
  }
}

void main() {
  group('ApproxH3IndexProvider', () {
    test('produit un identifiant stable pour les mêmes coordonnées', () {
      final provider = ApproxH3IndexProvider();
      final i1 = provider.compute(3.8480, 11.5021);
      final i2 = provider.compute(3.8480, 11.5021);
      expect(i1, equals(i2));
    });

    test('produit un identifiant différent pour des coordonnées différentes', () {
      final provider = ApproxH3IndexProvider();
      final i1 = provider.compute(3.8480, 11.5021);
      final i2 = provider.compute(4.0511, 9.7679);
      expect(i1, isNot(equals(i2)));
    });

    test('produit un identifiant au format hexadécimal imitant H3', () {
      final provider = ApproxH3IndexProvider();
      final index = provider.compute(3.8480, 11.5021);
      expect(index.startsWith('88'), isTrue);
      expect(index.endsWith('fff'), isTrue);
    });
  });

  group('SafeH3IndexProvider', () {
    test('retombe sur l\'approximation si le calcul réel échoue', () {
      final fallback = ApproxH3IndexProvider();
      final safe = SafeH3IndexProvider(
        real: FailingH3IndexProvider(),
        fallback: fallback,
      );

      final attendu = fallback.compute(3.8480, 11.5021);
      final obtenu = safe.compute(3.8480, 11.5021);

      expect(obtenu, equals(attendu));
    });

    test('utilise le calcul réel en priorité quand il réussit', () {
      final safe = SafeH3IndexProvider(
        real: SucceedingH3IndexProvider(),
        fallback: ApproxH3IndexProvider(),
      );

      final obtenu = safe.compute(3.8480, 11.5021);

      expect(obtenu, equals('index-h3-reel'));
    });

    test('ne retente plus le calcul réel après un premier échec', () {
      var tentatives = 0;
      final real = _CountingFailingProvider(() => tentatives++);
      final safe = SafeH3IndexProvider(real: real, fallback: ApproxH3IndexProvider());

      safe.compute(3.8480, 11.5021);
      safe.compute(3.8480, 11.5021);
      safe.compute(3.8480, 11.5021);

      expect(tentatives, equals(1));
    });
  });
}

class _CountingFailingProvider implements H3IndexProvider {
  _CountingFailingProvider(this.onAttempt);
  final void Function() onAttempt;

  @override
  String compute(double lat, double lon, {int resolution = kDefaultH3Resolution}) {
    onAttempt();
    throw Exception('Librairie native H3 indisponible');
  }
}
