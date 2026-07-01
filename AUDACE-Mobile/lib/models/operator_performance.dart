// Modèle représentant les performances mesurées d'un opérateur réseau.
// Utilisé dans le classement et sur la carte de couverture.

import 'package:flutter/material.dart';

// Résumé des performances d'un opérateur basé sur ses mesures agrégées
class OperatorPerformance {
  final String name;              // Nom normalisé de l'opérateur (ex: "MTN Cameroon")
  final double localScore;        // Score local calculé sur 100 pts (mesures de cet appareil)
  final double nationalScore;     // Score national (identique au localScore actuellement)
  final double? downloadMbps;     // Débit descendant moyen en Mbps
  final double? latencyMs;        // Latence moyenne en millisecondes
  final double? jitterMs;         // Gigue moyenne en millisecondes
  final double? signalRsrpDbm;    // Signal RSRP moyen en dBm
  final Color color;              // Couleur de marque de l'opérateur (jaune MTN, orange…)
  final bool isReference;         // true si cet opérateur est utilisé comme référence de comparaison
  final int measurementCount;     // Nombre total de mesures ayant servi au calcul
  final DateTime? lastMeasuredAt; // Date et heure de la dernière mesure reçue

  const OperatorPerformance({
    required this.name,
    required this.localScore,
    required this.nationalScore,
    this.downloadMbps,
    this.latencyMs,
    this.jitterMs,
    this.signalRsrpDbm,
    required this.color,
    this.isReference = false,
    this.measurementCount = 1,
    this.lastMeasuredAt,
  });

  // Statut textuel basé sur le score local :
  // ≥ 78 = Excellent · ≥ 60 = Bon · ≥ 42 = Moyen · < 42 = À surveiller
  String get status {
    if (localScore >= 78) return 'Excellent';
    if (localScore >= 60) return 'Bon';
    if (localScore >= 42) return 'Moyen';
    return 'À surveiller';
  }
}
