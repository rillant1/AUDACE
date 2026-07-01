// Service de gestion des permissions Android runtime (API 23+).
// Sur Android 6+, déclarer une permission dans AndroidManifest.xml ne suffit pas.
// Il faut AUSSI demander la permission à l'utilisateur via une boîte de dialogue.
// Sans cette étape, Android bloque l'accès silencieusement (données vides ou
// SecurityException sur les APIs sensibles comme getTelephonyInfo).

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  // Singleton — une seule instance dans toute l'application
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  // Demande TOUTES les permissions nécessaires à l'application.
  // Affiche la boîte de dialogue système pour chaque permission non encore accordée.
  // Retourne un PermissionResult indiquant l'état de chaque permission.
  Future<PermissionResult> requestAllPermissions() async {
    try {
      // Note : Permission.storage est intentionnellement absente.
      // Sur Android 10+ (API 29+), le stockage est "scopé" (Scoped Storage)
      // et WRITE_EXTERNAL_STORAGE génère une PlatformException sur certains appareils.
      // L'app utilise path_provider (stockage interne/externe applicatif) qui
      // n'a pas besoin de cette permission.
      final statuses = await [
        Permission.phone,             // READ_PHONE_STATE — signal radio, opérateur, type réseau
        Permission.locationWhenInUse, // ACCESS_FINE_LOCATION — coordonnées GPS
        Permission.notification,      // POST_NOTIFICATIONS — requis Android 13+ (API 33+)
      ].request();

      final phoneGranted    = statuses[Permission.phone]?.isGranted ?? false;
      final locationGranted = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

      return PermissionResult(
        phoneGranted:       phoneGranted,
        locationGranted:    locationGranted,
        storageGranted:     true, // Stockage interne : toujours accessible sans permission
        allCriticalGranted: phoneGranted, // La permission téléphonie est la plus critique
      );
    } catch (_) {
      // PlatformException sur certains appareils ou versions d'Android non standards.
      // On continue avec les permissions disponibles plutôt que de bloquer l'analyse.
      return const PermissionResult(
        phoneGranted:       false,
        locationGranted:    false,
        storageGranted:     true,
        allCriticalGranted: false,
      );
    }
  }

  // Vérifie l'état actuel des permissions SANS afficher de boîte de dialogue.
  // Utilisé au démarrage pour savoir si on doit demander les permissions ou non.
  Future<PermissionResult> checkPermissions() async {
    try {
      final phoneGranted    = await Permission.phone.isGranted;
      final locationGranted = await Permission.locationWhenInUse.isGranted;
      return PermissionResult(
        phoneGranted:       phoneGranted,
        locationGranted:    locationGranted,
        storageGranted:     true,
        allCriticalGranted: phoneGranted,
      );
    } catch (_) {
      return const PermissionResult(
        phoneGranted:       false,
        locationGranted:    false,
        storageGranted:     true,
        allCriticalGranted: false,
      );
    }
  }

  // Vérifie si l'app est déjà exemptée du mode Doze (optimisation batterie).
  // Les foreground services peuvent être tués par Doze s'ils ne sont pas exemptés.
  Future<bool> isBatteryOptimizationExempted() async {
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      return false;
    }
  }

  // Demande au système Android d'exempter l'app de l'optimisation batterie.
  // DOIT être appelé depuis l'UI principale (Activity active) — pas depuis un isolat.
  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  // Ouvre les paramètres de l'application si l'utilisateur a refusé définitivement
  // (seul moyen de réactiver la permission après un refus définitif)
  Future<void> openSettings() => openAppSettings();
}

// Résultat de vérification ou de demande des permissions
class PermissionResult {
  final bool phoneGranted;      // READ_PHONE_STATE — signal radio, opérateur
  final bool locationGranted;   // ACCESS_FINE_LOCATION — GPS
  final bool storageGranted;    // Stockage (toujours true, pas de permission requise)
  final bool allCriticalGranted; // true si le minimum vital est accordé (= phoneGranted)

  const PermissionResult({
    required this.phoneGranted,
    required this.locationGranted,
    required this.storageGranted,
    required this.allCriticalGranted,
  });
}
