// lib/services/sync_service.dart
// Service de synchronisation des mesures vers le backend AUDACE.
// Gère la file SQLite locale → envoi HTTP → gestion des erreurs → retry.
// Backend : Express + MongoDB sur VPS (HTTPS via Nginx + Let's Encrypt)

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'queue_service.dart';

// URL de base de l'API AUDACE configurée à la compilation via --dart-define
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://82.29.172.251.nip.io/api/metrics', // nip.io = DNS wildcard pour IP brute
);

class SyncService {
  // Singleton de production — utilise QueueService (SQLite) et http.Client réels
  static final SyncService _instance = SyncService._internal(
    QueueService(),
    http.Client(),
    null, // pas d'override de connectivité en production
  );
  factory SyncService() => _instance;
  SyncService._internal(this._queue, this._client, this._connectivityOverride);

  // Constructeur de test — permet d'injecter un QueueRepository en mémoire,
  // un MockClient HTTP et une vérification de connectivité simulée.
  // Évite les dépendances sur les plugins natifs sqflite/connectivity_plus.
  SyncService.test(
    this._queue,
    this._client, {
    Future<bool> Function()? isOnline,
  }) : _connectivityOverride = isOnline ?? (() async => true);

  final QueueRepository _queue;
  final http.Client _client;
  // Override de connectivité pour les tests (null = utiliser le plugin réel)
  final Future<bool> Function()? _connectivityOverride;

  static const String _baseUrl      = kApiBaseUrl;
  static const Duration _httpTimeout = Duration(seconds: 30); // Timeout pour les requêtes simples

  // En-têtes communs à toutes les requêtes vers le backend
  static const Map<String, String> headers = {
    'Content-Type': 'application/json',
    'X-App-Version': '1.0.0', // Identifie la version de l'app côté serveur
  };

  Map<String, String> get _headers => headers;

  // ── Enfile + tente l'envoi immédiat si en ligne ───────────────────────────
  // Enfile la mesure dans SQLite, puis tente de vider la file si connecté.
  // Si hors ligne, retourne un SyncResult avec offline=true.
  Future<SyncResult> syncMetric(
    String metricId,
    Map<String, dynamic> jsonData,
  ) async {
    await _queue.enqueue(metricId, jsonData); // Persistance locale immédiate
    final isOnline = await _checkConnectivity();
    if (!isOnline) {
      final pending = await _queue.getPendingCount();
      return SyncResult(
        success: false,
        offline: true,
        message: 'Hors ligne — mesure mise en file ($pending en attente)',
        pendingCount: pending,
      );
    }
    return await _flushQueue(); // Tente l'envoi de toutes les mesures en attente
  }

  // ── Vide la file (toutes les mesures en attente) ──────────────────────────
  Future<SyncResult> _flushQueue() async {
    // Remet d'abord TOUS les échecs en attente (sans limite de retry_count)
    await _queue.resetAllFailed();
    final pending = await _queue.getPending(); // Lit les 100 premières en attente
    if (pending.isEmpty) {
      return SyncResult(
        success: true, offline: false,
        message: 'Aucune mesure en attente',
        pendingCount: 0,
      );
    }
    // Une seule mesure → POST simple ; plusieurs → POST batch (plus efficace)
    if (pending.length == 1) return await _sendSingle(pending.first);
    return await _sendBatch(pending);
  }

  // ── Envoi d'une seule mesure (POST /api/metrics) ──────────────────────────
  Future<SyncResult> _sendSingle(QueuedMetric metric) async {
    try {
      final body = jsonDecode(metric.json) as Map<String, dynamic>;
      body['device_metric_id'] = metric.metricId; // Ajoute l'ID de déduplication
      final response = await _client
          .post(Uri.parse(_baseUrl), headers: _headers, body: jsonEncode(body))
          .timeout(_httpTimeout);
      if (response.statusCode == 201 || response.statusCode == 200) {
        await _queue.markSent(metric.id!); // Marque comme envoyée
        return SyncResult(success: true, offline: false, message: 'Mesure envoyée avec succès', pendingCount: 0);
      }
      await _queue.markFailed(metric.id!); // Marque comme échouée (retry_count+1)
      return SyncResult(success: false, offline: false, message: 'Erreur serveur: ${response.statusCode}', pendingCount: 1);
    } catch (e) {
      await _queue.markFailed(metric.id!);
      return SyncResult(success: false, offline: false, message: 'Erreur réseau: $e', pendingCount: 1);
    }
  }

  // ── Envoi en lot (POST /api/metrics/batch) ────────────────────────────────
  // Timeout plus long (60s) car le payload peut être conséquent
  Future<SyncResult> _sendBatch(List<QueuedMetric> metrics) async {
    try {
      // Construit la liste JSON avec l'ID de déduplication dans chaque entrée
      final metricsList = metrics.map((m) {
        final body = jsonDecode(m.json) as Map<String, dynamic>;
        body['device_metric_id'] = m.metricId;
        return body;
      }).toList();

      final response = await _client
          .post(
            Uri.parse('$_baseUrl/batch'), // Endpoint batch distinct
            headers: _headers,
            body: jsonEncode({'metrics': metricsList}),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Marque toutes comme envoyées en cas de succès
        for (final m in metrics) await _queue.markSent(m.id!);
        final data = jsonDecode(response.body);
        return SyncResult(
          success: true, offline: false,
          message: '${data['inserted']} mesure(s) envoyée(s)',
          pendingCount: 0,
        );
      }
      // Marque toutes comme échouées en cas d'erreur
      for (final m in metrics) await _queue.markFailed(m.id!);
      return SyncResult(success: false, offline: false, message: 'Erreur batch: ${response.statusCode}', pendingCount: metrics.length);
    } catch (e) {
      for (final m in metrics) await _queue.markFailed(m.id!);
      return SyncResult(success: false, offline: false, message: 'Erreur réseau batch: $e', pendingCount: metrics.length);
    }
  }

  // ── Vérification de la connectivité réseau ────────────────────────────────
  // Utilise l'override injecté en test, ou le plugin connectivity_plus en production.
  Future<bool> _checkConnectivity() async {
    final override = _connectivityOverride;
    if (override != null) return override();
    try {
      final results = await Connectivity().checkConnectivity();
      // Connecté si WiFi OU données mobiles (pas ethernet, pas VPN seul)
      return results.any(
        (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
      );
    } catch (_) {
      return false; // En cas d'erreur du plugin → considère hors ligne
    }
  }

  // ── Force le retry de tous les échecs + tente la sync ────────────────────
  // Utilisé depuis DebugQueueScreen et main.dart (reconnexion réseau).
  Future<SyncResult> forceRetryAll() async {
    await _queue.resetAllFailed(); // Remet TOUS les échecs en attente sans limite
    final isOnline = await _checkConnectivity();
    if (!isOnline) {
      final pending = await _queue.getPendingCount();
      return SyncResult(
        success: false, offline: true,
        message: 'Hors ligne — $pending mesure(s) remises en attente',
        pendingCount: pending,
      );
    }
    return await _flushQueue();
  }

  // ── Teste la connexion au backend sans envoyer de données ─────────────────
  // Envoie un GET sur /api/health et retourne le résultat.
  Future<({bool ok, String message})> testBackendConnection() async {
    try {
      // Construit l'URL du health check depuis l'URL de base
      final healthUrl = _baseUrl.replaceAll(RegExp(r'/api/metrics.*'), '/api/health');
      final response = await _client
          .get(Uri.parse(healthUrl), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return (ok: true, message: 'Serveur accessible ✓  (${response.statusCode})');
      }
      return (ok: false, message: 'Réponse inattendue : ${response.statusCode}');
    } catch (e) {
      return (ok: false, message: 'Connexion impossible : $e');
    }
  }

  // ── Tente la sync quand la connectivité est rétablie ────────────────────
  // Appelé depuis main.dart via le Connectivity stream.
  Future<SyncResult> onConnectivityRestored() async {
    final isOnline = await _checkConnectivity();
    if (!isOnline)
      return SyncResult(
        success: false, offline: true,
        message: 'Toujours hors ligne',
        pendingCount: await _queue.getPendingCount(),
      );
    return await _flushQueue();
  }

  // Retourne les compteurs de la file (pending / sent / failed)
  Future<Map<String, int>> getSyncStats() => _queue.getStats();
}

// Résultat d'une opération de synchronisation
class SyncResult {
  final bool success;      // true si l'envoi a réussi
  final bool offline;      // true si hors ligne (pas d'erreur réseau, juste pas de connexion)
  final String message;    // Message lisible pour l'UI
  final int pendingCount;  // Nombre de mesures encore en attente après l'opération

  const SyncResult({
    required this.success,
    required this.offline,
    required this.message,
    required this.pendingCount,
  });
}
