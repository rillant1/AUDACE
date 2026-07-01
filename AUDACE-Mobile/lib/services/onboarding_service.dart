// Service de gestion de l'état du tutoriel d'intégration (onboarding).
// Mémorise quelles étapes du tutoriel ont déjà été montrées à l'utilisateur.
// Utilise SharedPreferences pour une persistance simple entre les sessions.

import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  // Préfixe v2 pour éviter tout conflit avec d'éventuelles clés de versions précédentes
  static const _prefix = 'tutorial_v2_';

  // Vérifie si une étape du tutoriel doit être affichée.
  // Retourne true si l'étape n'a jamais été vue (ou si la clé n'existe pas).
  static Future<bool> shouldShow(String key) async {
    final prefs = await SharedPreferences.getInstance();
    // Si la valeur n'existe pas, getBool retourne null → l'opérateur ?? force false
    // → la négation retourne true = il faut montrer le tutoriel
    return !(prefs.getBool('$_prefix$key') ?? false);
  }

  // Marque une étape du tutoriel comme déjà vue pour ne plus la répéter.
  static Future<void> markShown(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$key', true);
  }

  // Remet toutes les étapes du tutoriel à zéro — utilisé par "Rejouer le tutoriel".
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    // Trouve toutes les clés commençant par le préfixe du tutoriel
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    // Supprime chaque clé pour que shouldShow() retourne true à nouveau
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
