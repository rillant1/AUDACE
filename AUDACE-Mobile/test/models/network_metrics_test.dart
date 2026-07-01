// test/models/network_metrics_test.dart
// Vérifie la sérialisation JSON du modèle de mesure : clés racine, et
// seuils d'interprétation RSRP / WiFi / qualité globale aux bornes.

import 'package:flutter_test/flutter_test.dart';
import 'package:netprobe/models/network_metrics.dart';

NetworkMetrics _buildMetrics({
  RadioSignalMetrics? radioSignal,
  WifiSignalMetrics? wifiSignal,
  ConnectivityMetrics? connectivity,
}) {
  return NetworkMetrics(
    radioSignal: radioSignal ?? const RadioSignalMetrics(),
    wifiSignal: wifiSignal,
    connectivity: connectivity ?? const ConnectivityMetrics(),
    qoe: const QoEMetrics(),
    context: const ContextMetadata(
      timestamp: '2026-06-16T00:00:00Z',
      deviceModel: 'Pixel',
      deviceBrand: 'Google',
      osVersion: 'Android 14',
      osType: 'Android',
      batteryLevelPct: 80,
      isCharging: false,
      appVersion: '1.0.0',
      anonymousDeviceId: 'abc123',
    ),
    operatorName: 'MTN',
    operatorMcc: '624',
    operatorMnc: '01',
    activeSession: const ActiveSession(type: 'Mobile'),
  );
}

void main() {
  group('NetworkMetrics.toJson', () {
    test('contient toutes les clés racine attendues', () {
      final json = _buildMetrics().toJson();
      expect(json.containsKey('schema_version'), isTrue);
      expect(json.containsKey('generated_at'), isTrue);
      expect(json.containsKey('operateur'), isTrue);
      expect(json.containsKey('session_active'), isTrue);
      expect(json.containsKey('signal_radio'), isTrue);
      expect(json.containsKey('connectivite_qos'), isTrue);
      expect(json.containsKey('experience_utilisateur_qoe'), isTrue);
      expect(json.containsKey('metadonnees_contexte'), isTrue);
    });

    test('n\'inclut pas signal_wifi quand absent', () {
      final json = _buildMetrics().toJson();
      expect(json.containsKey('signal_wifi'), isFalse);
    });

    test('inclut signal_wifi quand présent', () {
      final json = _buildMetrics(
        wifiSignal: const WifiSignalMetrics(
          ssid: 'Reseau',
          bssid: '00:00:00:00:00:00',
          rssiDbm: -55,
          qualityPct: 80,
          linkSpeedMbps: 100,
          frequencyMhz: 5000,
          band: '5GHz',
          ipAddress: '192.168.1.10',
          gateway: '192.168.1.1',
        ),
      ).toJson();
      expect(json.containsKey('signal_wifi'), isTrue);
    });
  });

  group('ContextMetadata — identifiant anonyme', () {
    test('expose identifiant_anonyme dans le JSON', () {
      final json = _buildMetrics().toJson();
      final contexte = json['metadonnees_contexte'] as Map<String, dynamic>;
      expect(contexte['identifiant_anonyme'], 'abc123');
    });

    test('identifiant_anonyme est null quand non fourni', () {
      const contexte = ContextMetadata(
        timestamp: '2026-06-16T00:00:00Z',
        deviceModel: 'Pixel',
        deviceBrand: 'Google',
        osVersion: 'Android 14',
        osType: 'Android',
        batteryLevelPct: 80,
        isCharging: false,
        appVersion: '1.0.0',
      );
      expect(contexte.toJson()['identifiant_anonyme'], isNull);
    });
  });

  group('RadioSignalMetrics — interprétation RSRP aux bornes', () {
    test('rsrp >= -80 dBm est Excellent', () {
      const m = RadioSignalMetrics(rsrp: -80);
      expect(m.toJson()['interpretation'], 'Excellent');
    });

    test('rsrp = -81 dBm passe à Bon', () {
      const m = RadioSignalMetrics(rsrp: -81);
      expect(m.toJson()['interpretation'], 'Bon');
    });

    test('rsrp = -90 dBm est encore Bon', () {
      const m = RadioSignalMetrics(rsrp: -90);
      expect(m.toJson()['interpretation'], 'Bon');
    });

    test('rsrp = -91 dBm passe à Faible', () {
      const m = RadioSignalMetrics(rsrp: -91);
      expect(m.toJson()['interpretation'], 'Faible');
    });

    test('rsrp = -100 dBm est encore Faible', () {
      const m = RadioSignalMetrics(rsrp: -100);
      expect(m.toJson()['interpretation'], 'Faible');
    });

    test('rsrp = -101 dBm est Très faible', () {
      const m = RadioSignalMetrics(rsrp: -101);
      expect(m.toJson()['interpretation'], 'Très faible');
    });

    test('signal indisponible si aucune donnée radio', () {
      const m = RadioSignalMetrics(unavailableReason: 'Pas de SIM');
      expect(m.isAvailable, isFalse);
      expect(m.toJson()['raison_indisponibilite'], 'Pas de SIM');
    });
  });

  group('WifiSignalMetrics — interprétation aux bornes', () {
    test('rssi >= -50 dBm est Excellent', () {
      const m = WifiSignalMetrics(
        ssid: 's', bssid: 'b', rssiDbm: -50, qualityPct: 100,
        linkSpeedMbps: 100, frequencyMhz: 5000, band: '5GHz',
        ipAddress: '0.0.0.0', gateway: '0.0.0.0',
      );
      expect(m.interpretation, 'Excellent');
    });

    test('rssi = -51 dBm passe à Bon', () {
      const m = WifiSignalMetrics(
        ssid: 's', bssid: 'b', rssiDbm: -51, qualityPct: 100,
        linkSpeedMbps: 100, frequencyMhz: 5000, band: '5GHz',
        ipAddress: '0.0.0.0', gateway: '0.0.0.0',
      );
      expect(m.interpretation, 'Bon');
    });

    test('rssi = -61 dBm passe à Acceptable', () {
      const m = WifiSignalMetrics(
        ssid: 's', bssid: 'b', rssiDbm: -61, qualityPct: 100,
        linkSpeedMbps: 100, frequencyMhz: 5000, band: '5GHz',
        ipAddress: '0.0.0.0', gateway: '0.0.0.0',
      );
      expect(m.interpretation, 'Acceptable');
    });

    test('rssi = -71 dBm passe à Faible', () {
      const m = WifiSignalMetrics(
        ssid: 's', bssid: 'b', rssiDbm: -71, qualityPct: 100,
        linkSpeedMbps: 100, frequencyMhz: 5000, band: '5GHz',
        ipAddress: '0.0.0.0', gateway: '0.0.0.0',
      );
      expect(m.interpretation, 'Faible');
    });
  });

  group('ConnectivityMetrics — qualité globale aux bornes', () {
    test('débit élevé + faible latence + faible perte = Excellente', () {
      const m = ConnectivityMetrics(
        downloadMbps: 10, latencyMs: 50, packetLossPct: 1,
      );
      expect(m.toJson()['qualite_globale'], 'Excellente');
    });

    test('valeurs moyennes donnent Bonne ou Acceptable selon le score', () {
      const m = ConnectivityMetrics(
        downloadMbps: 2, latencyMs: 150, packetLossPct: 5,
      );
      expect(m.toJson()['qualite_globale'], 'Bonne');
    });

    test('valeurs faibles sur les 3 critères donnent Acceptable (score minimal mesuré = 3)', () {
      const m = ConnectivityMetrics(
        downloadMbps: 0.5, latencyMs: 500, packetLossPct: 20,
      );
      expect(m.toJson()['qualite_globale'], 'Acceptable');
    });

    test('aucune mesure disponible donne Mauvaise (score nul)', () {
      const m = ConnectivityMetrics();
      expect(m.toJson()['qualite_globale'], 'Mauvaise');
    });
  });
}
