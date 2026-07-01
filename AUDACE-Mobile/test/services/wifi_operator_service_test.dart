import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:netprobe/services/wifi_operator_service.dart';

// ─── Doubles de test ────────────────────────────────────────────────────────

class _FakeNetworkInfo implements NetworkInfo {
  final String? gatewayIp;
  final String? ssid;
  _FakeNetworkInfo({this.gatewayIp, this.ssid});

  @override Future<String?> getWifiGatewayIP() async => gatewayIp;
  @override Future<String?> getWifiName() async => ssid;

  // Stubs obligatoires — non utilisés dans ces tests
  @override Future<String?> getWifiBSSID() async => null;
  @override Future<String?> getWifiIP() async => null;
  @override Future<String?> getWifiIPv6() async => null;
  @override Future<String?> getWifiSubmask() async => null;
  @override Future<String?> getWifiBroadcast() async => null;
}

// Fabrique un client HTTP simulé qui retourne toujours la même réponse
Future<http.Response> Function(Uri, {Map<String, String>? headers})
    _httpRepondant(int status, String body) =>
        (Uri uri, {Map<String, String>? headers}) async =>
            http.Response(body, status);

// Client HTTP qui lance toujours une exception (timeout / hors ligne)
Future<http.Response> Function(Uri, {Map<String, String>? headers})
    get _httpHorsLigne =>
        (Uri _, {Map<String, String>? headers}) =>
            Future.error(Exception('réseau indisponible'));

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('WifiOperatorService — détection via API modem Huawei', () {
    test('retourne le nom de l\'opérateur depuis <FullName>', () async {
      const xmlHuawei = '''<?xml version="1.0"?>
<response><State>0</State><FullName>MTN Cameroon</FullName>
<ShortName>MTN</ShortName><Numeric>62401</Numeric></response>''';

      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: '192.168.8.1'),
        httpGet: _httpRepondant(200, xmlHuawei),
      );

      final result = await service.detectOperator();
      expect(result.name, 'MTN Cameroon');
      expect(result.source, WifiDetectionSource.modemApi);
    });

    test('tombe sur <ShortName> si <FullName> est absent', () async {
      const xml = '<response><ShortName>Orange</ShortName></response>';
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: '192.168.1.1'),
        httpGet: _httpRepondant(200, xml),
      );
      final result = await service.detectOperator();
      expect(result.name, 'Orange');
      expect(result.source, WifiDetectionSource.modemApi);
    });

    test('ignore une réponse 404 et passe à la méthode suivante', () async {
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: '192.168.8.1', ssid: 'MTN-Box'),
        httpGet: _httpRepondant(404, ''),
      );
      final result = await service.detectOperator();
      // Modem API échoue → SSID parsing
      expect(result.source, WifiDetectionSource.ssid);
      expect(result.name, 'MTN Cameroon');
    });
  });

  group('WifiOperatorService — lookup ASN (HTTPS)', () {
    test('extrait le nom depuis ipapi.co (champ org propre)', () async {
      // ipapi.co retourne "MTN Cameroon" sans préfixe AS
      const json = '{"ip":"105.235.0.1","org":"MTN Cameroon","asn":"AS36873"}';
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: null),
        httpGet: _httpRepondant(200, json),
      );
      final result = await service.detectOperator();
      expect(result.name, 'MTN Cameroon');
      expect(result.source, WifiDetectionSource.asnLookup);
    });

    test('nettoie le préfixe AS depuis ipinfo.io', () async {
      // ipinfo.io retourne "AS36873 MTN Cameroon"
      const json = '{"ip":"105.235.0.1","org":"AS36873 MTN Cameroon"}';
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: null),
        httpGet: _httpRepondant(200, json),
      );
      final result = await service.detectOperator();
      expect(result.name, 'MTN Cameroon');
    });

    test('normalise "Orange S.A." en "Orange Cameroun"', () async {
      const json = '{"org":"Orange S.A."}';
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: null),
        httpGet: _httpRepondant(200, json),
      );
      final result = await service.detectOperator();
      expect(result.name, 'Orange Cameroun');
    });

    test('ignore un org inconnu ("Public Yaoundé") et passe au SSID', () async {
      // Le lookup ASN retourne un nom d'organisation non reconnu.
      // On doit ignorer ce résultat et continuer avec la détection SSID.
      const json = '{"org":"Public Yaoundé"}';
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(
          gatewayIp: null,
          ssid: 'MTN-4G-Box',          // le SSID contient MTN → doit gagner
        ),
        httpGet: _httpRepondant(200, json),
      );
      final result = await service.detectOperator();
      expect(result.name, 'MTN Cameroon');
      expect(result.source, WifiDetectionSource.ssid);
    });

    test('org inconnu sans SSID reconnaissable → résultat inconnu', () async {
      const json = '{"org":"Public Yaoundé"}';
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: null, ssid: 'MonReseau'),
        httpGet: _httpRepondant(200, json),
      );
      final result = await service.detectOperator();
      expect(result.source, WifiDetectionSource.inconnu);
    });

    test('normalise "Blue by Camtel" depuis ASN', () async {
      const json = '{"org":"AS36932 Blue by Camtel"}';
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: null),
        httpGet: _httpRepondant(200, json),
      );
      final result = await service.detectOperator();
      expect(result.name, 'Blue');
      expect(result.source, WifiDetectionSource.asnLookup);
    });

    test('normalise "Yoomee SA" depuis ASN', () async {
      const json = '{"org":"AS37590 Yoomee SA"}';
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: null),
        httpGet: _httpRepondant(200, json),
      );
      final result = await service.detectOperator();
      expect(result.name, 'Yoomee');
      expect(result.source, WifiDetectionSource.asnLookup);
    });

    test('passe au second endpoint si le premier échoue', () async {
      // Le premier appel (ipapi.co) échoue, le second (ipinfo.io) répond
      int appels = 0;
      Future<http.Response> httpSelectif(Uri uri,
          {Map<String, String>? headers}) async {
        appels++;
        if (appels == 1) throw Exception('timeout');
        return http.Response('{"org":"MTN Cameroon"}', 200);
      }

      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: null),
        httpGet: httpSelectif,
      );
      final result = await service.detectOperator();
      expect(result.name, 'MTN Cameroon');
      expect(result.source, WifiDetectionSource.asnLookup);
    });
  });

  group('WifiOperatorService — détection via SSID', () {
    test('reconnaît MTN dans le nom du réseau', () async {
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(ssid: '"MTN-FastBox"'),
        httpGet: _httpHorsLigne,
      );
      final result = await service.detectOperator();
      expect(result.name, 'MTN Cameroon');
      expect(result.source, WifiDetectionSource.ssid);
    });

    test('reconnaît Orange dans le SSID (insensible à la casse)', () async {
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(ssid: 'orange_home'),
        httpGet: _httpHorsLigne,
      );
      final result = await service.detectOperator();
      expect(result.name, 'Orange Cameroun');
      expect(result.source, WifiDetectionSource.ssid);
    });

    test('reconnaît Camtel dans le SSID', () async {
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(ssid: 'CAMTEL_YDE'),
        httpGet: _httpHorsLigne,
      );
      final result = await service.detectOperator();
      expect(result.name, 'Camtel');
    });

    test('reconnaît Nexttel dans le SSID', () async {
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(ssid: 'NEXTTEL_WIFI'),
        httpGet: _httpHorsLigne,
      );
      final result = await service.detectOperator();
      expect(result.name, 'Nexttel');
    });

    test('reconnaît Blue dans le SSID', () async {
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(ssid: 'Blue_Home'),
        httpGet: _httpHorsLigne,
      );
      final result = await service.detectOperator();
      expect(result.name, 'Blue');
      expect(result.source, WifiDetectionSource.ssid);
    });

    test('reconnaît Yoomee dans le SSID', () async {
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(ssid: 'Yoomee_Box'),
        httpGet: _httpHorsLigne,
      );
      final result = await service.detectOperator();
      expect(result.name, 'Yoomee');
      expect(result.source, WifiDetectionSource.ssid);
    });
  });

  group('WifiOperatorService — repli et cas limites', () {
    test('retourne WiFi/inconnu si toutes les méthodes échouent', () async {
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(ssid: 'MonReseau'),
        httpGet: _httpHorsLigne,
      );
      final result = await service.detectOperator();
      expect(result.name, 'WiFi');
      expect(result.source, WifiDetectionSource.inconnu);
    });

    test('ne plante pas si NetworkInfo lance une exception', () async {
      final service = WifiOperatorService(
        netInfo: _NetworkInfoDefaillant(),
        httpGet: _httpHorsLigne,
      );
      final result = await service.detectOperator();
      expect(result, isNotNull);
      expect(result.source, WifiDetectionSource.inconnu);
    });

    test('l\'ordre de priorité est : modem > ASN > SSID', () async {
      // Le modem répond correctement → doit prendre le dessus sur SSID "Orange"
      const xml = '<response><FullName>MTN Cameroon</FullName></response>';
      final service = WifiOperatorService(
        netInfo: _FakeNetworkInfo(gatewayIp: '192.168.8.1', ssid: 'Orange-Wifi'),
        httpGet: _httpRepondant(200, xml),
      );
      final result = await service.detectOperator();
      expect(result.name, 'MTN Cameroon');
      expect(result.source, WifiDetectionSource.modemApi);
    });
  });
}

// NetworkInfo qui lève une exception sur tous les appels
class _NetworkInfoDefaillant implements NetworkInfo {
  @override Future<String?> getWifiGatewayIP() => Future.error(Exception('plugin absent'));
  @override Future<String?> getWifiName() => Future.error(Exception('plugin absent'));
  @override Future<String?> getWifiBSSID() async => null;
  @override Future<String?> getWifiIP() async => null;
  @override Future<String?> getWifiIPv6() async => null;
  @override Future<String?> getWifiSubmask() async => null;
  @override Future<String?> getWifiBroadcast() async => null;
}
