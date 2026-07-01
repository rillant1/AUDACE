// lib/services/background_service.dart
// Foreground Service Android persistant — tourne même quand l'app est fermée.
// Utilise flutter_background_service qui crée un vrai Service Android natif.
// Collecte les métriques réseau toutes les 5 minutes et les envoie au backend.

import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'metrics_service.dart';
import 'queue_service.dart';
import 'sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// POINT D'ENTRÉE DU SERVICE — exécuté dans un isolat Dart séparé du UI
// @pragma('vm:entry-point') empêche le tree-shaker de le supprimer lors de la
// compilation AOT en mode release
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  // Enregistre les plugins Flutter dans cet isolat séparé (requis pour
  // que les MethodChannels fonctionnent : SQLite, GPS, WiFi…)
  DartPluginRegistrant.ensureInitialized();

  // Passe en mode foreground : Android affiche une notification persistante
  // et ne peut pas tuer ce service sauf si l'utilisateur le force manuellement
  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  // Écoute la commande 'stopService' envoyée depuis l'UI (HomeScreen)
  // et s'arrête proprement
  service.on('stopService').listen((_) => service.stopSelf());

  // Crée le runner de cycle avec les services de production
  final runner = BackgroundCycleRunner();

  // ── Premier cycle immédiat au démarrage du service ─────────────────────
  await runner.runCycle(service);

  // ── Collecte toutes les 5 minutes (cycle périodique) ───────────────────
  Timer.periodic(const Duration(minutes: 5), (_) async {
    await runner.runCycle(service);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGIQUE D'UN CYCLE — classe injectable pour les tests
// Encapsule le verrou anti-concurrence, la collecte et la gestion d'erreurs.
// ─────────────────────────────────────────────────────────────────────────────
class BackgroundCycleRunner {
  // Collecteur de métriques (injectable en test via un faux collecteur)
  final Future<void> Function() _collect;
  // Lecteur des stats de synchronisation (injectable en test)
  final Future<Map<String, int>> Function() _getStats;
  // Enfile les erreurs dans SQLite (injectable en test)
  final Future<void> Function(String id, Map<String, dynamic> data) _enqueue;

  // Verrou interne : un seul cycle à la fois dans cet instance
  bool _enCours = false;

  BackgroundCycleRunner({
    Future<void> Function()? collect,
    Future<Map<String, int>> Function()? getStats,
    Future<void> Function(String id, Map<String, dynamic> data)? enqueue,
  })  : _collect  = collect  ?? (() => MetricsService().collectAllMetrics()),
        _getStats  = getStats  ?? (() => SyncService().getSyncStats()),
        _enqueue   = enqueue   ?? ((id, data) => QueueService().enqueue(id, data));

  // ── Un cycle complet de collecte : mesures → SQLite → envoi backend ──────
  Future<void> runCycle(ServiceInstance service) async {
    // Si un cycle est déjà en cours, on met à jour la notification et on sort
    if (_enCours) {
      _updateNotification(service, 'AUDACE actif', 'Collecte en cours…');
      return;
    }
    _enCours = true;

    // Formatage de l'heure locale pour la notification (ex: "14:32")
    final now  = DateTime.now();
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    try {
      _updateNotification(service, 'AUDACE — Analyse...', 'Collecte en cours ($hhmm)');

      // Lance la collecte complète : GPS, signal radio, débit, ping, QoE…
      // collectAllMetrics() sauvegarde aussi dans SQLite et tente l'envoi
      await _collect();

      // Lit les statistiques après collecte pour alimenter la notification
      final stats   = await _getStats();
      final pending = stats['pending'] ?? 0; // Mesures en attente d'envoi
      final sent    = stats['sent']    ?? 0; // Total des mesures envoyées

      // Met à jour la notification persistante avec le résultat
      _updateNotification(
        service,
        'AUDACE actif',
        pending > 0
            ? '$pending en attente · dernière : $hhmm'      // Hors ligne
            : 'Dernière mesure : $hhmm · total envoyé : $sent', // En ligne
      );

      // Notifie l'UI via un événement (HomeScreen écoute 'collectionDone')
      service.invoke('collectionDone', {
        'success': pending == 0, // true si tout a été envoyé
        'offline': pending > 0,  // true si des mesures sont en attente
        'pending': pending,
        'sent':    sent,
        'time':    hhmm,
      });
    } catch (e) {
      // catch (e) attrape TOUT : Exception ET Error (TypeError, RangeError…)
      // Un simple "on Exception" laisserait propager les Error Dart et
      // pourrait tuer l'isolat du service.
      try {
        await _enqueue(
          'bg_error_${now.millisecondsSinceEpoch}', // ID unique
          {
            'horodatage':          now.toIso8601String(),
            'erreur_background':   e.toString(),
            'cycle':               'background_5min',
          },
        );
      } catch (_) {} // Si même l'enqueue échoue, on abandonne silencieusement
      _updateNotification(service, 'AUDACE actif', 'Erreur cycle $hhmm — réessai dans 5 min');
    } finally {
      _enCours = false; // Libère le verrou dans tous les cas (y compris Error)
    }
  }

  // Expose l'état du verrou (utile pour les tests)
  bool get enCours => _enCours;
}

// Met à jour le titre et le texte de la notification de foreground service
void _updateNotification(ServiceInstance service, String title, String content) {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(title: title, content: content);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GESTIONNAIRE PUBLIC — singleton utilisé depuis main.dart et HomeScreen
// ─────────────────────────────────────────────────────────────────────────────
class BackgroundService {
  // Singleton — une seule instance dans toute l'application principale
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  // Instance du plugin flutter_background_service
  final _service = FlutterBackgroundService();

  // ── Configure le service et le canal de notification Android ──────────────
  Future<void> initialize() async {
    final notif = FlutterLocalNotificationsPlugin();

    // Crée le canal de notification (requis Android 8+)
    await notif
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'netprobe_service',               // ID du canal
            'AUDACE Service',                 // Nom affiché dans les paramètres
            description: 'Surveillance réseau en arrière-plan',
            importance: Importance.low,       // Silencieux (pas de son ni vibration)
          ),
        );

    // Configure le service pour Android et iOS
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,             // Point d'entrée de l'isolat service
        autoStart: true,              // Redémarre automatiquement si tué par le système
        isForegroundMode: true,       // Foreground Service (notification visible)
        notificationChannelId: 'netprobe_service',
        initialNotificationTitle: 'AUDACE actif',
        initialNotificationContent: 'Surveillance réseau démarrée',
        foregroundServiceNotificationId: 888, // ID unique de la notification
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,        // Même point d'entrée au premier plan
        onBackground: _onIosBackground, // Callback minimal pour iOS background
      ),
    );
  }

  // Démarre le service s'il n'est pas déjà en cours
  Future<void> startHourlyCollection() async {
    if (!await _service.isRunning()) await _service.startService();
  }

  // Envoie la commande 'stopService' à l'isolat pour l'arrêter proprement
  Future<void> stopHourlyCollection() async {
    _service.invoke('stopService');
  }

  // Vérifie si le service est actuellement actif
  Future<bool> get isRunning => _service.isRunning();

  // Stream des événements 'collectionDone' émis par l'isolat à chaque cycle
  Stream<Map<String, dynamic>?> get collectionEvents =>
      _service.on('collectionDone');
}

// Callback iOS en arrière-plan — minimal, requis par le plugin
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true; // iOS exige un bool de retour
}
