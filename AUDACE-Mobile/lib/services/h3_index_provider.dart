// Module de cartographie — calcule l'index hexagonal H3 (Uber) correspondant
// à une position GPS, pour l'agrégation spatiale des mesures sur la carte de
// couverture du régulateur.
//
// La résolution 8 correspond à des hexagones d'environ 0.46 km² (≈700m de côté),
// cohérent avec la valeur H3AggregationEngine.defaultResolution = 8 du document technique.
//
// ARCHITECTURE : le calcul H3 réel s'appuie sur une librairie native (libh3)
// chargée dynamiquement par h3_flutter. Sur certains appareils, ce chargement
// peut échouer. SafeH3IndexProvider capture cet échec et bascule sur une
// approximation locale, pour ne jamais faire échouer une collecte à cause de la cartographie.

import 'package:h3_flutter/h3_flutter.dart';

// Résolution H3 par défaut — cohérente avec le document technique
const int kDefaultH3Resolution = 8;

// Interface abstraite du calcul d'index H3.
// Permet d'injecter une implémentation différente selon le contexte
// (vraie librairie H3, approximation, ou double de test).
abstract class H3IndexProvider {
  String compute(double lat, double lon, {int resolution = kDefaultH3Resolution});
}

// Algorithme d'approximation historique — filet de sécurité sans dépendance native.
// Arrondit les coordonnées à 2 décimales (~1.1 km de précision) et encode en
// hexadécimal pour imiter le format visuel d'un index H3.
// N'est PAS un véritable index H3 et ne doit être utilisé qu'en repli.
class ApproxH3IndexProvider implements H3IndexProvider {
  @override
  String compute(double lat, double lon, {int resolution = kDefaultH3Resolution}) {
    // Arrondi à 2 décimales pour grouper les mesures proches
    final latRounded = (lat * 100).round();
    final lonRounded = (lon * 100).round();
    // Combinaison des deux valeurs pour former un entier unique
    final combined = (latRounded.abs() * 100000 + lonRounded.abs());
    // Format similaire à H3 : "88" (préfixe résolution 8) + valeur hex + "fff"
    return '88${combined.toRadixString(16).padLeft(11, '0')}fff';
  }
}

// Véritable calcul H3 via le package h3_flutter (librairie native Uber H3).
// Utilisé en production quand la librairie native est correctement chargée.
class H3FlutterIndexProvider implements H3IndexProvider {
  // H3Factory().load() charge la librairie native (peut échouer → géré par SafeH3IndexProvider)
  H3FlutterIndexProvider() : _h3 = const H3Factory().load();

  final H3 _h3; // Instance de la librairie H3

  @override
  String compute(double lat, double lon, {int resolution = kDefaultH3Resolution}) {
    // geoToCell convertit les coordonnées GPS en index H3 (BigInt)
    final cell = _h3.geoToCell(GeoCoord(lat: lat, lon: lon), resolution);
    // Conversion en chaîne hexadécimale (format standard des index H3)
    return cell.toRadixString(16);
  }
}

// Provider de production par défaut — essaie le vrai calcul H3 avec repli automatique.
// La librairie native est initialisée au premier appel pour ne pas bloquer le démarrage
// de l'application si la librairie est absente.
class SafeH3IndexProvider implements H3IndexProvider {
  SafeH3IndexProvider({H3IndexProvider? real, H3IndexProvider? fallback})
      : _fallback = fallback ?? ApproxH3IndexProvider(), // Repli : approximation locale
        _real     = real;

  H3IndexProvider? _real;           // Librairie H3 réelle (lazy-init au premier appel)
  final H3IndexProvider _fallback;  // Approximation de secours
  bool _realUnavailable = false;    // true si la librairie native a déjà échoué

  @override
  String compute(double lat, double lon, {int resolution = kDefaultH3Resolution}) {
    if (!_realUnavailable) {
      try {
        // Initialisation paresseuse — évite le crash au démarrage si la lib est absente
        _real ??= H3FlutterIndexProvider();
        return _real!.compute(lat, lon, resolution: resolution);
      } catch (_) {
        // La librairie native n'est pas disponible — on bascule définitivement
        // sur l'approximation pour tous les appels suivants (pas de retry)
        _realUnavailable = true;
      }
    }
    // Repli sur l'algorithme d'approximation locale
    return _fallback.compute(lat, lon, resolution: resolution);
  }
}
