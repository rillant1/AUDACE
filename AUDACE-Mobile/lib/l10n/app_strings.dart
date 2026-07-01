// Classe de localisation — toutes les chaînes de l'interface en français et en anglais.
// Instanciée avec le code langue courant ('fr' ou 'en') et retourne automatiquement
// la bonne traduction via le getter _fr.

class AppStrings {
  final String languageCode; // Code langue courant : 'fr' ou 'en'
  const AppStrings(this.languageCode);

  // true si la langue courante est le français
  bool get _fr => languageCode == 'fr';

  // ── Navigation (barre du bas) ──────────────────────────────────────────────
  String get home        => _fr ? 'Accueil'    : 'Home';
  String get ranking     => _fr ? 'Classement' : 'Ranking';
  String get map         => _fr ? 'Carte'      : 'Map';
  String get settings    => _fr ? 'Paramètres' : 'Settings';

  // ── Accueil — état vide (avant la première analyse) ───────────────────────
  String get readyToAnalyze => _fr ? 'Prêt à analyser' : 'Ready to analyze';
  // Description des fonctionnalités sur l'écran d'accueil vide
  String get readyDescription => _fr
      ? 'Appuyez sur ANALYSER LE RÉSEAU pour\nmesurer la qualité de service\net la qualité d\'expérience de votre réseau.'
      : 'Tap ANALYZE NETWORK to\nmeasure the quality of service\nand experience of your network.';

  // Titres et descriptions des 4 blocs de fonctionnalités (accueil vide)
  String get signalFeatureTitle       => _fr ? 'Signal radio'                             : 'Radio signal';
  String get signalFeatureDesc        => 'RSRP, RSRQ, RSSI, SINR, Cell ID'; // Identique dans les deux langues
  String get connectivityFeatureTitle => _fr ? 'Qualité de service'                      : 'Quality of service';
  String get connectivityFeatureDesc  => _fr ? 'Débit, latence, gigue, perte de paquets' : 'Speed, latency, jitter, packet loss';
  String get qoeFeatureTitle          => _fr ? 'Qualité d\'expérience'                   : 'Quality of experience';
  String get qoeFeatureDesc           => _fr ? 'HTTP, navigation web, taux échec apps'   : 'HTTP, web browsing, app failure rate';
  String get contextFeatureTitle      => _fr ? 'Contexte terminal'                        : 'Device context';
  String get contextFeatureDesc       => _fr ? 'Appareil, batterie, position H3'          : 'Device, battery, H3 position';

  // ── Accueil — actions ──────────────────────────────────────────────────────
  String get analyzeNetwork => _fr ? 'ANALYSER LE RÉSEAU' : 'ANALYZE NETWORK'; // Bouton FAB principal
  String get analyzing      => _fr ? 'Analyse en cours...' : 'Analyzing...';   // Pendant l'analyse
  String get save           => _fr ? 'Sauvegarder' : 'Save';                   // Bouton sauvegarder
  String get share          => _fr ? 'Partager'    : 'Share';                  // Bouton partager

  // ── Accueil — titres de sections du dashboard ─────────────────────────────
  String get sectionSignal       => _fr ? 'Signal Radio'                : 'Radio Signal';
  String get sectionConnectivity => _fr ? 'Qualité de service (QoS)'     : 'Quality of Service (QoS)';
  String get sectionQoe          => _fr ? 'Qualité d\'expérience (QoE)'  : 'Quality of Experience (QoE)';
  String get sectionContext      => _fr ? 'Contexte & Terminal'          : 'Context & Device';

  // ── Métriques — labels des cartes de mesure ────────────────────────────────
  String get downloadLabel  => _fr ? 'Débit ↓'            : 'Speed ↓';
  String get uploadLabel    => _fr ? 'Débit ↑'            : 'Speed ↑';
  String get latencyLabel   => _fr ? 'Latence'            : 'Latency';
  String get jitter         => _fr ? 'Gigue'              : 'Jitter';
  String get loss           => _fr ? 'Perte'              : 'Loss';
  String get appFailureRate => _fr ? "Taux d'échec Apps"  : 'App Failure Rate';
  String get availability   => _fr ? 'Dispo'              : 'Avail';

  // ── Contexte terminal — labels des champs de métadonnées ──────────────────
  String get terminal   => 'Terminal'; // Même dans les deux langues
  String get system     => _fr ? 'Système'    : 'System';
  String get battery    => _fr ? 'Batterie'   : 'Battery';
  String get connection => _fr ? 'Connexion'  : 'Connection';
  String get timestamp  => _fr ? 'Horodatage' : 'Timestamp';
  String get charging   => _fr ? 'en charge'  : 'charging';
  String get active     => _fr ? 'ACTIF'      : 'ACTIVE';
  // Messages d'erreur affichés après une analyse incomplète
  String get networkError  => _fr
      ? "Réseau indisponible — certaines mesures n'ont pas pu être effectuées."
      : 'Network unavailable — some measurements could not be completed.';
  String get analysisError => _fr
      ? 'Analyse interrompue. Veuillez réessayer.'
      : 'Analysis interrupted. Please try again.';

  // ── Classement des opérateurs ──────────────────────────────────────────────
  String get networkRanking      => _fr ? 'Classement réseau'   : 'Network ranking';
  String get loadingLabel        => _fr ? 'Chargement en cours…' : 'Loading…';
  String get noMeasurements      => _fr ? 'Aucune mesure enregistrée'  : 'No measurements recorded';
  String get noMeasurementsTitle => _fr ? 'Aucune mesure disponible'   : 'No measurements available';
  String get noMeasurementsHint  => _fr
      ? "Lancez une analyse depuis l'onglet Accueil pour voir le classement en temps réel."
      : 'Run an analysis from the Home tab to see the real-time ranking.';
  String get otherOperators => _fr ? 'Autres opérateurs' : 'Other operators';
  String get bestNetwork    => _fr ? 'Meilleur réseau'   : 'Best network';
  String get currentNetwork => _fr ? 'En cours'          : 'Current';

  // Chaîne pluralisée pour le nombre de mesures (ex: "1 mesure" / "3 mesures")
  String measureCount(int n) =>
      _fr ? '$n mesure${n > 1 ? 's' : ''}' : '$n measurement${n > 1 ? 's' : ''}';
  // Sous-titre du classement (ex: "42 mesures · AUDACE")
  String rankingSubtitle(int total) => '${measureCount(total)} · AUDACE';
  // Note de bas du classement avec le nombre de mesures locales
  String dataNote(int n) => _fr
      ? 'Basé sur ${measureCount(n)} collectées localement. Tirez vers le bas pour actualiser.'
      : 'Based on ${measureCount(n)} collected locally. Pull down to refresh.';

  // ── Carte de couverture — panneau position ────────────────────────────────
  String get yourPosition => _fr ? 'Votre position' : 'Your position';
  String get analyzeHint  => _fr
      ? 'Effectuez une analyse — les données de votre zone apparaîtront ici.'
      : 'Run an analysis — your area data will appear here.';

  // ── Carte de couverture — qualité des hexagones ───────────────────────────
  String get qualityGood    => _fr ? 'Bonne'   : 'Good';
  String get qualityAverage => _fr ? 'Moyenne' : 'Average';
  String get qualityPoor    => _fr ? 'Faible'  : 'Poor';
  // Retourne le label de qualité selon le score (≥70 bon, ≥45 moyen, <45 faible)
  String qualityLabel(double score) =>
      score >= 70 ? qualityGood : score >= 45 ? qualityAverage : qualityPoor;
  // Sous-titre d'une cellule hexagonale (ex: "Meilleur opérateur · 5 mesures dans cette zone")
  String mapCellSubtitle(int n) => _fr
      ? 'Meilleur opérateur · $n mesure${n > 1 ? 's' : ''} dans cette zone'
      : 'Best operator · $n measurement${n > 1 ? 's' : ''} in this area';

  // ── Temps relatif — utilisé pour l'horodatage des données ─────────────────
  // Retourne une chaîne lisible indiquant depuis combien de temps (ex: "il y a 3 min")
  String timeAgo(DateTime? dt) {
    if (dt == null) return ''; // Pas de date connue
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return _fr ? "à l'instant"               : 'just now';
    if (diff.inMinutes < 60) return _fr ? 'il y a ${diff.inMinutes} min' : '${diff.inMinutes} min ago';
    if (diff.inHours   < 24) return _fr ? 'il y a ${diff.inHours}h'   : '${diff.inHours}h ago';
    return _fr ? 'il y a ${diff.inDays}j' : '${diff.inDays}d ago';
  }

  // ── Paramètres ─────────────────────────────────────────────────────────────
  String get language        => _fr ? 'Langue'                        : 'Language';
  String get languageSubtitle=> _fr ? 'Choisissez la langue de l\'app': 'Choose the app language';
  String get french          => _fr ? 'Français'                      : 'French';
  String get english         => _fr ? 'Anglais'                       : 'English';
  String get faq             => 'FAQ'; // Identique dans les deux langues
  String get faqSubtitle     => _fr ? 'Questions fréquentes'          : 'Frequently asked questions';
  String get appVersion      => _fr ? 'Version de l\'application'     : 'App version';

  // ── FAQ — retourne la liste selon la langue active ─────────────────────────
  List<FaqItem> get faqItems => _fr ? _faqFr : _faqEn;

  // 7 questions/réponses en français
  static const _faqFr = [
    FaqItem(
      question: 'Qu\'est-ce qu\'AUDACE ?',
      answer:
          'AUDACE (Outil de mesure de la qualité des réseaux au Cameroun) est une application '
          'développée pour mesurer objectivement la qualité des réseaux mobiles et fixes au Cameroun. '
          'Elle collecte des métriques réelles depuis votre appareil : débit, latence, gigue, '
          'signal radio et disponibilité réseau.',
    ),
    FaqItem(
      question: 'Comment fonctionne le test réseau ?',
      answer:
          'En appuyant sur "Analyser le réseau", l\'app effectue plusieurs mesures en temps réel :\n'
          '• Ping vers 8.8.8.8 pour la latence et la gigue\n'
          '• Téléchargement depuis Cloudflare pour le débit descendant\n'
          '• Envoi de données vers Cloudflare pour le débit montant\n'
          '• Test de navigation web vers art.cm\n'
          '• Lecture du signal radio RSRP/RSRQ depuis la carte SIM\n'
          'Toutes ces mesures sont combinées en un score de qualité sur 100.',
    ),
    FaqItem(
      question: 'Mes données sont-elles confidentielles ?',
      answer:
          'Oui. L\'app ne collecte aucune donnée personnelle identifiable. '
          'Un identifiant anonyme chiffré (SHA-256) est généré localement et ne peut pas être '
          'retracé jusqu\'à vous. Seules les métriques techniques (débit, latence, GPS approximatif) '
          'sont transmises au serveur AUDACE.',
    ),
    FaqItem(
      question: 'Que signifie le score sur 100 ?',
      answer:
          'Le classement des opérateurs utilise un score sur 4 composantes :\n'
          '• Débit descendant (30 pts) : échelle logarithmique, optimal à 35 Mbps\n'
          '• Latence (25 pts) : optimal en dessous de 20 ms\n'
          '• Gigue (25 pts) : optimal en dessous de 5 ms\n'
          '• Signal RSRP (20 pts) : optimal à -44 dBm\n\n'
          'L\'échelle log du débit signifie que passer de 1 à 2 Mbps améliore beaucoup '
          'plus le score que passer de 20 à 21 Mbps — ce qui correspond à l\'expérience réelle.\n\n'
          'Interprétation : 75+ = Excellent · 55–74 = Bon · 35–54 = Moyen · <35 = Faible.',
    ),
    FaqItem(
      question: 'Le classement des opérateurs est-il fiable ?',
      answer:
          'Oui, grâce à deux mécanismes :\n'
          '• Données réelles uniquement : chaque mesure vient d\'un vrai appareil, '
          'pas d\'un simulateur.\n'
          '• Correction bayésienne : un opérateur avec peu de mesures est tiré vers la '
          'moyenne globale. Cela évite qu\'un opérateur avec seulement 3 mesures '
          'chancheuses se retrouve en tête devant un opérateur avec 1000 mesures fiables.\n\n'
          'Opérateurs reconnus : MTN Cameroon, Orange Cameroun, Blue (Camtel), Yoomee.',
    ),
    FaqItem(
      question: 'Puis-je utiliser l\'app sans connexion internet ?',
      answer:
          'Partiellement. Les mesures sont enregistrées localement même hors ligne. '
          'Elles sont automatiquement envoyées au serveur dès que la connexion est rétablie. '
          'En revanche, le test de débit nécessite une connexion active.',
    ),
    FaqItem(
      question: 'Pourquoi l\'app demande-t-elle autant de permissions ?',
      answer:
          'Les permissions servent à :\n'
          '• Localisation : associer les mesures à une zone géographique (hexagone H3)\n'
          '• Téléphonie : lire le nom de l\'opérateur, le RSRP et le type de réseau (4G/5G)\n'
          '• Réseau/WiFi : mesurer le débit et identifier l\'opérateur de la box\n'
          'Aucune permission n\'est utilisée à d\'autres fins que la mesure réseau.',
    ),
  ];

  // 7 questions/réponses en anglais (traduction fidèle du contenu français)
  static const _faqEn = [
    FaqItem(
      question: 'What is AUDACE?',
      answer:
          'AUDACE (Network Quality Measurement Tool for Cameroon) is an application '
          'designed to objectively measure the quality of mobile and fixed networks in Cameroon. '
          'It collects real metrics from your device: throughput, latency, jitter, '
          'radio signal strength, and network availability.',
    ),
    FaqItem(
      question: 'How does the network test work?',
      answer:
          'When you tap "Analyze Network", the app takes several real-time measurements:\n'
          '• Ping to 8.8.8.8 for latency and jitter\n'
          '• Download from Cloudflare for download speed\n'
          '• Data upload to Cloudflare for upload speed\n'
          '• Web browsing test to art.cm\n'
          '• Radio signal reading (RSRP/RSRQ) from SIM card\n'
          'All results are combined into a quality score out of 100.',
    ),
    FaqItem(
      question: 'Is my data private?',
      answer:
          'Yes. The app collects no personally identifiable data. '
          'An encrypted anonymous identifier (SHA-256) is generated locally and cannot be '
          'traced back to you. Only technical metrics (speed, latency, approximate GPS) '
          'are transmitted to the AUDACE server.',
    ),
    FaqItem(
      question: 'What does the score out of 100 mean?',
      answer:
          'The operator ranking uses a score with 4 components:\n'
          '• Download speed (30 pts): logarithmic scale, optimal at 35 Mbps\n'
          '• Latency (25 pts): optimal below 20 ms\n'
          '• Jitter (25 pts): optimal below 5 ms\n'
          '• RSRP signal (20 pts): optimal at -44 dBm\n\n'
          'The log scale for speed means that going from 1 to 2 Mbps improves the score '
          'much more than going from 20 to 21 Mbps — matching real-world experience.\n\n'
          'Key: 75+ = Excellent · 55–74 = Good · 35–54 = Average · <35 = Poor.',
    ),
    FaqItem(
      question: 'Is the operator ranking reliable?',
      answer:
          'Yes, thanks to two mechanisms:\n'
          '• Real data only: every measurement comes from a real device, not a simulator.\n'
          '• Bayesian correction: an operator with few measurements is pulled toward the '
          'global average. This prevents an operator with only 3 lucky measurements '
          'from outranking one with 1000 reliable measurements.\n\n'
          'Recognized operators: MTN Cameroon, Orange Cameroun, Blue (Camtel), Yoomee.',
    ),
    FaqItem(
      question: 'Can I use the app without an internet connection?',
      answer:
          'Partially. Measurements are saved locally even when offline. '
          'They are automatically sent to the server once connectivity is restored. '
          'However, the speed test requires an active connection.',
    ),
    FaqItem(
      question: 'Why does the app request so many permissions?',
      answer:
          'Permissions are used for:\n'
          '• Location: associate measurements with a geographic area (H3 hexagon)\n'
          '• Telephony: read operator name, RSRP signal and network type (4G/5G)\n'
          '• Network/WiFi: measure throughput and identify the box operator\n'
          'No permission is used for any other purpose than network measurement.',
    ),
  ];
}

// Modèle d'un élément FAQ : question + réponse
class FaqItem {
  final String question; // Question affichée dans l'en-tête de la tuile
  final String answer;   // Réponse affichée quand la tuile est dépliée
  const FaqItem({required this.question, required this.answer});
}
