// Service de détection de l'opérateur WiFi réel.
// Quand l'utilisateur est connecté via une box/modem 4G (ex: modem MTN),
// l'opérateur SIM (ex: Orange) ne correspond pas à la connexion active.
// Ce service interroge l'appareil réseau lui-même pour identifier le bon opérateur.
// Cascade : API Huawei → lookup ASN → SSID → "WiFi" (inconnu)

import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

// Type de fonction http.get — permet l'injection en test
typedef HttpGetFn = Future<http.Response> Function(Uri uri, {Map<String, String>? headers});

// Résultat de la détection avec la source utilisée
class WifiOperatorResult {
  final String name;                // Nom normalisé de l'opérateur
  final WifiDetectionSource source; // Méthode qui a fourni ce résultat

  const WifiOperatorResult({required this.name, required this.source});
}

// Source de la détection — utile pour le diagnostic et la confiance du résultat
enum WifiDetectionSource {
  modemApi,  // API locale du modem Huawei (résultat le plus fiable)
  asnLookup, // ASN de l'IP publique via ipapi.co / ipinfo.io (fiable)
  ssid,      // Nom du réseau WiFi (moins fiable, basé sur une correspondance textuelle)
  inconnu,   // Aucune méthode n'a fonctionné
}

// Détecte l'opérateur réel d'une connexion WiFi en cascade.
class WifiOperatorService {
  static const _timeout = Duration(seconds: 4); // Timeout par requête

  final NetworkInfo _netInfo; // Accès aux infos réseau (SSID, passerelle…)
  final HttpGetFn _httpGet;   // Fonction http.get (injectable en test)

  WifiOperatorService({NetworkInfo? netInfo, HttpGetFn? httpGet})
      : _netInfo = netInfo ?? NetworkInfo(),
        _httpGet  = httpGet ?? http.get;

  // Lance la détection en cascade jusqu'à la première méthode réussie
  Future<WifiOperatorResult> detectOperator() async {
    // Étape 1 : récupère l'IP de la passerelle (box/routeur)
    final gatewayIp = await _gatewayIp();

    // Étape 2 : API Huawei sur la passerelle (modems 4G très courants au Cameroun)
    if (gatewayIp != null) {
      final result = await _tryHuaweiApi(gatewayIp);
      if (result != null) return result;
    }

    // Étape 3 : lookup ASN via l'IP publique de la connexion
    final asnResult = await _tryAsnLookup();
    if (asnResult != null) return asnResult;

    // Étape 4 : lecture du nom du réseau WiFi (SSID)
    final ssidResult = await _trySsid();
    if (ssidResult != null) return ssidResult;

    // Aucune méthode n'a abouti
    return const WifiOperatorResult(
      name: 'WiFi',
      source: WifiDetectionSource.inconnu,
    );
  }

  // ── Méthode 1 : API REST des modems Huawei ────────────────────────────────
  // Les modems Huawei (E5573, B525, B612…) exposent une API sans authentification.
  // Elle retourne le nom de l'opérateur 4G inséré dans le modem.
  Future<WifiOperatorResult?> _tryHuaweiApi(String gatewayIp) async {
    // Deux endpoints Huawei : l'un retourne le PLMN actuel, l'autre l'état de la connexion
    final endpoints = [
      'http://$gatewayIp/api/net/current-plmn',
      'http://$gatewayIp/api/monitoring/status',
    ];

    for (final url in endpoints) {
      try {
        final resp = await _httpGet(Uri.parse(url)).timeout(_timeout);
        if (resp.statusCode == 200) {
          // Cherche le nom complet en priorité, puis le nom court, puis le SPN
          final name = _xmlTag(resp.body, 'FullName') ??
              _xmlTag(resp.body, 'ShortName') ??
              _xmlTag(resp.body, 'Spn');
          if (name != null && name.isNotEmpty) {
            return WifiOperatorResult(
              name: name,
              source: WifiDetectionSource.modemApi,
            );
          }
        }
      } catch (_) {
        continue; // Timeout ou erreur réseau → essaie l'endpoint suivant
      }
    }
    return null;
  }

  // ── Méthode 2 : Lookup ASN via l'IP publique ──────────────────────────────
  // Détermine l'opérateur de la connexion Internet via son numéro ASN.
  // ip-api.com (HTTP) est bloqué sur Android 9+ sans cleartext policy.
  // ipapi.co et ipinfo.io offrent HTTPS gratuit → on essaie les deux.
  Future<WifiOperatorResult?> _tryAsnLookup() async {
    final endpoints = [
      (
        uri:    Uri.parse('https://ipapi.co/json/'),
        orgKey: 'org', // Retourne: "MTN Cameroon" (propre, sans préfixe AS)
      ),
      (
        uri:    Uri.parse('https://ipinfo.io/json'),
        orgKey: 'org', // Retourne: "AS36873 MTN Cameroon" (préfixe AS à enlever)
      ),
    ];

    for (final ep in endpoints) {
      try {
        final resp = await _httpGet(
          ep.uri,
          headers: {'Accept': 'application/json'},
        ).timeout(_timeout);

        if (resp.statusCode == 200) {
          final raw = _jsonField(resp.body, ep.orgKey);
          if (raw != null && raw.isNotEmpty) {
            final cleaned = _nettoyerNomIsp(raw); // Enlève le préfixe "AS12345 "
            if (cleaned.isNotEmpty) {
              return WifiOperatorResult(
                name: cleaned,
                source: WifiDetectionSource.asnLookup,
              );
            }
          }
        }
      } catch (_) {
        continue; // Timeout ou erreur → essaie le service suivant
      }
    }
    return null;
  }

  // ── Méthode 3 : Nom du réseau WiFi (SSID) ────────────────────────────────
  // Détecte l'opérateur en cherchant son nom dans le SSID du réseau connecté.
  // Moins fiable car le SSID peut être personnalisé par l'utilisateur.
  Future<WifiOperatorResult?> _trySsid() async {
    try {
      final ssid = await _netInfo.getWifiName();
      if (ssid == null || ssid.isEmpty) return null;
      // Certains appareils encadrent le SSID avec des guillemets → on les enlève
      final s = ssid.replaceAll('"', '').toUpperCase();
      if (s.contains('MTN'))     return const WifiOperatorResult(name: 'MTN Cameroon',   source: WifiDetectionSource.ssid);
      if (s.contains('ORANGE'))  return const WifiOperatorResult(name: 'Orange Cameroun', source: WifiDetectionSource.ssid);
      if (s.contains('CAMTEL'))  return const WifiOperatorResult(name: 'Camtel',          source: WifiDetectionSource.ssid);
      if (s.contains('BLUE'))    return const WifiOperatorResult(name: 'Blue',            source: WifiDetectionSource.ssid);
      if (s.contains('YOOMEE'))  return const WifiOperatorResult(name: 'Yoomee',          source: WifiDetectionSource.ssid);
      if (s.contains('NEXTTEL')) return const WifiOperatorResult(name: 'Nexttel',         source: WifiDetectionSource.ssid);
    } catch (_) {}
    return null; // SSID non reconnu comme opérateur connu
  }

  // ── Détection de l'adresse IP de la passerelle ───────────────────────────
  // Priorité 1 : lire la vraie passerelle depuis le système Android.
  // Priorité 2 : sonder les IP courantes des modems en parallèle.
  Future<String?> _gatewayIp() async {
    // Tente la lecture directe de la passerelle WiFi
    try {
      final gw = await _netInfo.getWifiGatewayIP();
      if (gw != null && gw.isNotEmpty) return gw;
    } catch (_) {}

    // Sonde les IP courantes des modems en parallèle (timeout 2s chacun)
    // 192.168.8.1  = modems Huawei 4G (E5573, B525…)
    // 192.168.1.1  = Livebox et routeurs classiques
    // 192.168.0.1  = routeurs génériques
    // 192.168.43.1 = hotspot Android natif
    // 10.0.0.1     = certains opérateurs / VPN
    const candidates = [
      '192.168.8.1',
      '192.168.1.1',
      '192.168.0.1',
      '192.168.43.1',
      '10.0.0.1',
    ];

    final futures = candidates.map((ip) async {
      try {
        final r = await _httpGet(Uri.parse('http://$ip/api/net/current-plmn'))
            .timeout(const Duration(seconds: 2));
        // 200 = répond correctement, 401 = authentification requise mais le modem est là
        if (r.statusCode == 200 || r.statusCode == 401) return ip;
      } catch (_) {}
      return null;
    });

    // Retourne la première IP qui répond (parmi celles qui ne sont pas null)
    final results = await Future.wait(futures);
    return results.firstWhere((ip) => ip != null, orElse: () => null);
  }

  // Extrait la valeur d'un tag XML simple : <FullName>MTN Cameroon</FullName>
  String? _xmlTag(String body, String tag) {
    final m = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(body);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  // Extrait la valeur d'un champ JSON simple : "org": "AS36873 MTN Cameroon"
  String? _jsonField(String body, String key) {
    final m = RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(body);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  // Nettoie le nom de l'opérateur renvoyé par les APIs ASN.
  // Supprime le préfixe "AS12345 " et normalise le nom.
  // Retourne une chaîne vide si l'opérateur n'est pas reconnu comme camerounais.
  String _nettoyerNomIsp(String raw) {
    // Enlève le préfixe "AS" + numéro + espace (ex: "AS36873 MTN" → "MTN")
    final u = raw.replaceFirst(RegExp(r'^AS\d+\s+'), '').trim().toUpperCase();
    if (u.contains('MTN'))     return 'MTN Cameroon';
    if (u.contains('ORANGE'))  return 'Orange Cameroun';
    // BLUE avant CAMTEL : "Blue by Camtel" doit retourner la marque commerciale
    if (u.contains('BLUE'))    return 'Blue';
    if (u.contains('CAMTEL'))  return 'Camtel';
    if (u.contains('YOOMEE'))  return 'Yoomee';
    if (u.contains('NEXTTEL')) return 'Nexttel';
    return ''; // Opérateur inconnu (ex: "Public Yaoundé") → méthode suivante
  }
}
