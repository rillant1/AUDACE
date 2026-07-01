// Widget de contenu affiché dans les bulles du tutoriel coach mark.
// Utilisé par TutorialCoachMark pour expliquer chaque fonctionnalité à l'utilisateur
// lors du premier lancement de l'application.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TutorialContent extends StatelessWidget {
  final String title;   // Titre de l'étape du tutoriel (ex: "Lancer une mesure")
  final String body;    // Texte explicatif de l'étape
  final IconData? icon; // Icône optionnelle affichée à gauche du titre

  const TutorialContent({
    super.key,
    required this.title,
    required this.body,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20), // Marges pour ne pas coller au bord
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AudaceColors.primary.withOpacity(0.12), // Ombre teal légère
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // La bulle prend uniquement la place nécessaire
        children: [
          // ── Ligne d'en-tête : icône (facultative) + titre ───────────────
          Row(
            children: [
              // L'icône n'est affichée que si elle est fournie (paramètre optionnel)
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AudaceColors.primary.withOpacity(0.1), // Fond teal très clair
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AudaceColors.primary, size: 18),
                ),
                const SizedBox(width: 10), // Espace entre l'icône et le titre
              ],
              // Le titre occupe tout l'espace restant de la ligne
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AudaceColors.primary, // Teal pour bien se démarquer
                    fontSize: 16,
                    fontWeight: FontWeight.w800, // Très gras
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Corps du texte explicatif ────────────────────────────────────
          Text(
            body,
            style: const TextStyle(
              color: AudaceColors.textDark,
              fontSize: 13,
              height: 1.5, // Interligne augmenté pour une meilleure lisibilité
            ),
          ),
        ],
      ),
    );
  }
}
