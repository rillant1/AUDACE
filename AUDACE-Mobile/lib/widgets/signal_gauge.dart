// Widget affichant les 3 métriques de signal radio cellulaire (RSRP, RSRQ, SINR)
// sous forme de barres de progression colorées avec interprétation qualitative.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';

class SignalGaugeRow extends StatelessWidget {
  final double? rsrp;        // Puissance du signal de référence (dBm)
  final double? rsrq;        // Qualité du signal reçu (dB)
  final double? sinr;        // Rapport signal sur bruit (dB)
  final String networkType;  // Type de réseau affiché dans le badge (ex: "4G", "5G")

  const SignalGaugeRow({
    super.key,
    this.rsrp,
    this.rsrq,
    this.sinr,
    required this.networkType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AudaceColors.surface,
        border: Border.all(color: AudaceColors.border),
      ),
      child: Column(
        children: [
          // ── En-tête : badge du type de réseau + verdict textuel du RSRP ───
          Row(
            children: [
              _NetworkTypeBadge(label: networkType),
              const Spacer(),
              Text(
                rsrp != null ? _interpretRsrp(rsrp!) : 'Signal inconnu',
                style: AppTextStyles.body(
                  color: rsrp != null ? _rsrpColor(rsrp!) : AudaceColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Trois barres de signal ──────────────────────────────────────
          _SignalBar(
            label: 'RSRP',
            value: rsrp,
            min: -140, max: -40, // Plage typique RSRP en dBm
            unit: 'dBm',
            tooltip: 'Puissance du signal de référence',
          ),
          const SizedBox(height: 10),
          _SignalBar(
            label: 'RSRQ',
            value: rsrq,
            min: -20, max: -3, // Plage typique RSRQ en dB
            unit: 'dB',
            tooltip: 'Qualité du signal reçu',
          ),
          const SizedBox(height: 10),
          _SignalBar(
            label: 'SINR',
            value: sinr,
            min: -10, max: 30, // Plage typique SINR en dB
            unit: 'dB',
            tooltip: 'Rapport signal sur bruit',
            invertColors: false, // SINR : plus haut = meilleur (pas d'inversion)
          ),
        ],
      ),
    );
  }

  // Interprète le RSRP en verdict textuel
  String _interpretRsrp(double v) {
    if (v >= -80) return 'Excellent';
    if (v >= -90) return 'Bon';
    if (v >= -100) return 'Faible';
    return 'Très faible';
  }

  // Couleur associée au verdict RSRP
  Color _rsrpColor(double v) {
    if (v >= -80) return AudaceColors.success;
    if (v >= -90) return const Color(0xFF84CC16); // Vert-jaune (entre succès et avertissement)
    if (v >= -100) return AudaceColors.warning;
    return AudaceColors.error;
  }
}

// ─── Barre de progression d'une métrique de signal ───────────────────────────
class _SignalBar extends StatelessWidget {
  final String label;       // Nom court de la métrique (ex: "RSRP")
  final double? value;      // Valeur mesurée (null = indisponible)
  final double min;         // Borne basse de la plage normalisée
  final double max;         // Borne haute de la plage normalisée
  final String unit;        // Unité affichée (ex: "dBm")
  final String tooltip;     // Description (non affichée actuellement, garde le contexte)
  final bool invertColors;  // true = valeur basse est mauvaise (par défaut)

  const _SignalBar({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.tooltip,
    this.invertColors = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    // Normalise la valeur entre 0.0 et 1.0 selon la plage [min, max]
    final normalized = hasValue
        ? ((value! - min) / (max - min)).clamp(0.0, 1.0)
        : 0.0;
    final barColor = hasValue
        ? _colorFromNormalized(normalized)
        : AudaceColors.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Label de la métrique (largeur fixe pour alignement)
            SizedBox(
              width: 42,
              child: Text(
                label,
                style: AppTextStyles.mono(
                  color: AudaceColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Barre de progression (fond gris + remplissage coloré proportionnel)
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: AudaceColors.border, // Piste de fond
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: normalized, // Largeur proportionnelle à la valeur
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(
                          colors: [barColor.withOpacity(0.7), barColor],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Valeur numérique + unité (largeur fixe, alignée à droite)
            SizedBox(
              width: 72,
              child: Text(
                hasValue ? '${value!.toStringAsFixed(1)} $unit' : '— $unit',
                textAlign: TextAlign.right,
                style: AppTextStyles.mono(
                  color: hasValue ? barColor : AudaceColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Couleur de la barre selon la position normalisée (0.0–1.0)
  // Seuils : ≥70% vert, ≥40% orange, sinon rouge
  Color _colorFromNormalized(double n) {
    if (n >= 0.7) return AudaceColors.success;
    if (n >= 0.4) return AudaceColors.warning;
    return AudaceColors.error;
  }
}

// ─── Badge du type de réseau (ex: "4G", "5G", "3G") ──────────────────────────
class _NetworkTypeBadge extends StatelessWidget {
  final String label;
  const _NetworkTypeBadge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        colors: [AudaceColors.primary, AudaceColors.primaryLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Text(
      label,
      style: AppTextStyles.mono(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
