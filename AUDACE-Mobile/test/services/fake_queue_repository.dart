// test/services/fake_queue_repository.dart
// Double de test en mémoire pour QueueRepository — évite toute dépendance
// au plugin natif sqflite (indisponible sur la VM Dart de test).

import 'dart:convert';

import 'package:netprobe/services/queue_service.dart';

class FakeQueueRepository implements QueueRepository {
  final List<QueuedMetric> _store = [];
  int _nextId = 1;

  @override
  Future<void> enqueue(String metricId, Map<String, dynamic> jsonData) async {
    final dejaPresent = _store.any((m) => m.metricId == metricId);
    if (dejaPresent) return;
    _store.add(
      QueuedMetric(
        id: _nextId++,
        metricId: metricId,
        json: jsonEncode(jsonData),
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> markSent(int id) async {
    final index = _store.indexWhere((m) => m.id == id);
    if (index == -1) return;
    final m = _store[index];
    _store[index] = QueuedMetric(
      id: m.id,
      metricId: m.metricId,
      json: m.json,
      status: QueueStatus.sent,
      createdAt: m.createdAt,
      sentAt: DateTime.now(),
      retryCount: m.retryCount,
    );
  }

  @override
  Future<void> markFailed(int id) async {
    final index = _store.indexWhere((m) => m.id == id);
    if (index == -1) return;
    final m = _store[index];
    _store[index] = QueuedMetric(
      id: m.id,
      metricId: m.metricId,
      json: m.json,
      status: QueueStatus.failed,
      createdAt: m.createdAt,
      sentAt: m.sentAt,
      retryCount: m.retryCount + 1,
    );
  }

  @override
  Future<void> requeueFailed() async {
    for (var i = 0; i < _store.length; i++) {
      final m = _store[i];
      if (m.status == QueueStatus.failed && m.retryCount < 10) {
        _store[i] = QueuedMetric(
          id: m.id,
          metricId: m.metricId,
          json: m.json,
          status: QueueStatus.pending,
          createdAt: m.createdAt,
          sentAt: m.sentAt,
          retryCount: m.retryCount,
        );
      }
    }
  }

  @override
  Future<List<QueuedMetric>> getPending() async {
    return _store.where((m) => m.status == QueueStatus.pending).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<List<QueuedMetric>> getAll({int limit = 500}) async {
    final sorted = [..._store]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList();
  }

  @override
  Future<int> getPendingCount() async =>
      _store.where((m) => m.status == QueueStatus.pending).length;

  @override
  Future<Map<String, int>> getStats() async => {
    'pending': _store.where((m) => m.status == QueueStatus.pending).length,
    'sent': _store.where((m) => m.status == QueueStatus.sent).length,
    'failed': _store.where((m) => m.status == QueueStatus.failed).length,
  };

  @override
  Future<void> purgeOldSent() async {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    _store.removeWhere(
      (m) =>
          m.status == QueueStatus.sent &&
          m.sentAt != null &&
          m.sentAt!.isBefore(sevenDaysAgo),
    );
  }

  @override
  Future<void> resetAllFailed() async {
    for (var i = 0; i < _store.length; i++) {
      final m = _store[i];
      if (m.status == QueueStatus.failed) {
        _store[i] = QueuedMetric(
          id: m.id,
          metricId: m.metricId,
          json: m.json,
          status: QueueStatus.pending,
          createdAt: m.createdAt,
          sentAt: m.sentAt,
          retryCount: 0,
        );
      }
    }
  }
}
