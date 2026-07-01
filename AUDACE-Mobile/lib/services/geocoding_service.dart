// Service de géocodage — convertit un nom de lieu en coordonnées GPS (et l'inverse).
// Utilise l'API Nominatim d'OpenStreetMap, restreinte au territoire camerounais.

import 'dart:convert';
import 'package:http/http.dart' as http;

// Résultat d'une recherche de lieu
class GeoSearchResult {
  final String name;        // Nom court du lieu (ex: "Yaoundé")
  final String displayName; // Nom complet avec pays (ex: "Yaoundé, Centre, Cameroun")
  final double lat;         // Latitude GPS
  final double lon;         // Longitude GPS

  const GeoSearchResult({
    required this.name,
    required this.displayName,
    required this.lat,
    required this.lon,
  });
}

class GeocodingService {
  // URL de base de l'API Nominatim (OpenStreetMap)
  static const _baseUrl        = 'https://nominatim.openstreetmap.org/search';
  static const _reverseBaseUrl = 'https://nominatim.openstreetmap.org/reverse';

  // En-têtes requis par Nominatim : User-Agent obligatoire pour identifier l'application
  // Langue fr pour recevoir les noms de lieux en français
  static const _headers = {
    'User-Agent': 'AUDACE/1.0 ART-Cameroun contact@art.cm',
    'Accept-Language': 'fr',
  };

  // Recherche des lieux correspondant à la requête, restreinte au Cameroun.
  // Retourne une liste vide si la requête est vide, en erreur ou sans résultat.
  Future<List<GeoSearchResult>> search(String query) async {
    // Pas de requête vide
    if (query.trim().isEmpty) return [];
    try {
      // Construit l'URL avec les paramètres de recherche
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'q': query.trim(),        // Texte de recherche
        'format': 'json',         // Réponse en JSON
        'limit': '5',             // Maximum 5 résultats
        'countrycodes': 'cm',     // Restreint au Cameroun (code ISO 3166-1)
        'addressdetails': '0',    // Pas de détails d'adresse pour alléger la réponse
      });

      // Requête HTTP avec timeout de 8 secondes
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));

      // Si le serveur ne répond pas 200 OK, on retourne une liste vide
      if (response.statusCode != 200) return [];

      // Désérialise le tableau JSON de résultats
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;

      // Convertit chaque entrée JSON en GeoSearchResult
      return data.map((item) {
        final m = item as Map<String, dynamic>;
        return GeoSearchResult(
          // "name" peut être absent sur certains résultats → fallback sur display_name
          name: m['name'] as String? ?? m['display_name'] as String? ?? query,
          displayName: m['display_name'] as String? ?? query,
          // Nominatim renvoie les coordonnées en String, pas en double
          lat: double.parse(m['lat'] as String),
          lon: double.parse(m['lon'] as String),
        );
      }).toList();
    } catch (_) {
      // Timeout, erreur réseau ou JSON invalide → liste vide
      return [];
    }
  }

  // Géocodage inverse — convertit des coordonnées GPS en nom de lieu lisible.
  // Retourne "Quartier, Ville" ou null si la position est inconnue / hors ligne.
  Future<String?> reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.parse(_reverseBaseUrl).replace(queryParameters: {
        'lat':            lat.toString(),
        'lon':            lon.toString(),
        'format':         'json',
        'zoom':           '14',  // niveau quartier / sous-préfecture
        'addressdetails': '1',
      });
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final m = jsonDecode(response.body) as Map<String, dynamic>;
      final addr = m['address'] as Map<String, dynamic>?;
      if (addr == null) return null;

      // Priorité des composantes d'adresse : quartier > village > ville > commune
      final part1 = addr['suburb']       as String?
                 ?? addr['neighbourhood'] as String?
                 ?? addr['village']       as String?
                 ?? addr['town']          as String?;
      final part2 = addr['city']         as String?
                 ?? addr['municipality']  as String?
                 ?? addr['county']        as String?;

      if (part1 != null && part2 != null && part1 != part2) return '$part1, $part2';
      return part1 ?? part2 ?? (m['display_name'] as String?)?.split(',').first;
    } catch (_) {
      return null; // Hors ligne ou Nominatim indisponible
    }
  }
}
