// Écran de démarrage (splash) de l'application AUDACE.
// Affiché pendant 2800ms au lancement, avec une animation de fondu + zoom.
// Redirige ensuite vers HomeScreen avec une transition FadeTransition.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Contrôleur d'animation (900ms)
  late final AnimationController _ctrl;
  // Animation d'opacité : 0 → 1 (fondu entrant, courbe easeOut)
  late final Animation<double> _fade;
  // Animation d'échelle : 0.88 → 1.0 (léger zoom, courbe easeOutCubic)
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // Durée de l'animation d'entrée : 900ms
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Fondu : easeOut → rapide au début, ralentit à la fin
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.0, end: 1.0));

    // Zoom léger : easeOutCubic → démarre à 88% de taille et grandit à 100%
    _scale = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
    ).drive(Tween(begin: 0.88, end: 1.0));

    // Lance l'animation dès le premier frame
    _ctrl.forward();
    // Après 2800ms, redirige vers l'écran principal
    Future.delayed(const Duration(milliseconds: 2800), _goToHome);
  }

  // Remplace le splash par HomeScreen avec une transition FadeTransition (500ms)
  Future<void> _goToHome() async {
    if (!mounted) return; // Sécurité si le widget est démonté (rare)
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        // Transition : fondu entrant de 500ms
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose(); // Libère le contrôleur d'animation
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Fond blanc pendant le splash
      body: FadeTransition(
        opacity: _fade, // Fondu piloté par l'animation
        child: ScaleTransition(
          scale: _scale, // Zoom piloté par l'animation
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min, // Centrage vertical du contenu
              children: [
                _Logo(), // Logo carré arrondi avec image ou fallback gradient
                const SizedBox(height: 24),
                // Nom de l'app en majuscules espacées
                const Text(
                  'AUDACE',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AudaceColors.primary, // Teal
                    letterSpacing: 5,             // Espacement large pour effet logomark
                  ),
                ),
                const SizedBox(height: 6),
                // Sous-titre (vide — réservé pour une tagline future)
                const Text(
                  '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AudaceColors.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Widget du logo carré arrondi (100×100, rayon 26)
class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          // Ombre teal sous le logo
          BoxShadow(
            color: AudaceColors.primary.withOpacity(0.18),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26), // Coins arrondis du logo
        child: Image.asset(
          'assets/logo/icon.jpeg', // Logo PNG de l'application
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          // Si l'image n'existe pas → carré gradient teal avec la lettre A
          errorBuilder: (_, __, ___) => Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(26)),
              gradient: LinearGradient(
                colors: [AudaceColors.primary, AudaceColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: const Text(
              'A',
              style: TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
