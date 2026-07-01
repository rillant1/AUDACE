import 'package:flutter/material.dart';

// ─── Palette de couleurs AUDACE ──────────────────────────────────────────────
// Fond blanc + teal #006A6A (couleurs du logo ART), inspiration Vinted
class AudaceColors {
  // ── Couleurs de fond ──────────────────────────────────────────────────────
  static const background   = Color(0xFFF4F7F6); // Fond légèrement vert-gris (pages principales)
  static const surface      = Color(0xFFFFFFFF); // Fond des cartes (blanc pur)
  static const surfaceAlt   = Color(0xFFEAF3F3); // Fond teal très clair (badges, sections)

  // ── Couleur principale — teal ART ────────────────────────────────────────
  static const primary      = Color(0xFF006A6A); // Teal foncé (couleur principale du logo)
  static const primaryLight = Color(0xFF00A3A3); // Teal clair (survols, accents secondaires)
  static const primaryGlow  = Color(0xFF006A6A); // Identique à primary — gardé pour cohérence

  // ── Couleurs de texte ─────────────────────────────────────────────────────
  static const textDark     = Color(0xFF0D1F1F); // Presque noir (teal très foncé) — titres
  static const textMedium   = Color(0xFF3D5C5C); // Teal moyen — sous-titres, étiquettes
  static const textMuted    = Color(0xFF8AADAD); // Teal grisé — métadonnées, placeholders

  // ── Bordures ──────────────────────────────────────────────────────────────
  static const border       = Color(0xFFD6E8E8); // Bordure teal claire (cartes, dividers)
  static const borderStrong = Color(0xFF99C4C4); // Bordure plus marquée (focus, sélection)

  // ── États sémantiques ─────────────────────────────────────────────────────
  static const success      = Color(0xFF10B981); // Vert — score bon, envoi réussi
  static const warning      = Color(0xFFF59E0B); // Orange — score moyen, en attente
  static const error        = Color(0xFFEF4444); // Rouge — score faible, erreur

  // ── Couleurs des opérateurs camerounais ───────────────────────────────────
  static const mtn          = Color(0xFFFFCC00); // Jaune MTN
  static const orange       = Color(0xFFFF6600); // Orange Cameroun
  static const camtel       = Color(0xFF0057A8); // Bleu Camtel / Blue
  static const nexttel      = Color(0xFF8B0000); // Bordeaux Nexttel
  static const unknown      = Color(0xFF8AADAD); // Teal gris — opérateur inconnu

  // ── Or — carte "Meilleur opérateur" ─────────────────────────────────────
  static const gold         = Color(0xFFD4A017); // Or foncé (badge champion)
  static const goldLight    = Color(0xFFFFF3CD); // Or clair (fond badge champion)
}

// ─── Thème Material 3 de l'application ──────────────────────────────────────
class AudaceTheme {
  // Retourne le thème clair (l'app n'a pas de thème sombre)
  static ThemeData get light => ThemeData(
    useMaterial3: true,                             // Active Material Design 3
    scaffoldBackgroundColor: AudaceColors.background,
    fontFamily: 'Roboto',                           // Police système Android
    colorScheme: const ColorScheme.light(
      primary:   AudaceColors.primary,              // Couleur principale
      secondary: AudaceColors.primaryLight,         // Couleur secondaire / accent
      surface:   AudaceColors.surface,              // Fond des surfaces (cartes)
      error:     AudaceColors.error,                // Couleur d'erreur
      onPrimary: Colors.white,                      // Texte sur fond primary
      onSurface: AudaceColors.textDark,             // Texte sur fond surface
    ),

    // ── AppBar : fond blanc, pas d'élévation ──────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AudaceColors.textDark,
      elevation: 0,
      surfaceTintColor: Colors.transparent, // Empêche la teinte bleutée de Material3
    ),

    // ── Cartes : fond blanc, bordure subtile ──────────────────────────────
    cardTheme: CardThemeData(
      color: AudaceColors.surface,
      elevation: 0,                          // Pas d'ombre — utilise les bordures
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AudaceColors.border),
      ),
    ),

    // ── Boutons principaux ────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AudaceColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),

    // ── Snackbars flottantes ──────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,            // Flotte au-dessus du contenu
      backgroundColor: AudaceColors.textDark,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    // ── Barre de navigation inférieure ────────────────────────────────────
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AudaceColors.primary,
      unselectedItemColor: AudaceColors.textMuted,
      elevation: 0,
      type: BottomNavigationBarType.fixed, // Tous les onglets ont la même largeur
    ),

    // ── Dividers ──────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AudaceColors.border,
      thickness: 1,
    ),
  );
}

// ─── Styles de texte prédéfinis ──────────────────────────────────────────────
class AudaceText {
  // Titre de page principal — grand et gras
  static const headline = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w800, color: AudaceColors.textDark,
    letterSpacing: -0.3,
  );
  // Titre de section ou d'AppBar
  static const title = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w700, color: AudaceColors.textDark,
  );
  // Sous-titre — teal moyen, semi-gras
  static const subtitle = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w500, color: AudaceColors.textMedium,
  );
  // Corps de texte standard — normal
  static const body = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, color: AudaceColors.textDark,
  );
  // Métadonnées, légendes, notes de bas de page — petit et atténué
  static const caption = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w400, color: AudaceColors.textMuted,
  );
  // Étiquette de champ ou de colonne — semi-gras et espacé
  static const label = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w600, color: AudaceColors.textMedium,
    letterSpacing: 0.3,
  );
  // Valeur numérique principale — grande et très grasse
  static const metric = TextStyle(
    fontSize: 20, fontWeight: FontWeight.w800, color: AudaceColors.textDark,
    letterSpacing: -0.5,
  );
}

// ─── Décoration de carte standard ────────────────────────────────────────────
// Utilisée pour créer des conteneurs cohérents dans toute l'application
BoxDecoration cardDecoration({
  Color? borderColor,     // Couleur de bordure (par défaut AudaceColors.border)
  double radius = 16,     // Rayon des coins arrondis
  List<BoxShadow>? shadows, // Ombres personnalisées (null = ombre par défaut)
}) => BoxDecoration(
  color: AudaceColors.surface,                   // Fond blanc
  borderRadius: BorderRadius.circular(radius),   // Coins arrondis
  border: Border.all(color: borderColor ?? AudaceColors.border),
  boxShadow: shadows ?? [
    BoxShadow(
      color: AudaceColors.primary.withOpacity(0.06), // Ombre teal très légère
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ],
);

// ─── Retourne la couleur de marque d'un opérateur ────────────────────────────
// Correspondance sur le nom en minuscules pour être insensible à la casse
Color operatorColor(String name) {
  final n = name.toLowerCase();
  if (n.contains('mtn'))    return AudaceColors.mtn;      // Jaune MTN
  if (n.contains('orange')) return AudaceColors.orange;   // Orange
  if (n.contains('blue') || n.contains('camtel')) return AudaceColors.camtel; // Bleu Camtel
  return AudaceColors.unknown; // Teal gris par défaut
}

// ─── Retourne le chemin du logo PNG d'un opérateur ───────────────────────────
// Retourne null si l'opérateur n'a pas de logo en assets — le widget OperatorLogo
// affichera alors un fallback avec les initiales de l'opérateur
String? operatorLogoPath(String name) {
  final n = name.toLowerCase();
  if (n.contains('mtn'))    return 'assets/operators/mtn.png';
  if (n.contains('orange')) return 'assets/operators/orange.png';
  if (n.contains('blue') || n.contains('camtel')) return 'assets/operators/blue.png';
  return null; // Pas de logo disponible pour cet opérateur
}
