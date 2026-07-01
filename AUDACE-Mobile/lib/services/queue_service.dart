// lib/services/queue_service.dart
// File d'attente locale SQLite pour les mesures réseau en attente d'envoi.
// Persiste les mesures entre les redémarrages de l'application et les coupures réseau.
// Architecture en trois couches : QueueStatus enum → QueuedMetric modèle →
// QueueRepository interface → SqfliteQueueRepository implémentation → QueueService façade.

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// Statut d'une mesure dans la file d'attente
enum QueueStatus {
  pending, // En attente d'envoi (nouvelle ou remise en attente après échec)
  sent,    // Envoyée avec succès au serveur
  failed,  // Échec d'envoi (retry_count incrémenté)
}

// Modèle d'une mesure stockée dans la file SQLite
class QueuedMetric {
  final int? id;           // ID SQLite auto-incrémenté (null avant insertion)
  final String metricId;   // UUID unique de la mesure (pour la déduplication côté serveur)
  final String json;       // Payload JSON sérialisé (NetworkMetrics.toJson())
  final QueueStatus status; // Statut actuel
  final DateTime createdAt; // Date de création (locale)
  final DateTime? sentAt;   // Date d'envoi (null si pas encore envoyée)
  final int retryCount;     // Nombre d'essais d'envoi échoués (max 10 avant abandon)

  const QueuedMetric({
    this.id,
    required this.metricId,
    required this.json,
    this.status = QueueStatus.pending,
    required this.createdAt,
    this.sentAt,
    this.retryCount = 0,
  });

  // Sérialise en Map pour l'insertion SQLite (sans 'id' — auto-incrémenté)
  Map<String, dynamic> toMap() => {
    'metric_id':   metricId,
    'json':        json,
    'status':      status.name,           // Stocké en texte : 'pending', 'sent', 'failed'
    'created_at':  createdAt.toIso8601String(),
    'sent_at':     sentAt?.toIso8601String(), // null si pas encore envoyée
    'retry_count': retryCount,
  };

  // Désérialise depuis une ligne SQLite
  factory QueuedMetric.fromMap(Map<String, dynamic> map) => QueuedMetric(
    id:         map['id']         as int?,
    metricId:   map['metric_id']  as String,
    json:       map['json']       as String,
    status:     QueueStatus.values.firstWhere(
      (s) => s.name == map['status'],
      orElse: () => QueueStatus.pending, // Valeur de secours si statut inconnu
    ),
    createdAt:  DateTime.parse(map['created_at'] as String),
    sentAt:     map['sent_at'] != null
        ? DateTime.parse(map['sent_at'] as String)
        : null,
    retryCount: map['retry_count'] as int? ?? 0,
  );
}

// Interface abstraite de la file d'attente — permet l'injection en test
// sans dépendance sur sqflite (indisponible sur la VM Dart de test).
abstract class QueueRepository {
  Future<void> enqueue(String metricId, Map<String, dynamic> jsonData);
  Future<void> markSent(int id);
  Future<void> markFailed(int id);
  Future<void> requeueFailed();                          // Remet en attente (retry_count < 10)
  Future<List<QueuedMetric>> getPending();               // Mesures en attente (max 100)
  Future<List<QueuedMetric>> getAll({int limit = 500}); // Toutes les mesures
  Future<int> getPendingCount();                         // Compteur rapide
  Future<Map<String, int>> getStats();                   // Compteurs par statut
  Future<void> purgeOldSent();                           // Supprime les envoyées > 7 jours
  // Remet TOUS les échecs en attente (sans limite de retry_count) — utilisé par forceRetryAll()
  Future<void> resetAllFailed();
}

// Implémentation de production — persiste dans netprobe_queue.db via sqflite
class SqfliteQueueRepository implements QueueRepository {
  Database? _db; // Instance SQLite (initialisée une seule fois)

  // Getter avec lazy init — crée la BD si nécessaire, sinon retourne l'instance existante
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  // Crée la base de données et la table queue si elles n'existent pas
  Future<Database> _initDb() async {
    final dbPath = join(await getDatabasesPath(), 'netprobe_queue.db');
    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        // Table principale avec contrainte UNIQUE sur metric_id (déduplication)
        await db.execute('''
          CREATE TABLE queue (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            metric_id   TEXT    NOT NULL UNIQUE,
            json        TEXT    NOT NULL,
            status      TEXT    NOT NULL DEFAULT 'pending',
            created_at  TEXT    NOT NULL,
            sent_at     TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // Index sur status pour accélérer les requêtes de type WHERE status = 'pending'
        await db.execute('CREATE INDEX idx_status  ON queue(status)');
        // Index sur created_at pour le tri chronologique et la purge
        await db.execute('CREATE INDEX idx_created ON queue(created_at)');
      },
    );
  }

  @override
  Future<void> enqueue(String metricId, Map<String, dynamic> jsonData) async {
    final db = await database;
    // ConflictAlgorithm.ignore : si metric_id existe déjà → on ignore silencieusement
    // Évite les doublons en cas de retry sans créer d'exception
    await db.insert(
      'queue',
      QueuedMetric(
        metricId:  metricId,
        json:      jsonEncode(jsonData),
        createdAt: DateTime.now(),
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> markSent(int id) async {
    final db = await database;
    await db.update(
      'queue',
      {
        'status':  QueueStatus.sent.name,
        'sent_at': DateTime.now().toIso8601String(), // Horodatage de l'envoi
      },
      where:     'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markFailed(int id) async {
    final db = await database;
    // rawUpdate pour incrémenter retry_count atomiquement
    await db.rawUpdate(
      'UPDATE queue SET status = ?, retry_count = retry_count + 1 WHERE id = ?',
      [QueueStatus.failed.name, id],
    );
  }

  @override
  Future<void> requeueFailed() async {
    final db = await database;
    // Remet en attente seulement les échecs avec retry_count < 10
    // Les mesures avec 10 essais ou plus sont abandonnées (évite les boucles infinies)
    await db.rawUpdate(
      "UPDATE queue SET status = 'pending' WHERE status = 'failed' AND retry_count < 10",
    );
  }

  @override
  Future<List<QueuedMetric>> getPending() async {
    final db = await database;
    final maps = await db.query(
      'queue',
      where:     'status = ?',
      whereArgs: ['pending'],
      orderBy:   'created_at ASC', // Plus anciennes en premier (FIFO)
      limit:     100,              // Max 100 par lot pour limiter la taille du payload
    );
    return maps.map(QueuedMetric.fromMap).toList();
  }

  @override
  Future<int> getPendingCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM queue WHERE status = 'pending'",
    );
    return result.first['count'] as int? ?? 0;
  }

  @override
  Future<Map<String, int>> getStats() async {
    final db = await database;
    // Une seule requête SQL avec CASE WHEN pour les 3 compteurs (plus efficace)
    final result = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN status = 'sent'    THEN 1 ELSE 0 END) as sent,
        SUM(CASE WHEN status = 'failed'  THEN 1 ELSE 0 END) as failed
      FROM queue
    ''');
    final row = result.first;
    return {
      'pending': row['pending'] as int? ?? 0,
      'sent':    row['sent']    as int? ?? 0,
      'failed':  row['failed']  as int? ?? 0,
    };
  }

  @override
  Future<List<QueuedMetric>> getAll({int limit = 500}) async {
    final db = await database;
    final maps = await db.query(
      'queue',
      orderBy: 'created_at DESC', // Plus récentes en premier
      limit:   limit,
    );
    return maps.map(QueuedMetric.fromMap).toList();
  }

  @override
  Future<void> purgeOldSent() async {
    final db = await database;
    // Supprime les mesures envoyées depuis plus de 7 jours
    // pour éviter que la BD ne grossisse indéfiniment
    final sevenDaysAgo = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();
    await db.delete(
      'queue',
      where:     "status = 'sent' AND sent_at < ?",
      whereArgs: [sevenDaysAgo],
    );
  }

  @override
  Future<void> resetAllFailed() async {
    final db = await database;
    // Remet TOUS les échecs en attente sans vérifier retry_count
    // et réinitialise le compteur à 0 → utilisé par forceRetryAll()
    await db.rawUpdate(
      "UPDATE queue SET status = 'pending', retry_count = 0 WHERE status = 'failed'",
    );
  }
}

// Façade singleton déléguant à SqfliteQueueRepository en production.
// Conserve l'API publique historique de QueueService pour ses appelants existants.
class QueueService implements QueueRepository {
  // Singleton — utilise SqfliteQueueRepository par défaut
  static final QueueService _instance = QueueService._internal(
    SqfliteQueueRepository(),
  );
  factory QueueService() => _instance;
  QueueService._internal(this._repository);

  // Constructeur de test — permet d'injecter un QueueRepository en mémoire
  QueueService.test(this._repository);

  final QueueRepository _repository; // Implémentation injectée

  // Toutes les méthodes délèguent directement au repository
  @override
  Future<void> enqueue(String metricId, Map<String, dynamic> jsonData) =>
      _repository.enqueue(metricId, jsonData);

  @override
  Future<void> markSent(int id) => _repository.markSent(id);

  @override
  Future<void> markFailed(int id) => _repository.markFailed(id);

  @override
  Future<void> requeueFailed() => _repository.requeueFailed();

  @override
  Future<List<QueuedMetric>> getPending() => _repository.getPending();

  @override
  Future<List<QueuedMetric>> getAll({int limit = 500}) =>
      _repository.getAll(limit: limit);

  @override
  Future<int> getPendingCount() => _repository.getPendingCount();

  @override
  Future<Map<String, int>> getStats() => _repository.getStats();

  @override
  Future<void> purgeOldSent() => _repository.purgeOldSent();

  @override
  Future<void> resetAllFailed() => _repository.resetAllFailed();
}
