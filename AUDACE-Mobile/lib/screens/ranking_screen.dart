// Écran de classement des opérateurs réseau (MTN, Orange, Blue/Camtel...).
// Affiche le champion (meilleur score) en grand, puis les autres opérateurs en liste.
// Tente d'abord le classement serveur (toutes mesures), bascule sur SQLite local en fallback.

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../l10n/app_strings.dart';
import '../models/operator_performance.dart';
import '../services/app_settings.dart';
import '../services/coverage_insights_service.dart';
import '../services/onboarding_service.dart';
import '../services/queue_service.dart';
import '../theme/app_theme.dart';
import '../widgets/operator_logo.dart';
import '../widgets/tutorial_content.dart';

class RankingScreen extends StatefulWidget {
  final String? currentOperator;          // Opérateur actuel de l'utilisateur (pour le badge "réseau actuel")
  final QueueRepository _queue;           // Injectable en test
  final CoverageInsightsService _insights; // Injectable en test

  RankingScreen({
    super.key,
    required this.currentOperator,
    QueueRepository? queue,
    CoverageInsightsService? insights,
  })  : _queue   = queue   ?? QueueService(),
        _insights = insights ?? const CoverageInsightsService();

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  List<OperatorPerformance> _operators = []; // Classement trié (index 0 = champion)
  bool _loading = true;
  int _totalMeasures = 0; // Nombre total de mesures (serveur ou local)

  // Clés pour cibler les widgets du tutoriel coach mark
  final _keyTotal   = GlobalKey();
  final _keyChampion = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RankingScreen old) {
    super.didUpdateWidget(old);
    // Recharge si l'opérateur de l'utilisateur a changé (ex: nouvelle mesure prise)
    if (widget.currentOperator != old.currentOperator) _load();
  }

  // Charge le classement : essaie le serveur, sinon retombe sur la BD locale.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 1. Essai serveur — total exact MongoDB + classement tous appareils
      final result = await widget._insights.buildRankingsFromServer();
      if (result.operators.isNotEmpty && mounted) {
        setState(() {
          _operators     = result.operators;
          _totalMeasures = result.total;
          _loading       = false;
        });
        // Déclenche le tutoriel après le premier rendu (sinon GlobalKey pas encore attachée)
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTriggerTutorial());
        return;
      }
      // 2. Fallback local — mesures de cet appareil uniquement
      final operators = await widget._insights.buildRankingsFromDB(widget._queue);
      final all       = await widget._queue.getAll(limit: 500);
      if (mounted) {
        setState(() {
          _operators     = operators;
          _totalMeasures = all.length;
          _loading       = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTriggerTutorial());
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Vérifie si le tutoriel "ranking" doit être affiché (première visite uniquement)
  Future<void> _maybeTriggerTutorial() async {
    if (!mounted) return;
    final show = await OnboardingService.shouldShow('ranking');
    if (!show || !mounted) return;
    _showRankingTutorial();
  }

  // Affiche le tutoriel coach mark avec 2 cibles : total des mesures + carte champion
  void _showRankingTutorial() {
    final fr = AppSettings().languageCode.value == 'fr';
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'total',
          keyTarget: _keyTotal,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (_, __) => TutorialContent(
                icon: Icons.bar_chart_rounded,
                title: fr ? 'Total des mesures' : 'Total measurements',
                body: fr
                    ? 'Ce chiffre représente toutes les mesures collectées sur l\'ensemble des appareils participants.'
                    : 'This number represents all measurements collected across all participating devices.',
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'champion',
          keyTarget: _keyChampion,
          shape: ShapeLightFocus.RRect,
          radius: 20,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (_, __) => TutorialContent(
                icon: Icons.emoji_events_rounded,
                title: fr ? 'Meilleur opérateur' : 'Best operator',
                body: fr
                    ? 'L\'opérateur avec le meilleur score global. Le score combine débit (30 pts), latence (25 pts), gigue (25 pts) et signal (20 pts).'
                    : 'The operator with the highest overall score, combining speed (30 pts), latency (25 pts), jitter (25 pts) and signal (20 pts).',
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
      onFinish: () => OnboardingService.markShown('ranking'),
      onSkip: () { OnboardingService.markShown('ranking'); return true; },
    ).show(context: context, rootOverlay: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(AppSettings().languageCode.value);
    return Container(
      color: AudaceColors.background,
      child: RefreshIndicator(
        color: AudaceColors.primary,
        backgroundColor: Colors.white,
        onRefresh: _load, // Tirer pour rafraîchir
        child: CustomScrollView(
          key: const Key('ranking-screen'),
          slivers: [
            // ── En-tête : titre + sous-titre (total des mesures) ──────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.networkRanking, style: AudaceText.headline),
                    const SizedBox(height: 4),
                    Text(
                      key: _keyTotal,
                      _loading
                          ? s.loadingLabel
                          : _operators.isEmpty
                              ? s.noMeasurements
                              : s.rankingSubtitle(_totalMeasures),
                      style: AudaceText.caption,
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── Contenu principal : chargement / vide / liste ──────────────
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AudaceColors.primary)),
              )
            else if (_operators.isEmpty)
              SliverFillRemaining(child: _EmptyState())
            else ...[
              // Carte du meilleur opérateur (champion)
              SliverToBoxAdapter(
                child: Padding(
                  key: _keyChampion,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ChampionCard(leader: _operators.first),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // Séparateur titre (seulement s'il y a d'autres opérateurs à montrer)
              if (_operators.length > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(s.otherOperators, style: AudaceText.label),
                  ),
                ),

              // Liste des autres opérateurs (à partir de l'index 1, le champion étant déjà affiché)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final idx = i + 1; // index 0 = champion, déjà affiché
                    if (idx >= _operators.length) return null;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _OperatorCard(
                        rank: idx + 1, // Rang affiché commence à 2
                        op: _operators[idx],
                        isCurrentOp: _operators[idx].name == (widget.currentOperator ?? ''),
                      ),
                    );
                  },
                  childCount: (_operators.length - 1).clamp(0, 999),
                ),
              ),

              // Note de bas de page (explication de la méthodologie)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  child: _DataNote(totalMeasures: _totalMeasures),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Carte Champion (meilleur opérateur, mise en avant) ───────────────────────
class _ChampionCard extends StatelessWidget {
  final OperatorPerformance leader;
  const _ChampionCard({required this.leader});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(AppSettings().languageCode.value);
    final color = operatorColor(leader.name); // Couleur de marque de l'opérateur

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Dégradé du teal primaire vers la couleur de l'opérateur (mélange 35%)
        gradient: LinearGradient(
          colors: [
            AudaceColors.primary,
            Color.lerp(AudaceColors.primary, color, 0.35)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AudaceColors.primary.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Badge "Meilleur réseau" + compteur de mesures ───────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AudaceColors.gold,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      s.bestNetwork,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                s.measureCount(leader.measurementCount),
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Logo + nom + score circulaire ───────────────────────────────
          Row(
            children: [
              // Logo opérateur dans un ring blanc (effet "médaille")
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: OperatorLogo(
                  operatorName: leader.name,
                  size: 52,
                  borderRadius: 13,
                ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      leader.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.timeAgo(leader.lastMeasuredAt),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),

              // Score circulaire (cercle blanc semi-transparent + chiffre)
              _CircularScore(score: leader.localScore),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),

          // ── Trois pastilles de métriques détaillées ────────────────────
          Row(
            children: [
              _MetricPill(
                icon: Icons.download_rounded,
                label: s.downloadLabel,
                value: leader.downloadMbps != null
                    ? '${leader.downloadMbps!.toStringAsFixed(1)} Mbps'
                    : '—',
              ),
              const SizedBox(width: 10),
              _MetricPill(
                icon: Icons.timer_outlined,
                label: s.latencyLabel,
                value: leader.latencyMs != null
                    ? '${leader.latencyMs!.toStringAsFixed(0)} ms'
                    : '—',
              ),
              const SizedBox(width: 10),
              _MetricPill(
                icon: Icons.ssid_chart_rounded,
                label: s.jitter,
                value: leader.jitterMs != null
                    ? '${leader.jitterMs!.toStringAsFixed(0)} ms'
                    : '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Score circulaire dans la carte champion ───────────────────────────────
class _CircularScore extends StatelessWidget {
  final double score;
  const _CircularScore({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.15),
        border: Border.all(color: Colors.white30, width: 2),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            score.toStringAsFixed(0),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const Text(
            '/100',
            style: TextStyle(color: Colors.white60, fontSize: 9, height: 1),
          ),
        ],
      ),
    );
  }
}

// ─── Pastille de métrique dans la carte champion ───────────────────────────
class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MetricPill({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white60, size: 12),
                const SizedBox(width: 4),
                Text(label,
                    style: const TextStyle(color: Colors.white60, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Carte opérateur standard (rang ≥ 2) ──────────────────────────────────────
class _OperatorCard extends StatelessWidget {
  final int rank;             // Rang affiché (2, 3, 4...)
  final OperatorPerformance op;
  final bool isCurrentOp;     // true = c'est l'opérateur actuel de l'utilisateur
  const _OperatorCard({required this.rank, required this.op, required this.isCurrentOp});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(AppSettings().languageCode.value);
    final color = operatorColor(op.name);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AudaceColors.surface,
        borderRadius: BorderRadius.circular(16),
        // Bordure plus marquée si c'est l'opérateur actuel de l'utilisateur
        border: Border.all(
          color: isCurrentOp
              ? AudaceColors.primary.withOpacity(0.5)
              : AudaceColors.border,
          width: isCurrentOp ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Numéro de rang dans un cercle
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AudaceColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  rank.toString(),
                  style: TextStyle(
                    color: AudaceColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Logo opérateur
              OperatorLogo(operatorName: op.name, size: 40, borderRadius: 10),
              const SizedBox(width: 12),

              // Nom + badge "réseau actuel" éventuel + sous-titre
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            op.name,
                            style: AudaceText.title.copyWith(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Affiché seulement si c'est l'opérateur SIM/WiFi actuel de l'utilisateur
                        if (isCurrentOp)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AudaceColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              s.currentNetwork,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.measureCount(op.measurementCount)} · ${s.timeAgo(op.lastMeasuredAt)}',
                      style: AudaceText.caption,
                    ),
                  ],
                ),
              ),

              // Pastille de score (couleur de marque)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Text(
                  '${op.localScore.toStringAsFixed(0)}/100',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          // ── Ligne de métriques détaillées (débit / latence / gigue) ────
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AudaceColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _MiniMetric(
                  label: s.downloadLabel,
                  value: op.downloadMbps != null
                      ? '${op.downloadMbps!.toStringAsFixed(1)} Mbps'
                      : '—',
                  color: color,
                ),
                _Divider(),
                _MiniMetric(
                  label: s.latencyLabel,
                  value: op.latencyMs != null
                      ? '${op.latencyMs!.toStringAsFixed(0)} ms'
                      : '—',
                  color: color,
                ),
                _Divider(),
                _MiniMetric(
                  label: s.jitter,
                  value: op.jitterMs != null
                      ? '${op.jitterMs!.toStringAsFixed(0)} ms'
                      : '—',
                  color: color,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Petit séparateur vertical entre les métriques
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: AudaceColors.border);
}

// Métrique compacte (label + valeur) dans la ligne de détails
class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniMetric({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: AudaceText.caption),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: AudaceColors.textDark,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── État vide (aucune mesure disponible) ─────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings(AppSettings().languageCode.value);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AudaceColors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bar_chart_rounded,
                  color: AudaceColors.primary, size: 38),
            ),
            const SizedBox(height: 20),
            Text(s.noMeasurementsTitle, style: AudaceText.title),
            const SizedBox(height: 8),
            Text(
              s.noMeasurementsHint,
              textAlign: TextAlign.center,
              style: AudaceText.caption,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Note de bas de page (méthodologie de calcul) ──────────────────────────────
class _DataNote extends StatelessWidget {
  final int totalMeasures;
  const _DataNote({required this.totalMeasures});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(AppSettings().languageCode.value);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AudaceColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AudaceColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AudaceColors.primary, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.dataNote(totalMeasures),
              style: AudaceText.caption,
            ),
          ),
        ],
      ),
    );
  }
}
