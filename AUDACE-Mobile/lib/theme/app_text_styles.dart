// Styles de texte paramétriques utilisés principalement sur la carte de couverture.
// Ces deux méthodes permettent de créer des TextStyle avec seulement les paramètres voulus,
// sans avoir à spécifier tous les champs comme avec TextStyle directement.

import 'package:flutter/material.dart';

class AppTextStyles {
  // Famille de police monospace pour les valeurs numériques et les données techniques
  static const String _mono = 'monospace';

  // Crée un style de texte proportionnel (police par défaut du thème).
  // Tous les paramètres sont optionnels — seuls ceux fournis sont appliqués.
  static TextStyle body({
    Color? color,           // Couleur du texte (null = héritage du thème)
    double? fontSize,       // Taille en points logiques
    FontWeight? fontWeight, // Graisse (w400 = normal, w700 = gras, etc.)
    double? height,         // Hauteur de ligne (multiplicateur de fontSize)
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
    );
  }

  // Crée un style de texte en police monospace.
  // Utilisé pour les valeurs numériques (débit, latence) et les identifiants techniques.
  static TextStyle mono({
    Color? color,               // Couleur du texte
    double? fontSize,           // Taille en points logiques
    FontWeight? fontWeight,     // Graisse
    double? letterSpacing,      // Espacement entre les caractères (kerning)
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      fontFamily: _mono, // Applique la police monospace pour l'alignement des chiffres
    );
  }
}
