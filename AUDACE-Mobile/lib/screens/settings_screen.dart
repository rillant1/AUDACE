// Écran des paramètres de l'application.
// Permet de changer la langue (Français / Anglais) et d'accéder à la FAQ.
// Se reconstruit automatiquement quand la langue change via ValueListenableBuilder.

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../l10n/app_strings.dart';
import '../services/app_settings.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tutorial_content.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Clés globales pour positionner les bulles du tutoriel sur les widgets cibles
  final _keyLanguage = GlobalKey(); // Cible la carte de sélection de langue
  final _keyFaq      = GlobalKey(); // Cible la section FAQ

  @override
  void initState() {
    super.initState();
    // Déclenche le tutoriel APRÈS le premier frame (les widgets doivent être construits
    // pour que les GlobalKeys aient une position sur l'écran)
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTriggerTutorial());
  }

  // Vérifie si le tutoriel de cet écran doit être affiché et le lance si oui
  Future<void> _maybeTriggerTutorial() async {
    if (!mounted) return;
    final show = await OnboardingService.shouldShow('settings');
    if (!show || !mounted) return;
    _showSettingsTutorial();
  }

  // Affiche le TutorialCoachMark de l'écran paramètres (2 étapes)
  void _showSettingsTutorial() {
    final fr = AppSettings().languageCode.value == 'fr'; // Langue courante pour les bulles
    TutorialCoachMark(
      targets: [
        // Étape 1 : Sélection de la langue
        TargetFocus(
          identify: 'language',
          keyTarget: _keyLanguage,
          shape: ShapeLightFocus.RRect,
          radius: 16,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (_, __) => TutorialContent(
                icon: Icons.language_rounded,
                title: fr ? 'Langue' : 'Language',
                body: fr
                    ? 'Choisissez entre le Français et l\'Anglais. Le changement est immédiat sur toute l\'application.'
                    : 'Choose between French and English. The change is immediate across the whole app.',
              ),
            ),
          ],
        ),
        // Étape 2 : Section FAQ
        TargetFocus(
          identify: 'faq',
          keyTarget: _keyFaq,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (_, __) => TutorialContent(
                icon: Icons.help_outline_rounded,
                title: fr ? 'Questions fréquentes' : 'FAQ',
                body: fr
                    ? 'Retrouvez ici les explications sur le fonctionnement d\'AUDACE, les données collectées et la confidentialité.'
                    : 'Find explanations about how AUDACE works, the data collected, and privacy.',
              ),
            ),
          ],
        ),
      ],
      colorShadow: AudaceColors.primary,   // Couleur de l'ombre du spotlight
      opacityShadow: 0.85,                  // Opacité du fond sombre
      paddingFocus: 10,                     // Padding autour du widget ciblé
      textSkip: fr ? 'Passer' : 'Skip',    // Bouton pour ignorer le tutoriel
      alignSkip: Alignment.topRight,
      // Marque le tutoriel comme vu à la fin ou si sauté
      onFinish: () => OnboardingService.markShown('settings'),
      onSkip: () { OnboardingService.markShown('settings'); return true; },
    ).show(context: context, rootOverlay: true);
  }

  // Réinitialise TOUS les tutoriels et affiche un Snackbar de confirmation
  Future<void> _replayTutorial() async {
    await OnboardingService.resetAll(); // Efface tous les flags tutorial_v2_*
    if (!mounted) return;
    final fr = AppSettings().languageCode.value == 'fr';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(fr ? 'Tutoriel réinitialisé' : 'Tutorial reset'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder se reconstruit automatiquement quand la langue change
    return ValueListenableBuilder<String>(
      valueListenable: AppSettings().languageCode,
      builder: (context, lang, _) {
        final s  = AppStrings(lang); // Toutes les chaînes dans la langue courante
        final fr = lang == 'fr';
        return Scaffold(
          backgroundColor: AudaceColors.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AudaceColors.textDark, size: 20),
              onPressed: () => Navigator.pop(context), // Retour à l'écran précédent
            ),
            title: Text(s.settings, style: AudaceText.title),
            centerTitle: false,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            children: [
              // ── Section Langue ──────────────────────────────────────────
              _SectionHeader(title: s.language),
              const SizedBox(height: 8),
              // Container avec GlobalKey pour positionner la bulle du tutoriel
              Container(
                key: _keyLanguage,
                child: _LanguageCard(strings: s),
              ),
              const SizedBox(height: 28),

              // ── Section FAQ ─────────────────────────────────────────────
              Container(
                key: _keyFaq, // Cible de la 2ème bulle du tutoriel
                child: _SectionHeader(title: s.faq),
              ),
              const SizedBox(height: 8),
              // Génère une _FaqTile par question/réponse
              ...s.faqItems.map((item) => _FaqTile(item: item)),
              const SizedBox(height: 28),

              // ── Bouton rejouer tutoriel ──────────────────────────────────
              _ReplayTutorialTile(
                label: fr ? 'Rejouer le tutoriel' : 'Replay tutorial',
                onTap: _replayTutorial,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Tuile "Rejouer le tutoriel" ─────────────────────────────────────────────
class _ReplayTutorialTile extends StatelessWidget {
  final String label;      // Texte du bouton (localisé)
  final VoidCallback onTap; // Action : resetAll() + snackbar

  const _ReplayTutorialTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AudaceColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icône dans un carré teal clair
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AudaceColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.play_lesson_rounded,
                  color: AudaceColors.primary, size: 18),
            ),
            const SizedBox(width: 14),
            // Label
            Expanded(
              child: Text(label,
                  style: AudaceText.body.copyWith(fontWeight: FontWeight.w600)),
            ),
            // Chevron droit
            const Icon(Icons.chevron_right_rounded,
                color: AudaceColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── En-tête de section (ex: "LANGUE", "FAQ") ────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text(
          title.toUpperCase(), // En majuscules pour l'effet "catégorie"
          style: AudaceText.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1, // Espacement typographique pour les labels
            color: AudaceColors.primary,
          ),
        ),
      );
}

// ─── Carte de sélection de langue (Français / Anglais) ───────────────────────
class _LanguageCard extends StatelessWidget {
  final AppStrings strings;
  const _LanguageCard({required this.strings});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AudaceColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Option Français — première rangée (coins arrondis en haut)
          _LangOption(
            flag: '🇫🇷',
            label: strings.french,
            code: 'fr',
            selected: strings.languageCode == 'fr',
            isFirst: true,
          ),
          Divider(height: 1, color: AudaceColors.border),
          // Option Anglais — deuxième rangée (coins arrondis en bas)
          _LangOption(
            flag: '🇬🇧',
            label: strings.english,
            code: 'en',
            selected: strings.languageCode == 'en',
            isFirst: false,
          ),
        ],
      ),
    );
  }
}

// ─── Ligne d'option de langue ─────────────────────────────────────────────────
class _LangOption extends StatelessWidget {
  final String flag;    // Émoji drapeau (🇫🇷 / 🇬🇧)
  final String label;   // Nom de la langue dans la langue active
  final String code;    // Code ISO : 'fr' ou 'en'
  final bool selected;  // true si cette langue est la langue active
  final bool isFirst;   // Utilisé pour arrondir seulement les coins du haut ou du bas

  const _LangOption({
    required this.flag,
    required this.label,
    required this.code,
    required this.selected,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // Appel immédiat à AppSettings — le ValueListenableBuilder de l'écran
      // se reconstruit automatiquement grâce au ValueNotifier
      onTap: () => AppSettings().setLanguage(code),
      borderRadius: BorderRadius.vertical(
        top:    isFirst ? const Radius.circular(16) : Radius.zero,
        bottom: isFirst ? Radius.zero : const Radius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 24)), // Drapeau
            const SizedBox(width: 14),
            // Nom de la langue — gras si sélectionnée
            Expanded(
              child: Text(label,
                  style: AudaceText.body.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  )),
            ),
            // Coche teal si la langue est active
            if (selected)
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: AudaceColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Tuile FAQ expansible ─────────────────────────────────────────────────────
class _FaqTile extends StatefulWidget {
  final FaqItem item;
  const _FaqTile({required this.item});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false; // État courant (plié / déplié)
  late AnimationController _ctrl;
  late Animation<double> _rotation; // Animation de rotation de la flèche (0.0 → 0.5 tour)

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    // Rotation de 0 (flèche vers le bas) à 0.5 (flèche vers le haut = déplié)
    _rotation = Tween(begin: 0.0, end: 0.5).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Bascule l'état et anime la flèche dans la bonne direction
  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          // Bordure teal quand la tuile est dépliée, grise sinon
          color: _expanded
              ? AudaceColors.primary.withOpacity(0.4)
              : AudaceColors.border,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            // ── En-tête de la tuile : icône + question + flèche ─────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Icône point d'interrogation
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AudaceColors.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.help_outline_rounded,
                        color: AudaceColors.primary, size: 16),
                  ),
                  const SizedBox(width: 12),
                  // Texte de la question
                  Expanded(
                    child: Text(widget.item.question,
                        style: AudaceText.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        )),
                  ),
                  // Flèche qui tourne de 180° quand la tuile est dépliée
                  RotationTransition(
                    turns: _rotation,
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AudaceColors.primary, size: 22),
                  ),
                ],
              ),
            ),
            // ── Corps de la réponse — visible uniquement si déplié ──────
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
                // Décalé de 56px à gauche pour s'aligner sous le texte de la question
                child: Text(widget.item.answer,
                    style: AudaceText.caption.copyWith(
                      height: 1.6,
                      color: AudaceColors.textMedium,
                    )),
              ),
          ],
        ),
      ),
    );
  }
}
