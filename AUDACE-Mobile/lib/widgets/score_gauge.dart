// Widget de jauge de score réseau — carte principale du dashboard.
// Affiche un score sur 100 avec une animation de remplissage circulaire,
// le verdict qualité et les 3 métriques clés (débit ↓, débit ↑, latence).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScoreGauge extends StatefulWidget {
  final int score;           // Score de qualité 0–100
  final String verdict;      // Verdict lisible (ex: "Excellent", "Bon", "À améliorer")
  final double? downloadMbps; // Débit descendant en Mbps (null = non mesuré)
  final double? uploadMbps;   // Débit montant en Mbps (null = non mesuré)
  final double? latencyMs;    // Latence en ms (null = non mesurée)

  const ScoreGauge({
    super.key,
    required this.score,
    required this.verdict,
    this.downloadMbps,
    this.uploadMbps,
    this.latencyMs,
  });

  @override
  State<ScoreGauge> createState() => _ScoreGaugeState();
}

class _ScoreGaugeState extends State<ScoreGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim; // Progression de 0.0 à 1.0

  @override
  void initState() {
    super.initState();
    // Animation de 1400ms avec courbe easeOutCubic (démarre vite, ralentit à la fin)
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward(); // Lance l'animation dès la création du widget
  }

  @override
  void didUpdateWidget(ScoreGauge old) {
    super.didUpdateWidget(old);
    // Si le score change (nouvelle analyse), rejoue l'animation depuis zéro
    if (old.score != widget.score) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose(); // Libère le contrôleur
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Fond dégradé teal foncé → teal moyen (couleur de la carte de score)
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D5252), Color(0xFF1A7878)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D5252).withOpacity(0.30), // Ombre teal foncé
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        children: [
          // ── Ligne d'en-tête : label + compteur animé ───────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'QUALITÉ RÉSEAU',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .12,
                  color: Color(0xFFBFE3DE), // Teal clair
                ),
              ),
              // Compteur "Score : X/100" qui s'anime de 0 jusqu'au score réel
              AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => Text(
                  'Score : ${(_anim.value * widget.score).round()}/100',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9FCFC9), // Teal légèrement atténué
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Jauge circulaire avec score au centre ───────────────────────
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) {
              final displayScore = (_anim.value * widget.score).round(); // Valeur animée
              final color = _scoreColor(widget.score); // Couleur selon le score final
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Cercle de 170×170 px avec le dessin de la jauge
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CustomPaint(
                      painter: _GaugePainter(
                        progress: _anim.value * widget.score / 100, // 0.0 → 1.0
                        color: color,
                      ),
                    ),
                  ),
                  // Contenu centré dans la jauge : score + verdict
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Grand nombre du score ───────────────────────────
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end, // "/100" aligné en bas
                        children: [
                          Text(
                            '$displayScore',
                            style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1, // Pas d'interligne pour centrage parfait
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8), // Décalage vers le bas
                            child: Text(
                              '/100',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9FCFC9),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // ── Badge de verdict ────────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16), // Fond blanc semi-transparent
                          borderRadius: BorderRadius.circular(999), // Pill shape
                        ),
                        child: Text(
                          widget.verdict,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // ── Trois tuiles de métriques rapides ─────────────────────────
          Row(
            children: [
              _QuickStat(
                label: 'DÉBIT ↓',
                value: widget.downloadMbps != null
                    ? widget.downloadMbps!.toStringAsFixed(1)
                    : '—',
                unit: 'Mb/s',
              ),
              _QuickStat(
                label: 'DÉBIT ↑',
                value: widget.uploadMbps != null
                    ? widget.uploadMbps!.toStringAsFixed(1)
                    : '—',
                unit: 'Mb/s',
              ),
              _QuickStat(
                label: 'LATENCE',
                value: widget.latencyMs != null
                    ? widget.latencyMs!.toStringAsFixed(0)
                    : '—',
                unit: 'ms',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Couleur de l'arc de la jauge : vert ≥75, orange ≥35, rouge <35
  Color _scoreColor(int s) {
    if (s >= 75) return AudaceColors.success; // Vert
    if (s >= 35) return AudaceColors.warning; // Orange
    return AudaceColors.error;                // Rouge
  }
}

// ─── Tuile de métrique rapide (débit / latence) ───────────────────────────────
class _QuickStat extends StatelessWidget {
  final String label; // Label en haut (ex: "DÉBIT ↓")
  final String value; // Valeur formatée (ex: "24.5") ou "—" si indisponible
  final String unit;  // Unité (ex: "Mb/s", "ms")

  const _QuickStat({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10), // Fond blanc très semi-transparent
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Label de la métrique (en petit, teal clair)
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9FCFC9),
              letterSpacing: .06,
            ),
          ),
          const SizedBox(height: 4),
          // Valeur + unité en RichText (tailles différentes)
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value, // Grand nombre blanc
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                TextSpan(
                  text: ' $unit', // Unité plus petite et atténuée
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9FCFC9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── CustomPainter de la jauge circulaire ─────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double progress; // Progression 0.0 → 1.0 (animée)
  final Color color;     // Couleur de l'arc (vert/orange/rouge)
  const _GaugePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2; // Centre X
    final cy = size.height / 2; // Centre Y
    final r  = math.min(cx, cy) - 10; // Rayon (laisse 10px de marge)

    // Brosse du fond de la jauge (cercle complet blanc à 12% d'opacité)
    final trackPaint = Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap   = StrokeCap.round
      ..color       = Colors.white.withOpacity(0.12);

    // Brosse de l'arc de progression (couleur selon le score)
    final arcPaint = Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap   = StrokeCap.round // Extrémités arrondies
      ..color       = color;

    const startAngle = -math.pi / 2; // Démarre en haut (12h)
    const sweep      = 2 * math.pi;  // Tour complet = 360°

    // 1. Dessine le cercle de fond (toujours 100%)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle,
      sweep,
      false, // false = ne remplit pas l'intérieur
      trackPaint,
    );

    // 2. Dessine l'arc de progression (proportionnel au score)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle,
      sweep * progress, // Ex: 0.75 * 2π = 270° pour un score de 75
      false,
      arcPaint,
    );
  }

  // Ne redessine que si la progression ou la couleur a changé
  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.color != color;
}
