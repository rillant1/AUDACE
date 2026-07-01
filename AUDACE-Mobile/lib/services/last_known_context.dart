// Cache persistant du dernier contexte réseau connu (opérateur + position GPS).
// Rôle : le service background tourne dans un isolat Dart séparé sans accès
// aux canaux de méthode natifs (SIM, GPS). Ce cache permet de réutiliser
// les informations collectées lors de la dernière mesure foreground.

import 'package:shared_preferences/shared_preferences.dart';

class LastKnownContext {
  // Clés SharedPreferences pour le cache de contexte
  static const _kOperator  = 'lkc_operator'; // Nom de l'opérateur
  static const _kMcc       = 'lkc_mcc';       // Mobile Country Code
  static const _kMnc       = 'lkc_mnc';       // Mobile Network Code
  static const _kLat       = 'lkc_lat';       // Latitude GPS
  static const _kLon       = 'lkc_lon';       // Longitude GPS
  static const _kH3        = 'lkc_h3';        // Index hexagonal H3

  // Sauvegarde le contexte après une mesure foreground réussie.
  // N'écrase pas l'opérateur si le nouveau nom est vide ou "Inconnu".
  static Future<void> save({
    required String operatorName,
    required String mcc,
    required String mnc,
    double? latitude,
    double? longitude,
    String? h3Index,
  }) async {
    final p = await SharedPreferences.getInstance();
    // On ne met à jour le nom de l'opérateur que s'il est valide
    if (operatorName.isNotEmpty && operatorName != 'Inconnu') {
      await p.setString(_kOperator, operatorName);
      await p.setString(_kMcc, mcc);
      await p.setString(_kMnc, mnc);
    }
    // Les coordonnées GPS ne sont enregistrées que si disponibles
    if (latitude != null)  await p.setDouble(_kLat, latitude);
    if (longitude != null) await p.setDouble(_kLon, longitude);
    if (h3Index != null)   await p.setString(_kH3, h3Index);
  }

  // Lecture du nom de l'opérateur enregistré — chaîne vide si absent
  static Future<String>  getOperator() async =>
      (await SharedPreferences.getInstance()).getString(_kOperator) ?? '';

  // Lecture du MCC enregistré — "624" (Cameroun) si absent
  static Future<String>  getMcc()      async =>
      (await SharedPreferences.getInstance()).getString(_kMcc)      ?? '624';

  // Lecture du MNC enregistré — "??" si absent
  static Future<String>  getMnc()      async =>
      (await SharedPreferences.getInstance()).getString(_kMnc)      ?? '??';

  // Lecture de la latitude GPS — null si jamais enregistrée
  static Future<double?> getLat()      async =>
      (await SharedPreferences.getInstance()).getDouble(_kLat);

  // Lecture de la longitude GPS — null si jamais enregistrée
  static Future<double?> getLon()      async =>
      (await SharedPreferences.getInstance()).getDouble(_kLon);

  // Lecture de l'index H3 — null si jamais enregistré
  static Future<String?> getH3()       async =>
      (await SharedPreferences.getInstance()).getString(_kH3);
}
