// Service de vérification des mises à jour de l'application.
// Compare le versionCode local avec celui exposé par le serveur AUDACE.
// Retourne les informations de mise à jour si une version plus récente est disponible.

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

// URL de base de l'API — même que SyncService, avec --dart-define à la compilation
const String _kApiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://82.29.172.251.nip.io/api/metrics',
);

// URL du endpoint de version : /api/app/version
// Construit en remplaçant le chemin /api/metrics par /api/app/version
String get _versionUrl =>
    _kApiBase.replaceFirst(RegExp(r'/api/metrics.*'), '/api/app/version');

// Informations sur une mise à jour disponible
class AppUpdateInfo {
  final int versionCode;    // Numéro de version distant (entier, ex: 42)
  final String versionName; // Nom de version lisible (ex: "1.4.0")
  final String downloadUrl; // URL de téléchargement de la nouvelle APK
  final String changelog;   // Notes de version (nouvelles fonctionnalités, correctifs)
  final bool mandatory;     // true si la mise à jour est obligatoire pour continuer

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    required this.changelog,
    required this.mandatory,
  });
}

class UpdateService {
  // Singleton — une seule instance dans toute l'application
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  // Canal de méthode partagé avec TelephonyService — launchUrl utilise le même canal natif
  static const _channel = MethodChannel('cm.art.netprobe/telephony');

  // Vérifie si une mise à jour est disponible sur le serveur.
  // Retourne null si la version locale est déjà à jour ou si le serveur est inaccessible.
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      // Récupère le numéro de build de l'APK installée
      final info = await PackageInfo.fromPlatform();
      // buildNumber = versionCode Android (entier défini dans build.gradle)
      final currentCode = int.tryParse(info.buildNumber) ?? 1;

      // Interroge le serveur avec timeout de 8 secondes
      final response = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 8));

      // Si le serveur ne répond pas, on considère qu'aucune mise à jour n'est disponible
      if (response.statusCode != 200) return null;

      // Désérialise la réponse JSON
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final remoteCode = (json['versionCode'] as num?)?.toInt() ?? 0;

      // Pas de mise à jour si la version locale est égale ou supérieure
      if (remoteCode <= currentCode) return null;

      // Une mise à jour est disponible — construit l'objet d'informations
      return AppUpdateInfo(
        versionCode: remoteCode,
        versionName: json['versionName'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        changelog:   json['changelog']   as String? ?? '',
        mandatory:   json['mandatory']   as bool?   ?? false,
      );
    } catch (_) {
      // Timeout, erreur réseau ou JSON invalide → pas de mise à jour signalée
      return null;
    }
  }

  // Ouvre le navigateur Android sur l'URL de téléchargement de la nouvelle APK.
  // Délégué au canal natif car Intent.ACTION_VIEW n'est pas accessible directement en Dart.
  Future<void> openDownloadUrl(String url) async {
    try {
      await _channel.invokeMethod('launchUrl', {'url': url});
    } catch (_) {}
  }
}
