// Service de localisation GPS.
// Récupère la position GPS du téléphone pour remplir les champs latitude,
// longitude et H3 index dans les métadonnées de contexte du rapport JSON.

import 'package:geolocator/geolocator.dart';

import 'h3_index_provider.dart';

class LocationService {
  // Singleton — une seule instance dans toute l'application
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Constructeur de test — permet d'injecter un H3IndexProvider différent
  // (ex: double de test) sans passer par le singleton de production
  LocationService.test(this._h3Provider);

  // Provider H3 par défaut : SafeH3IndexProvider (vraie librairie H3 avec repli)
  H3IndexProvider _h3Provider = SafeH3IndexProvider();

  // Retourne la position GPS actuelle.
  // Retourne null si la permission est refusée, le GPS est désactivé,
  // ou si le timeout de 10 secondes est atteint.
  Future<LocationResult?> getCurrentLocation() async {
    try {
      // Vérifie si le service de localisation est activé sur l'appareil
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null; // GPS désactivé dans les paramètres système

      // Vérifie la permission de localisation actuelle
      LocationPermission permission = await Geolocator.checkPermission();

      // Si la permission n'a pas encore été demandée → on la demande
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      // Si l'utilisateur a refusé définitivement → on ne peut plus demander
      if (permission == LocationPermission.deniedForever) return null;

      // Obtient la position avec la meilleure précision disponible (GPS + WiFi)
      // timeLimit: 10s — si le GPS ne répond pas, on retourne null plutôt que de bloquer
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy:  LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Calcule l'index H3 de la zone hexagonale (résolution 8 ≈ 0.46 km²)
      // pour l'agrégation spatiale sur le dashboard du régulateur.
      // SafeH3IndexProvider utilise la vraie librairie H3 native avec repli automatique
      // sur l'approximation (voir h3_index_provider.dart) si la librairie n'est pas disponible.
      final h3Index = _h3Provider.compute(position.latitude, position.longitude);

      return LocationResult(
        latitude:  position.latitude,
        longitude: position.longitude,
        accuracy:  position.accuracy, // Précision en mètres (ex: 15.0)
        h3Index:   h3Index,           // Index hexagonal pour l'agrégation spatiale
      );
    } catch (e) {
      // Timeout GPS, erreur permission ou autre → retourne null
      return null;
    }
  }
}

// Résultat complet de la géolocalisation
class LocationResult {
  final double latitude;  // Latitude WGS84 en degrés décimaux
  final double longitude; // Longitude WGS84 en degrés décimaux
  final double accuracy;  // Précision de la mesure en mètres (ex: 15.0)
  final String h3Index;   // Index H3 de la cellule hexagonale (résolution 8)

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.h3Index,
  });
}
