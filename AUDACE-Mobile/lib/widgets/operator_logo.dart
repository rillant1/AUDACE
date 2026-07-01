// Widget d'affichage du logo d'un opérateur réseau.
// Si l'image PNG existe dans assets/operators/, elle est affichée.
// Sinon, un carré coloré avec les deux premières lettres de l'opérateur est utilisé.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Affiche le logo d'un opérateur avec un fallback graphique si l'image est absente.
class OperatorLogo extends StatelessWidget {
  final String operatorName;  // Nom de l'opérateur (ex: "MTN Cameroon")
  final double size;          // Taille du logo en pixels logiques (défaut : 48)
  final double borderRadius;  // Arrondi des coins en pixels (défaut : 12)

  const OperatorLogo({
    super.key,
    required this.operatorName,
    this.size = 48,
    this.borderRadius = 12,
  });

  // Calcule les initiales à afficher en fallback (2 lettres maximum)
  String get _initials {
    final parts = operatorName.trim().split(' ');
    // Deux mots → première lettre de chaque mot (ex: "MTN Cameroon" → "MC")
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    // Un seul mot → deux premières lettres (ex: "Orange" → "OR")
    if (operatorName.length >= 2) return operatorName.substring(0, 2).toUpperCase();
    // Cas extrême : nom d'un seul caractère
    return operatorName.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Chemin de l'image PNG en assets (null si pas de logo pour cet opérateur)
    final logoPath = operatorLogoPath(operatorName);
    // Couleur de marque de l'opérateur (jaune MTN, orange…)
    final color    = operatorColor(operatorName);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius), // Coins arrondis
      child: SizedBox(
        width: size,
        height: size,
        child: logoPath != null
            // ── Logo PNG de l'opérateur ──────────────────────────────────
            ? Image.asset(
                logoPath,
                width: size,
                height: size,
                fit: BoxFit.contain, // Conserve les proportions sans rogner
                // Si l'image échoue à charger → fallback avec initiales
                errorBuilder: (_, __, ___) => _Fallback(
                  initials: _initials,
                  color: color,
                  size: size,
                ),
              )
            // ── Fallback : initiales sur fond coloré ──────────────────────
            : _Fallback(initials: _initials, color: color, size: size),
      ),
    );
  }
}

// Widget de repli — affiche les initiales de l'opérateur sur un fond coloré semi-transparent
class _Fallback extends StatelessWidget {
  final String initials; // Ex: "MT" pour MTN
  final Color color;     // Couleur de marque de l'opérateur
  final double size;     // Taille du carré en pixels
  const _Fallback({required this.initials, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      // Fond de la couleur de marque à 12% d'opacité (très clair)
      color: color.withOpacity(0.12),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: color,              // Texte dans la couleur de marque
          fontSize: size * 0.33,    // Taille relative : 1/3 de la taille du widget
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,      // Rapproche légèrement les deux lettres
        ),
      ),
    );
  }
}
