// Écran principal de l'application : dashboard de mesure réseau.
// Contient 3 onglets (Accueil/Classement/Carte), le bouton d'analyse (FAB)
// et l'affichage détaillé des dernières métriques collectées.

import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../l10n/app_strings.dart';
import '../models/network_metrics.dart';
import '../services/app_settings.dart';
import '../services/metrics_service.dart';
import '../services/export_service.dart';
import '../services/onboarding_service.dart';
import '../services/queue_service.dart';
import '../theme/app_theme.dart';
import 'coverage_map_screen.dart';
import 'debug_queue_screen.dart';
import 'ranking_screen.dart';
import 'settings_screen.dart';
import '../widgets/signal_gauge.dart';
import '../widgets/score_gauge.dart';
import '../widgets/operator_logo.dart';
import '../widgets/tutorial_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final MetricsService _metricsService = MetricsService();
  final ExportService _exportService = ExportService();

  AppStrings get _s => AppStrings(AppSettings().languageCode.value);

  NetworkMetrics? _metrics;     // Dernière mesure collectée (null = pas encore de mesure)
  bool _isCollecting = false;   // true pendant la collecte (désactive le FAB)
  String _progressStep = '';    // Texte de l'étape en cours
  double _progress = 0.0;       // Progression de 0.0 à 1.0
  int _selectedTab = 0;         // 0=Accueil, 1=Classement, 2=Carte
  bool _techExpanded = false;   // État du panneau "détails techniques" repliable

  late AnimationController _pulseController; // Anime le cercle pulsant de l'état vide
  Timer? _tutorialTimer;

  // Clés pour cibler les widgets du tutoriel coach mark
  final _keyFab        = GlobalKey();
  final _keySettings   = GlobalKey();
  final _keyTabRanking = GlobalKey();
  final _keyTabMap     = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Animation de pulsation continue (2s, va-et-vient) pour l'icône de l'état vide
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTriggerTutorial());
  }

  // Vérifie si le tutoriel "home" doit être affiché (première visite)
  Future<void> _maybeTriggerTutorial() async {
    if (!mounted) return;
    final show = await OnboardingService.shouldShow('home');
    if (!show || !mounted) return;
    // Délai de 1.5s pour laisser l'écran se stabiliser avant d'afficher le tutoriel
    _tutorialTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _showHomeTutorial();
    });
  }

  // Affiche le tutoriel coach mark avec 4 cibles : FAB, réglages, onglet classement, onglet carte
  void _showHomeTutorial() {
    final fr = AppSettings().languageCode.value == 'fr';
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'fab',
          keyTarget: _keyFab,
          shape: ShapeLightFocus.RRect,
          radius: 28,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (_, __) => TutorialContent(
                icon: Icons.play_arrow_rounded,
                title: fr ? 'Lancer une mesure' : 'Start a test',
                body: fr
                    ? 'Appuyez ici pour analyser votre réseau. Débit, latence, gigue et signal sont mesurés en ~15 secondes.'
                    : 'Tap here to analyse your network. Speed, latency, jitter and signal are measured in ~15 s.',
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'settings',
          keyTarget: _keySettings,
          shape: ShapeLightFocus.RRect,
          radius: 10,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (_, __) => TutorialContent(
                icon: Icons.settings_rounded,
                title: fr ? 'Paramètres' : 'Settings',
                body: fr
                    ? 'Langue, notifications et FAQ accessibles ici.'
                    : 'Language, notifications and FAQ available here.',
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'tab-ranking',
          keyTarget: _keyTabRanking,
          shape: ShapeLightFocus.RRect,
          radius: 14,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (_, __) => TutorialContent(
                icon: Icons.leaderboard_rounded,
                title: fr ? 'Classement' : 'Ranking',
                body: fr
                    ? 'Comparez les performances de tous les opérateurs camerounais.'
                    : 'Compare all Cameroonian operators in real time.',
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'tab-map',
          keyTarget: _keyTabMap,
          shape: ShapeLightFocus.RRect,
          radius: 14,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (_, __) => TutorialContent(
                icon: Icons.location_on_rounded,
                title: fr ? 'Carte de couverture' : 'Coverage map',
                body: fr
                    ? 'Visualisez la qualité du réseau par zone géographique.'
                    : 'See network quality by geographic area.',
              ),
            ),
          ],
        ),
      ],
      colorShadow: AudaceColors.primary,
      opacityShadow: 0.85,
      paddingFocus: 10,
      textSkip: fr ? 'Passer' : 'Skip',
      alignSkip: Alignment.topRight,
      onFinish: () => OnboardingService.markShown('home'),
      onSkip: () { OnboardingService.markShown('home'); return true; },
    ).show(context: context, rootOverlay: true);
  }

  @override
  void dispose() {
    _tutorialTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // Lance la collecte complète des métriques via MetricsService
  Future<void> _startCollection() async {
    setState(() {
      _isCollecting = true;
      _progress = 0.0;
      _progressStep = 'Démarrage…';
    });
    try {
      final metrics = await _metricsService.collectAllMetrics(
        onProgress: (step, progress) {
          // Met à jour l'UI à chaque étape (callback synchrone, peut être appelé hors build)
          if (mounted) setState(() { _progressStep = step; _progress = progress; });
        },
      );
      setState(() => _metrics = metrics);
    } catch (e) {
      if (mounted) {
        final msg = _messageErreur(e);
        // null = erreur de permission silencieuse, pas de SnackBar (l'utilisateur a déjà vu le dialogue système)
        if (msg != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: AudaceColors.error,
            duration: const Duration(seconds: 4),
          ));
        }
      }
    } finally {
      if (mounted) setState(() => _isCollecting = false);
    }
  }

  // Partage le fichier exporté (JSON) des dernières métriques
  Future<void> _shareFile() async {
    if (_metrics == null) return;
    try {
      await _exportService.shareFile(_metrics!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur de partage : $e'),
          backgroundColor: AudaceColors.error,
        ));
      }
    }
  }

  // Traduit une exception technique en message utilisateur lisible
  // Retourne null pour les erreurs de permission (déjà gérées par le dialogue système)
  String? _messageErreur(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('permission') || raw.contains('platformexception')) return null;
    if (raw.contains('timeout') || raw.contains('sockete') || raw.contains('network')) {
      return _s.networkError;
    }
    return _s.analysisError;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AudaceColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildCurrentTab()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
      // Le FAB n'apparaît que sur l'onglet Accueil
      floatingActionButton: _selectedTab == 0 ? _buildFAB() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // Sélectionne le contenu de l'onglet actif
  Widget _buildCurrentTab() {
    return switch (_selectedTab) {
      1 => RankingScreen(currentOperator: _metrics?.operatorName),
      2 => CoverageMapScreen(metrics: _metrics),
      _ => _metrics == null ? _buildEmptyState() : _buildDashboard(),
    };
  }

  // ─── Header ───────────────────────────────────────────────────────────────
  // Logo AUDACE + titre + boutons (partage, réglages, debug en mode dev)
  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/logo/icon.jpeg',
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              // Repli si l'asset est manquant : icône signal sur fond teal
              errorBuilder: (_, __, ___) => Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AudaceColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.signal_cellular_alt, color: Colors.white, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'AUDACE',
              style: TextStyle(
                color: AudaceColors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
          // Bouton partage affiché seulement s'il y a des métriques à partager
          if (_metrics != null) ...[
            _HeaderBtn(
              icon: Icons.share_rounded,
              onTap: _shareFile,
            ),
            const SizedBox(width: 8),
          ],
          _HeaderBtn(
            key: _keySettings,
            icon: Icons.settings_rounded,
            filled: true, // Bouton mis en avant (fond teal plein)
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          // Bouton de debug (file SQLite) visible uniquement en mode debug
          if (kDebugMode) ...[
            const SizedBox(width: 8),
            _HeaderBtn(
              icon: Icons.storage_rounded,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DebugQueueScreen(queue: QueueService())),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── État vide (avant toute mesure) ────────────────────────────────────────
  // Affiche les 4 fonctionnalités principales + icône pulsante incitant à l'action
  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 120),
      child: Column(
        children: [
          const SizedBox(height: 40),
          // Cercle pulsant (échelle oscillant entre 1.0 et 1.04)
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Transform.scale(
              scale: 1.0 + _pulseController.value * 0.04,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AudaceColors.primary.withOpacity(0.08),
                  border: Border.all(color: AudaceColors.primary.withOpacity(0.25), width: 2),
                ),
                child: const Icon(Icons.wifi_tethering_rounded, color: AudaceColors.primary, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(_s.readyToAnalyze, style: AudaceText.headline),
          const SizedBox(height: 10),
          Text(_s.readyDescription, textAlign: TextAlign.center, style: AudaceText.subtitle),
          const SizedBox(height: 28),
          // Présentation des 4 catégories de mesures effectuées
          _FeatureRow(icon: Icons.cell_tower_rounded, title: _s.signalFeatureTitle, desc: _s.signalFeatureDesc),
          const SizedBox(height: 10),
          _FeatureRow(icon: Icons.speed_rounded, title: _s.connectivityFeatureTitle, desc: _s.connectivityFeatureDesc),
          const SizedBox(height: 10),
          _FeatureRow(icon: Icons.web_rounded, title: _s.qoeFeatureTitle, desc: _s.qoeFeatureDesc),
          const SizedBox(height: 10),
          _FeatureRow(icon: Icons.smartphone_rounded, title: _s.contextFeatureTitle, desc: _s.contextFeatureDesc),
        ],
      ),
    );
  }

  // ─── Dashboard (après une mesure) ──────────────────────────────────────────
  Widget _buildDashboard() {
    final m = _metrics!;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 130),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bandeau opérateur (logo + nom + MCC/MNC + statut actif)
              _OperatorBanner(metrics: m),
              const SizedBox(height: 14),

              // Jauge de score principale (hero card)
              ScoreGauge(
                score: m.score,
                verdict: m.scoreVerdict,
                downloadMbps: m.connectivity.downloadMbps,
                uploadMbps: m.connectivity.uploadMbps,
                latencyMs: m.connectivity.latencyMs,
              ),
              const SizedBox(height: 20),

              // Section signal radio (RSRP/RSRQ/SINR)
              _SectionLabel(title: _s.sectionSignal, icon: Icons.cell_tower_rounded),
              SignalGaugeRow(
                rsrp: m.radioSignal.rsrp,
                rsrq: m.radioSignal.rsrq,
                sinr: m.radioSignal.sinr,
                networkType: m.radioSignal.networkType.label,
              ),
              const SizedBox(height: 18),

              // Section qualité d'expérience (streaming, web, VoLTE)
              _SectionLabel(title: _s.sectionQoe, icon: Icons.web_rounded),
              _QoeCard(qoe: m.qoe),
              const SizedBox(height: 18),

              // Section informations sur le terminal
              _SectionLabel(title: _s.sectionContext, icon: Icons.smartphone_rounded),
              _TerminalCard(metrics: m),
              const SizedBox(height: 18),

              // Détails techniques (Cell ID, TAC/LAC, MCC/MNC, gigue) — repliable
              _CollapsibleTechDetails(
                metrics: m,
                expanded: _techExpanded,
                onToggle: () => setState(() => _techExpanded = !_techExpanded),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // Carte de progression flottante affichée pendant la collecte (au-dessus du FAB)
        if (_isCollecting)
          Positioned(
            left: 16,
            right: 16,
            bottom: 88,
            child: _ProgressCard(step: _progressStep, progress: _progress),
          ),
      ],
    );
  }

  // ─── Bouton flottant d'analyse (FAB) ───────────────────────────────────────
  // Pilule allongée avec icône + texte, grisée et désactivée pendant la collecte
  Widget _buildFAB() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        key: _keyFab,
        onTap: _isCollecting ? null : _startCollection, // Désactivé pendant la collecte
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 54,
          width: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            gradient: LinearGradient(
              // Gris uni en collecte, dégradé teal sinon
              colors: _isCollecting
                  ? [AudaceColors.textMuted, AudaceColors.textMuted]
                  : [const Color(0xFF0D5252), AudaceColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AudaceColors.primary.withOpacity(0.38),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isCollecting ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _isCollecting ? _s.analyzing : _s.analyzeNetwork,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Barre de navigation inférieure ────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AudaceColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: [
              _NavItem(
                key: const Key('tab-home'),
                icon: Icons.home_rounded,
                label: _s.home,
                selected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
              _NavItem(
                key: const Key('tab-ranking'),
                icon: Icons.leaderboard_rounded,
                label: _s.ranking,
                selected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
                targetKey: _keyTabRanking, // Pour le ciblage du tutoriel
              ),
              _NavItem(
                key: const Key('tab-map'),
                icon: Icons.location_on_rounded,
                label: _s.map,
                selected: _selectedTab == 2,
                onTap: () => setState(() => _selectedTab = 2),
                targetKey: _keyTabMap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets locaux
// ─────────────────────────────────────────────────────────────────────────────

// Label de section avec icône (ex: "SIGNAL RADIO")
class _SectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionLabel({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AudaceColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AudaceColors.primary, size: 15),
        ),
        const SizedBox(width: 9),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .10,
            color: AudaceColors.primary,
          ),
        ),
      ],
    ),
  );
}

// Bouton carré du header (icône seule, fond plein ou contour)
class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled; // true = fond teal plein (bouton mis en avant)
  const _HeaderBtn({super.key, required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: filled ? AudaceColors.primary : AudaceColors.surfaceAlt,
        borderRadius: BorderRadius.circular(11),
        border: filled ? null : Border.all(color: AudaceColors.border),
      ),
      child: Icon(icon, color: filled ? Colors.white : AudaceColors.primary, size: 18),
    ),
  );
}

// Bandeau affichant l'opérateur actuel (logo + nom + MCC/MNC + badge "actif")
class _OperatorBanner extends StatelessWidget {
  final NetworkMetrics metrics;
  const _OperatorBanner({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AudaceColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          OperatorLogo(operatorName: metrics.operatorName, size: 44, borderRadius: 11),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metrics.operatorName, style: AudaceText.title),
                const SizedBox(height: 2),
                Text(
                  'MCC ${metrics.operatorMcc} · MNC ${metrics.operatorMnc} · ${metrics.radioSignal.networkType.label}',
                  style: AudaceText.caption,
                ),
              ],
            ),
          ),
          // Badge "actif" avec puce verte clignotante (statique ici, juste un point coloré)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AudaceColors.success.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AudaceColors.success.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: AudaceColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(
                  AppStrings(AppSettings().languageCode.value).active,
                  style: const TextStyle(color: AudaceColors.success, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Carte de qualité d'expérience (streaming vidéo, navigation web, appels VoLTE)
class _QoeCard extends StatelessWidget {
  final QoEMetrics qoe;
  const _QoeCard({required this.qoe});

  @override
  Widget build(BuildContext context) {
    // Verdict streaming vidéo basé sur le délai de démarrage + nombre de coupures
    String videoLabel() {
      final start = qoe.videoStartDelayMs;
      final buf = qoe.videoBufferingCount ?? 0;
      if (start == null) return '—';
      if (start < 1500 && buf == 0) return 'Bon';
      if (start < 3000 && buf <= 2) return 'Moyen';
      return 'Faible';
    }

    // Couleur associée au verdict textuel
    Color labelColor(String l) {
      if (l == 'Bon') return AudaceColors.success;
      if (l == 'Moyen') return AudaceColors.warning;
      if (l == 'Faible') return AudaceColors.error;
      return AudaceColors.textMuted;
    }

    // Verdict navigation web basé sur le temps de chargement
    String webLabel() {
      final t = qoe.webBrowsingTimeMs;
      if (t == null) return '—';
      if (t < 2000) return 'Bon';
      if (t < 5000) return 'Moyen';
      return 'Faible';
    }

    // Verdict VoLTE (approximé par le taux de succès HTTP)
    String httpLabel() {
      final r = qoe.httpSuccessRatePct;
      if (r == null) return '—';
      if (r >= 90) return 'Bon';
      if (r >= 70) return 'Moyen';
      return 'Faible';
    }

    final videoL = videoLabel();
    final webL = webLabel();
    final httpL = httpLabel();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AudaceColors.border),
      ),
      child: Column(
        children: [
          _QoeRow(icon: Icons.videocam_rounded, label: 'Streaming vidéo', value: videoL, color: labelColor(videoL), border: true),
          _QoeRow(icon: Icons.language_rounded, label: 'Navigation web', value: webL, color: labelColor(webL), border: true),
          _QoeRow(icon: Icons.phone_in_talk_rounded, label: 'Appels VoLTE', value: httpL, color: labelColor(httpL), border: false),
        ],
      ),
    );
  }
}

// Ligne d'une carte QoE (icône + label + verdict coloré)
class _QoeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool border; // true = ligne avec séparateur en bas (pas la dernière)
  const _QoeRow({required this.icon, required this.label, required this.value, required this.color, required this.border});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      border: border ? const Border(bottom: BorderSide(color: AudaceColors.border)) : null,
    ),
    child: Row(
      children: [
        Icon(icon, color: AudaceColors.primaryLight, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: AudaceText.body.copyWith(fontWeight: FontWeight.w600))),
        Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
      ],
    ),
  );
}

// Carte des informations sur le terminal (modèle, OS, connexion, batterie)
class _TerminalCard extends StatelessWidget {
  final NetworkMetrics metrics;
  const _TerminalCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final ctx = metrics.context;
    final s = AppStrings(AppSettings().languageCode.value);
    final battPct = ctx.batteryLevelPct;
    // Couleur de la batterie : vert ≥50%, orange ≥20%, rouge sinon
    final battColor = battPct >= 50 ? AudaceColors.success : battPct >= 20 ? AudaceColors.warning : AudaceColors.error;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AudaceColors.border),
      ),
      child: Column(
        children: [
          _TerminalRow(label: 'Nom', value: '${ctx.deviceBrand} ${ctx.deviceModel}', border: true),
          _TerminalRow(label: 'Modèle', value: ctx.deviceModel, border: true),
          _TerminalRow(label: s.system, value: ctx.osVersion, border: true),
          _TerminalRow(
            label: s.connection,
            value: metrics.activeSession.type,
            // Badge avec le type de réseau (4G/5G/WiFi…) à droite de la valeur
            valueSuffix: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AudaceColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                metrics.radioSignal.networkType.label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AudaceColors.primary),
              ),
            ),
            border: true,
          ),
          _TerminalRow(
            label: s.battery,
            value: '$battPct%${ctx.isCharging ? " ⚡" : ""}', // Éclair si en charge
            valueColor: battColor,
            // Mini barre de niveau de batterie à droite
            valueSuffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 10),
                Container(
                  width: 48,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AudaceColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: battPct / 100,
                    child: Container(
                      decoration: BoxDecoration(
                        color: battColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            border: false, // Dernière ligne, pas de séparateur
          ),
        ],
      ),
    );
  }
}

// Ligne label/valeur de la carte terminal, avec suffixe optionnel (badge, barre…)
class _TerminalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? valueSuffix;
  final bool border;
  const _TerminalRow({required this.label, required this.value, this.valueColor, this.valueSuffix, required this.border});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      border: border ? const Border(bottom: BorderSide(color: AudaceColors.border)) : null,
    ),
    child: Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: AudaceText.caption.copyWith(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(
            value,
            style: AudaceText.body.copyWith(fontWeight: FontWeight.w700, fontSize: 13, color: valueColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?valueSuffix, // Opérateur null-aware spread : n'affiche rien si null
      ],
    ),
  );
}

// Panneau "détails techniques" repliable (Cell ID, TAC/LAC, MCC/MNC, gigue)
class _CollapsibleTechDetails extends StatelessWidget {
  final NetworkMetrics metrics;
  final bool expanded;
  final VoidCallback onToggle;
  const _CollapsibleTechDetails({required this.metrics, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final m = metrics.radioSignal;
    return Column(
      children: [
        // En-tête cliquable (toggle expand/collapse)
        GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              // Coins arrondis en haut seulement si déplié (jonction visuelle avec le contenu)
              borderRadius: expanded ? const BorderRadius.vertical(top: Radius.circular(16)) : BorderRadius.circular(16),
              border: Border.all(color: AudaceColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AudaceColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.developer_board_rounded, color: AudaceColors.primary, size: 15),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'DÉTAILS TECHNIQUES',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .10,
                      color: AudaceColors.primary,
                    ),
                  ),
                ),
                // Chevron qui tourne à 180° (0.5 tour) quand déplié
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: AudaceColors.primary, size: 22),
                ),
              ],
            ),
          ),
        ),
        // Contenu animé (apparition/disparition en fondu croisé)
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity), // État replié = rien
          secondChild: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              border: const Border(
                left: BorderSide(color: AudaceColors.border),
                right: BorderSide(color: AudaceColors.border),
                bottom: BorderSide(color: AudaceColors.border),
              ),
            ),
            child: Column(
              children: [
                const Divider(height: 1, color: AudaceColors.border),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(child: _TechTile(label: 'Cell ID', value: m.cellId ?? '—')),
                      const SizedBox(width: 10),
                      // TAC (4G) ou LAC (2G/3G), selon ce qui est disponible
                      Expanded(child: _TechTile(label: 'TAC / LAC', value: m.tac ?? m.lac ?? '—')),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Row(
                    children: [
                      Expanded(child: _TechTile(label: 'MCC · MNC', value: '${metrics.operatorMcc} · ${metrics.operatorMnc}')),
                      const SizedBox(width: 10),
                      Expanded(child: _TechTile(label: 'Jitter', value: metrics.connectivity.jitterMs != null ? '${metrics.connectivity.jitterMs!.toStringAsFixed(1)} ms' : '—')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 280),
        ),
      ],
    );
  }
}

// Tuile d'une valeur technique (label + valeur en grand)
class _TechTile extends StatelessWidget {
  final String label;
  final String value;
  const _TechTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AudaceColors.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AudaceColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AudaceText.caption.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(value, style: AudaceText.title.copyWith(fontSize: 16)),
      ],
    ),
  );
}

// Carte de progression flottante affichée pendant une collecte en cours
class _ProgressCard extends StatelessWidget {
  final String step;     // Texte de l'étape (ex: "Test du débit descendant...")
  final double progress; // 0.0 à 1.0
  const _ProgressCard({required this.step, required this.progress});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AudaceColors.border),
      boxShadow: [
        BoxShadow(color: AudaceColors.primary.withOpacity(0.12), blurRadius: 18, offset: const Offset(0, 6)),
      ],
    ),
    child: Row(
      children: [
        // Spinner circulaire dans un carré teal clair
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AudaceColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AudaceColors.primary),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step, style: AudaceText.body.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: AudaceColors.border,
                  color: AudaceColors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${(progress * 100).toInt()}%',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AudaceColors.primary),
        ),
      ],
    ),
  );
}

// Ligne de présentation d'une fonctionnalité dans l'état vide (icône + titre + description)
class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _FeatureRow({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AudaceColors.border),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AudaceColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AudaceColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AudaceText.label.copyWith(fontSize: 13)),
              const SizedBox(height: 2),
              Text(desc, style: AudaceText.caption),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: AudaceColors.textMuted, size: 18),
      ],
    ),
  );
}

// Item de la barre de navigation inférieure (icône + label, état sélectionné)
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final GlobalKey? targetKey; // Pour le ciblage du tutoriel coach mark
  const _NavItem({super.key, required this.icon, required this.label, required this.selected, required this.onTap, this.targetKey});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        key: targetKey,
        duration: const Duration(milliseconds: 180),
        height: 52,
        decoration: BoxDecoration(
          // Fond teal très léger si sélectionné
          color: selected ? AudaceColors.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? AudaceColors.primary : AudaceColors.textMuted, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: selected ? AudaceColors.primary : AudaceColors.textMuted,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}
