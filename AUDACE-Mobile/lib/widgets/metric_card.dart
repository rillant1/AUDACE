// Carte d'affichage d'une seule métrique réseau.
// Affiche une icône + un label + une valeur numérique + une unité.
// La couleur de bordure change selon la valeur (vert si bon, orange si moyen, rouge si faible).

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';

class MetricCard extends StatelessWidget {
  final String label;    // Nom de la métrique (ex: "Latence")
  final String value;    // Valeur formatée en texte (ex: "42")
  final String unit;     // Unité de la valeur (ex: "ms", "Mbps") — vide par défaut
  final IconData icon;   // Icône illustrant la métrique
  final Color? color;    // Couleur thématique (vert/orange/rouge) — null = couleur par défaut
  final bool fullWidth;  // Si true, la carte s'étend sur toute la largeur disponible

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.unit = '',
    this.color,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    // Couleur de la valeur : couleur fournie OU couleur par défaut du texte
    final valueColor = color ?? AudaceColors.textDark;
    return Container(
      // Pleine largeur si demandé, sinon taille naturelle du contenu
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AudaceColors.surface,
        border: Border.all(
          // Bordure colorée si color est fourni (30% d'opacité), sinon bordure standard
          color: color != null ? color!.withOpacity(0.3) : AudaceColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Ligne supérieure : icône + label ────────────────────────────
          Row(
            children: [
              // Icône à 70% d'opacité pour être moins dominante que la valeur
              Icon(icon, color: valueColor.withOpacity(0.7), size: 14),
              const SizedBox(width: 6),
              // Le label est flexible pour éviter le débordement sur les petits écrans
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyles.body(
                    color: AudaceColors.textMuted,   // Texte atténué pour le label
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,   // Tronque si le label est trop long
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Ligne inférieure : valeur + unité ────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end, // Aligne en bas (unité plus petite)
            children: [
              // Valeur en police monospace — plus petite si la valeur est longue (>6 chars)
              Flexible(
                child: Text(
                  value,
                  style: AppTextStyles.mono(
                    color: valueColor,
                    fontSize: value.length > 6 ? 15 : 20, // Taille adaptative
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // L'unité n'est affichée que si elle n'est pas vide
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2), // Alignement visuel avec la valeur
                  child: Text(
                    unit,
                    style: AppTextStyles.body(
                      color: AudaceColors.textMuted, // Unité atténuée
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
