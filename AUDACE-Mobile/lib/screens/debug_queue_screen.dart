// Écran de diagnostic de la file SQLite — accessible en mode debug.
// Affiche toutes les mesures stockées localement avec leur statut (en attente,
// envoyées, échouées) et offre des outils pour forcer la synchronisation.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/queue_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

// Écran de diagnostic de la file SQLite et des outils de synchronisation.
// Accessible uniquement en mode debug (kDebugMode).
class DebugQueueScreen extends StatefulWidget {
  final QueueRepository queue; // Repository injecté (permet les tests unitaires)
  const DebugQueueScreen({super.key, required this.queue});

  @override
  State<DebugQueueScreen> createState() => _DebugQueueScreenState();
}

class _DebugQueueScreenState extends State<DebugQueueScreen> {
  List<QueuedMetric> _mesures = []; // Toutes les mesures de la file (max 200)
  Map<String, int> _stats = {};    // Statistiques : pending / sent / failed
  bool _chargement = true;          // true pendant le chargement initial
  bool _syncing    = false;         // true pendant une synchronisation forcée
  bool _testing    = false;         // true pendant un test de connexion backend
  String? _dernierMessage;          // Message du dernier résultat (sync ou test)
  bool _dernierOk  = false;         // true si le dernier résultat était un succès

  @override
  void initState() {
    super.initState();
    _charger(); // Charge les données au premier affichage
  }

  // Recharge toutes les mesures et les statistiques depuis SQLite
  Future<void> _charger() async {
    setState(() => _chargement = true);
    final all   = await widget.queue.getAll(limit: 200); // 200 dernières mesures
    final stats = await widget.queue.getStats();         // Compteurs par statut
    setState(() {
      _mesures     = all;
      _stats       = stats;
      _chargement  = false;
    });
  }

  // Teste la connexion vers le serveur backend et affiche le résultat
  Future<void> _testerConnexion() async {
    setState(() { _testing = true; _dernierMessage = null; });
    final result = await SyncService().testBackendConnection();
    setState(() {
      _testing        = false;
      _dernierOk      = result.ok;
      _dernierMessage = result.message;
    });
  }

  // Force l'envoi de toutes les mesures en attente vers le backend
  Future<void> _forcerSync() async {
    setState(() { _syncing = true; _dernierMessage = null; });
    final result = await SyncService().forceRetryAll();
    await _charger(); // Recharge après sync pour voir les nouveaux statuts
    setState(() {
      _syncing        = false;
      _dernierOk      = result.success;
      _dernierMessage = result.message;
    });
  }

  // Remet tous les échecs en statut "pending" avec retry_count = 0
  Future<void> _reinitialiserEchecs() async {
    setState(() { _syncing = true; _dernierMessage = null; });
    await widget.queue.resetAllFailed();
    await _charger();
    setState(() {
      _syncing        = false;
      _dernierOk      = true;
      _dernierMessage = 'Tous les échecs remis en attente (retry_count = 0).';
    });
  }

  // Extrait le nom de l'opérateur depuis le JSON d'une mesure
  String _operateur(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final op   = json['operateur'] as Map<String, dynamic>?;
      // Cherche 'operateur.nom' puis 'nom' pour les anciens formats
      return (op?['nom'] ?? json['nom'] ?? '?') as String;
    } catch (_) {
      return '?'; // JSON invalide ou incomplet
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AudaceColors.background,
      appBar: AppBar(
        title: const Text('Diagnostic — File SQLite'),
        backgroundColor: Colors.white,
        foregroundColor: AudaceColors.textDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _charger, // Recharge les données
            tooltip: 'Rafraîchir',
          ),
        ],
      ),
      body: _chargement
          // Indicateur de chargement pendant la lecture SQLite
          ? const Center(child: CircularProgressIndicator(color: AudaceColors.primary))
          : Column(
              children: [
                // ── Bandeau URL du backend configurée ─────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AudaceColors.surfaceAlt, // Fond teal très clair
                  child: Text(
                    'Backend : $kApiBaseUrl',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace', // Police fixe pour les URLs
                      color: AudaceColors.textMedium,
                    ),
                  ),
                ),

                // ── Compteurs : Total / Attente / Envoyées / Échecs ────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Compteur('Total',    _mesures.length,           AudaceColors.textDark),
                      _Compteur('Attente',  _stats['pending'] ?? 0,    AudaceColors.warning),
                      _Compteur('Envoyées', _stats['sent']    ?? 0,    AudaceColors.success),
                      _Compteur('Échecs',   _stats['failed']  ?? 0,    AudaceColors.error),
                    ],
                  ),
                ),

                // ── Bannière de résultat de la dernière action ─────────────
                if (_dernierMessage != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    // Fond vert clair si succès, rouge clair si échec
                    color: _dernierOk
                        ? AudaceColors.success.withOpacity(0.12)
                        : AudaceColors.error.withOpacity(0.12),
                    child: Row(
                      children: [
                        Icon(
                          _dernierOk ? Icons.check_circle_outline : Icons.error_outline,
                          size: 16,
                          color: _dernierOk ? AudaceColors.success : AudaceColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dernierMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _dernierOk ? AudaceColors.success : AudaceColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Bouton fermer la bannière
                        GestureDetector(
                          onTap: () => setState(() => _dernierMessage = null),
                          child: const Icon(Icons.close, size: 14, color: AudaceColors.textMuted),
                        ),
                      ],
                    ),
                  ),

                // ── Boutons d'action ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Row(
                    children: [
                      // Tester la connexion backend
                      Expanded(
                        child: _ActionButton(
                          label: 'Tester backend',
                          icon: Icons.wifi_find_rounded,
                          loading: _testing,
                          color: AudaceColors.primary,
                          onPressed: _testing || _syncing ? null : _testerConnexion,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Forcer l'envoi de toutes les mesures en attente
                      Expanded(
                        child: _ActionButton(
                          label: 'Forcer sync',
                          icon: Icons.cloud_upload_rounded,
                          loading: _syncing,
                          color: AudaceColors.primaryLight,
                          onPressed: _testing || _syncing ? null : _forcerSync,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Remettre les échecs en attente pour un nouvel essai
                      Expanded(
                        child: _ActionButton(
                          label: 'Reset échecs',
                          icon: Icons.restart_alt_rounded,
                          loading: false,
                          color: AudaceColors.warning,
                          onPressed: _testing || _syncing ? null : _reinitialiserEchecs,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: AudaceColors.border),

                // ── Liste des mesures (scrollable) ─────────────────────────
                Expanded(
                  child: _mesures.isEmpty
                      // Message si aucune mesure
                      ? const Center(
                          child: Text(
                            'Aucune mesure.\nLance une analyse pour commencer.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AudaceColors.textMuted),
                          ),
                        )
                      // Liste de cartes expansibles
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _mesures.length,
                          itemBuilder: (_, i) {
                            final m = _mesures[i];
                            return _CarteMesure(
                              mesure:    m,
                              operateur: _operateur(m.json), // Nom de l'opérateur extrait du JSON
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets internes
// ─────────────────────────────────────────────────────────────────────────────

// Compteur vertical : nombre en grand + label en petit
class _Compteur extends StatelessWidget {
  final String label;  // Ex: "Attente"
  final int valeur;    // Nombre à afficher
  final Color couleur; // Couleur de la valeur

  const _Compteur(this.label, this.valeur, this.couleur);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$valeur',
          style: TextStyle(color: couleur, fontSize: 22, fontWeight: FontWeight.w800)),
      Text(label,
          style: const TextStyle(color: AudaceColors.textMuted, fontSize: 11)),
    ],
  );
}

// Bouton d'action avec spinner de chargement et état désactivé
class _ActionButton extends StatelessWidget {
  final String label;         // Label du bouton
  final IconData icon;        // Icône à gauche du label
  final bool loading;         // Si true, affiche un spinner au lieu du contenu
  final Color color;          // Couleur de fond du bouton
  final VoidCallback? onPressed; // null = bouton désactivé

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      // Spinner pendant le chargement, icône + label sinon
      child: loading
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14),
                const SizedBox(width: 4),
                Text(label),
              ],
            ),
    );
  }
}

// Carte expansible d'une mesure SQLite
class _CarteMesure extends StatelessWidget {
  final QueuedMetric mesure;  // Mesure avec statut, date, JSON
  final String operateur;     // Nom de l'opérateur extrait du JSON

  const _CarteMesure({required this.mesure, required this.operateur});

  // Couleur du point de statut (orange = en attente, vert = envoyé, rouge = échec)
  Color get _couleur {
    switch (mesure.status) {
      case QueueStatus.pending: return AudaceColors.warning;
      case QueueStatus.sent:    return AudaceColors.success;
      case QueueStatus.failed:  return AudaceColors.error;
    }
  }

  // Libellé du statut en français
  String get _libelle {
    switch (mesure.status) {
      case QueueStatus.pending: return 'En attente';
      case QueueStatus.sent:    return 'Envoyé';
      case QueueStatus.failed:  return 'Échec';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Label du nombre d'essais (affiché uniquement si retry_count > 0)
    final retryLabel = mesure.retryCount > 0
        ? ' · ${mesure.retryCount} essai${mesure.retryCount > 1 ? 's' : ''}'
        : '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _couleur.withOpacity(0.25)), // Bordure de la couleur du statut
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        // Point coloré indiquant le statut
        leading: Container(
          width: 10, height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _couleur),
        ),
        // Nom de l'opérateur
        title: Text(
          operateur,
          style: const TextStyle(
            color: AudaceColors.textDark, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        // Date + statut + nombre d'essais
        subtitle: Text(
          '${mesure.createdAt.toLocal().toString().substring(0, 19)}  ·  $_libelle$retryLabel',
          style: TextStyle(color: _couleur.withOpacity(0.85), fontSize: 11),
        ),
        children: [
          // JSON complet — appui long pour copier dans le presse-papier
          GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: mesure.json));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('JSON copié dans le presse-papier')),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFF8FAFA), // Fond très légèrement teinté
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal, // Scroll horizontal pour les longs JSON
                child: Text(
                  _jsonFormate(mesure.json), // JSON indenté à 2 espaces
                  style: const TextStyle(
                    color: AudaceColors.primary,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          // Hint "appui long" affiché sous le JSON
          const Padding(
            padding: EdgeInsets.only(bottom: 6, right: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Appui long → copier le JSON',
                style: TextStyle(color: AudaceColors.textMuted, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Reformate le JSON avec une indentation de 2 espaces pour la lisibilité
  String _jsonFormate(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw; // Si le JSON est invalide, on l'affiche tel quel
    }
  }
}
