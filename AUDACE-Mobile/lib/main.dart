// Point d'entrée de l'application AUDACE.
// Initialise les services, demande les permissions et lance l'app Flutter.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'screens/splash_screen.dart';
import 'services/permission_service.dart';
import 'services/background_service.dart';
import 'services/sync_service.dart';
import 'services/app_settings.dart';
import 'theme/app_theme.dart';

void main() async {
  // Initialise le binding Flutter avant tout appel de plugin natif
  WidgetsFlutterBinding.ensureInitialized();

  // Charge les préférences sauvegardées (langue choisie par l'utilisateur)
  await AppSettings().load();

  // Demande toutes les permissions Android au démarrage (téléphonie, GPS, notifications)
  await PermissionService().requestAllPermissions();

  // Initialise le service Android foreground (notification persistante + collecte auto)
  await BackgroundService().initialize();
  // Lance la collecte périodique en arrière-plan (toutes les 5 min via le service)
  await BackgroundService().startHourlyCollection();

  // Si l'appareil est déjà connecté, on envoie immédiatement les mesures en attente
  try {
    final initial = await Connectivity().checkConnectivity();
    // Vérifie si au moins une interface réseau (WiFi ou mobile) est active
    final isOnline = initial.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
    );
    // Lance l'envoi sans bloquer le démarrage (.ignore() évite d'attendre le résultat)
    if (isOnline) SyncService().forceRetryAll().ignore();
  } catch (_) {}

  // Écoute les changements de connectivité pour envoyer les mesures dès le retour du réseau
  Connectivity().onConnectivityChanged.listen((results) async {
    // Même logique : au moins une interface WiFi ou mobile active
    final isOnline = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
    );
    // Envoie les mesures en attente dès que la connexion revient
    if (isOnline) await SyncService().forceRetryAll();
  });

  // Bloque la rotation — l'app est conçue uniquement en mode portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Rend la barre de statut transparente avec des icônes sombres (fond clair de l'app)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // icônes sombres sur fond blanc
    ),
  );

  // Lance l'application Flutter
  runApp(const AudaceApp());
}

// Widget racine de l'application — écoute les changements de langue pour reconstruire
class AudaceApp extends StatefulWidget {
  const AudaceApp({super.key});
  @override
  State<AudaceApp> createState() => _AudaceAppState();
}

class _AudaceAppState extends State<AudaceApp> {
  @override
  void initState() {
    super.initState();
    // Abonne cet état aux changements de langue pour reconstruire toute l'app
    AppSettings().languageCode.addListener(_onLangChange);
  }

  @override
  void dispose() {
    // Désabonne pour éviter les fuites mémoire quand le widget est détruit
    AppSettings().languageCode.removeListener(_onLangChange);
    super.dispose();
  }

  // Appelé chaque fois que la langue change → force la reconstruction complète
  void _onLangChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AUDACE',
      // Masque le bandeau rouge "DEBUG" en production
      debugShowCheckedModeBanner: false,
      // Applique le thème teal/blanc défini dans app_theme.dart
      theme: AudaceTheme.light,
      // Locale active selon la préférence de l'utilisateur (fr ou en)
      locale: Locale(AppSettings().languageCode.value),
      // Premier écran affiché : splash animé avant l'accueil
      home: const SplashScreen(),
    );
  }
}
