// Overlay de progression — affiché par-dessus l'écran pendant l'analyse réseau.
// Montre un cercle de chargement, le nom de l'étape en cours et une barre de progression.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';

class ProgressOverlay extends StatelessWidget {
  final String step;      // Description de l'étape actuelle (ex: "Test du débit descendant…")
  final double progress;  // Progression de 0.0 (début) à 1.0 (terminé)

  const ProgressOverlay({
    super.key,
    required this.step,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Fond semi-transparent noir pour assombrir le contenu derrière
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32), // Marges latérales
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            border: Border.all(color: AudaceColors.border),
            boxShadow: [
              BoxShadow(
                color: AudaceColors.primary.withOpacity(0.12), // Lueur teal
                blurRadius: 40,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // La carte ne prend que la hauteur nécessaire
            children: [
              // ── Indicateur circulaire avec icône WiFi au centre ──────────
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Cercle de progression déterminé (value = 0.0 → 1.0)
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: progress,                       // Progression actuelle
                        strokeWidth: 3,
                        backgroundColor: AudaceColors.border, // Fond du cercle (gris)
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AudaceColors.primary,              // Arc teal
                        ),
                      ),
                    ),
                    // Icône WiFi fixe au centre du cercle
                    const Icon(
                      Icons.wifi_tethering_rounded,
                      color: AudaceColors.primary,
                      size: 28,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Titre "Analyse en cours" ─────────────────────────────────
              Text(
                'Analyse en cours',
                style: AppTextStyles.mono(
                  color: AudaceColors.textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5, // Léger espacement pour le style technique
                ),
              ),
              const SizedBox(height: 10),

              // ── Nom de l'étape en cours ──────────────────────────────────
              Text(
                step, // Ex: "Mesure de la latence (ping)…"
                style: AppTextStyles.body(
                  color: AudaceColors.textMedium,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // ── Barre de progression linéaire ────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(4), // Coins arrondis de la barre
                child: LinearProgressIndicator(
                  value: progress,                            // Progression actuelle
                  backgroundColor: AudaceColors.border,     // Fond de la barre (gris)
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AudaceColors.primary,                   // Remplissage teal
                  ),
                  minHeight: 6, // Barre légèrement plus épaisse que le défaut (4px)
                ),
              ),
              const SizedBox(height: 8),

              // ── Pourcentage aligné à droite ──────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${(progress * 100).toInt()}%', // Arrondi à l'entier inférieur
                  style: AppTextStyles.mono(
                    color: AudaceColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
