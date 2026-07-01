// Service d'export des mesures réseau au format JSON.
// Propose trois modes : sauvegarde sur l'appareil, partage via feuille native, copie en mémoire.

// lib/services/export_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/network_metrics.dart';

class ExportService {
  // Singleton — une seule instance dans toute l'application
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  // Génère le JSON bien indenté (2 espaces) et le retourne en String
  String generateJson(NetworkMetrics metrics) {
    const encoder = JsonEncoder.withIndent('  '); // Indentation de 2 espaces
    return encoder.convert(metrics.toJson());
  }

  // Sauvegarde le fichier JSON dans le dossier AUDACE/ sur l'appareil.
  // Retourne le chemin absolu du fichier créé.
  Future<String> saveToDevice(NetworkMetrics metrics) async {
    final jsonStr = generateJson(metrics);
    final filename = _buildFilename(metrics); // Ex: audace_MTN_20240101_120000.json

    Directory dir;
    // Sur Android, préférer le stockage externe (visible dans le gestionnaire de fichiers)
    // Si indisponible (certains appareils/configurations), utiliser le stockage interne
    if (Platform.isAndroid) {
      dir =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      // Sur iOS, seul le répertoire Documents est accessible
      dir = await getApplicationDocumentsDirectory();
    }

    // Crée le sous-dossier AUDACE/ s'il n'existe pas encore
    final subfolder = Directory('${dir.path}/AUDACE');
    if (!await subfolder.exists()) await subfolder.create(recursive: true);

    // Écrit le fichier en UTF-8 pour préserver les caractères accentués
    final file = File('${subfolder.path}/$filename');
    await file.writeAsString(jsonStr, encoding: utf8);

    return file.path;
  }

  // Partage le fichier via la feuille de partage native (WhatsApp, email, Drive…)
  Future<void> shareFile(NetworkMetrics metrics) async {
    final jsonStr = generateJson(metrics);
    final filename = _buildFilename(metrics);

    // Écrit d'abord dans un fichier temporaire (Share requiert un chemin de fichier)
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$filename');
    await tempFile.writeAsString(jsonStr, encoding: utf8);

    // Ouvre la feuille de partage native avec le type MIME JSON
    await Share.shareXFiles(
      [XFile(tempFile.path, mimeType: 'application/json')],
      subject: 'Rapport AUDACE - $filename',
      text:
          'Métriques réseau collectées par AUDACE\n'
          'Opérateur : ${metrics.operatorName}\n'
          'Date : ${metrics.context.timestamp}',
    );
  }

  // Retourne le JSON en String — utilisé pour copier dans le presse-papier
  String getJsonString(NetworkMetrics metrics) => generateJson(metrics);

  // Construit le nom du fichier à partir de l'opérateur et de la date/heure
  String _buildFilename(NetworkMetrics metrics) {
    // Format de date : yyyyMMdd_HHmmss (ex: 20240615_143022)
    final date = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    // Nettoie le nom de l'opérateur pour l'utiliser dans un nom de fichier
    final op = metrics.operatorName
        .replaceAll(' ', '_')                 // Remplace les espaces par _
        .replaceAll(RegExp(r'[^\w]'), '');    // Supprime les caractères non alphanumériques
    return 'audace_${op}_$date.json';
  }
}
