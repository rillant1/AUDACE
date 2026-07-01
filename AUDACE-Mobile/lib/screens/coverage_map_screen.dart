// Écran "Carte de couverture" : carte OpenStreetMap avec hexagones H3 colorés
// représentant la qualité réseau par zone, position GPS en direct, recherche
// de lieux (Nominatim) et panneau d'information (position ou cellule sélectionnée).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../l10n/app_strings.dart';
import '../models/network_metrics.dart';
import '../services/app_settings.dart';
import '../services/geocoding_service.dart';
import '../services/hex_coverage_service.dart';
import '../services/onboarding_service.dart';
import '../services/queue_service.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/tutorial_content.dart';

class CoverageMapScreen extends StatefulWidget {
  final NetworkMetrics? metrics;
  final QueueRepository queue;

  const CoverageMapScreen({
    super.key,
    required this.metrics,
    QueueRepository? queue,
  }) : queue = queue ?? const _DefaultQueue();

  @override
  State<CoverageMapScreen> createState() => _CoverageMapScreenState();
}

// Adaptateur const qui délègue au singleton QueueService — permet d'avoir
// une valeur par défaut const dans le constructeur tout en restant injectable en test.
class _DefaultQueue implements QueueRepository {
  const _DefaultQueue();
  QueueService get _s => QueueService();
  @override Future<void> enqueue(String id, Map<String, dynamic> j) => _s.enqueue(id, j);
  @override Future<void> markSent(int id) => _s.markSent(id);
  @override Future<void> markFailed(int id) => _s.markFailed(id);
  @override Future<void> requeueFailed() => _s.requeueFailed();
  @override Future<List<QueuedMetric>> getPending() => _s.getPending();
  @override Future<List<QueuedMetric>> getAll({int limit = 500}) => _s.getAll(limit: limit);
  @override Future<int> getPendingCount() => _s.getPendingCount();
  @override Future<Map<String, int>> getStats() => _s.getStats();
  @override Future<void> purgeOldSent() => _s.purgeOldSent();
  @override Future<void> resetAllFailed() => _s.resetAllFailed();
}

class _CoverageMapScreenState extends State<CoverageMapScreen> {
  final _mapController = MapController();
  final _searchCtrl = TextEditingController();
  final _hexService = HexCoverageService();
  final _geoService = GeocodingService();

  static const _defaultCenter = LatLng(3.8480, 11.5021); // Yaoundé (centre par défaut)
  static const _defaultZoom = 11.5;
  static const _gpsZoom = 14.5; // Zoom plus serré quand la position GPS est connue

  List<HexCoverageCell> _cells = [];
  bool _cellsLoading = true;
  bool _tuileHorsLigne = false; // vrai quand les tuiles OSM ne se chargent pas

  List<GeoSearchResult> _searchResults = [];
  bool _searchLoading = false;
  bool _showDropdown = false;

  HexCoverageCell? _selectedCell; // Cellule H3 actuellement sélectionnée (tap sur la carte)
  Timer? _debounce;     // Anti-rebond pour la recherche (500ms)
  Timer? _tutorialTimer;

  // Position GPS en direct (mise à jour via le flux Geolocator)
  LatLng? _livePosition;
  StreamSubscription<Position>? _positionSub;

  // Nom du lieu actuel obtenu par géocodage inverse (ex: "Bastos, Yaoundé")
  String? _locationName;

  // ── Clés pour le tutoriel ─────────────────────────────────────────────────
  final _keySearchBar = GlobalKey();
  final _keyRecenter  = GlobalKey();

  // ── Getters GPS ──────────────────────────────────────────────────────────

  // Position à afficher : GPS en direct en priorité, sinon la position
  // enregistrée lors de la dernière mesure, sinon le centre par défaut (Yaoundé)
  LatLng get _userPosition {
    if (_livePosition != null) return _livePosition!;
    final lat = widget.metrics?.context.latitude;
    final lon = widget.metrics?.context.longitude;
    return lat != null && lon != null ? LatLng(lat, lon) : _defaultCenter;
  }

  bool get _hasGps =>
      _livePosition != null ||
      (widget.metrics?.context.latitude != null &&
          widget.metrics?.context.longitude != null);

  // Couleur du cercle de signal autour du marqueur — basée sur RSRP (priorité) ou RSSI
  Color get _signalColor {
    final rsrp = widget.metrics?.radioSignal.rsrp;
    if (rsrp != null) {
      if (rsrp >= -80) return AudaceColors.success;
      if (rsrp >= -90) return AudaceColors.warning;
      return AudaceColors.error;
    }
    final rssi = widget.metrics?.radioSignal.rssi;
    if (rssi != null) {
      if (rssi >= -60) return AudaceColors.success;
      if (rssi >= -75) return AudaceColors.warning;
      return AudaceColors.error;
    }
    return AudaceColors.textMuted;
  }

  String get _signalLabel {
    final rsrp = widget.metrics?.radioSignal.rsrp;
    if (rsrp != null) {
      if (rsrp >= -80) return 'Fort';
      if (rsrp >= -90) return 'Moyen';
      return 'Faible';
    }
    return widget.metrics != null ? 'Signal' : '—';
  }

  // ── Cycle de vie ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadCells();
    _startLiveGps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Délai de 800ms pour laisser la carte se stabiliser avant le tutoriel
      _tutorialTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) _maybeTriggerTutorial();
      });
    });
  }

  // Vérifie si le tutoriel "map" doit être affiché (première visite)
  Future<void> _maybeTriggerTutorial() async {
    if (!mounted) return;
    final show = await OnboardingService.shouldShow('map');
    if (!show || !mounted) return;
    _showMapTutorial();
  }

  // Affiche le tutoriel coach mark avec 2 cibles : barre de recherche et bouton recentrer
  void _showMapTutorial() {
    final fr = AppSettings().languageCode.value == 'fr';
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'search',
          keyTarget: _keySearchBar,
          shape: ShapeLightFocus.RRect,
          radius: 14,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (_, __) => TutorialContent(
                icon: Icons.search_rounded,
                title: fr ? 'Rechercher un lieu' : 'Search a location',
                body: fr
                    ? 'Tapez le nom d\'une ville ou d\'un quartier pour naviguer rapidement sur la carte.'
                    : 'Type a city or neighbourhood name to navigate quickly on the map.',
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'recenter',
          keyTarget: _keyRecenter,
          shape: ShapeLightFocus.Circle,
          contents: [
            TargetContent(
              align: ContentAlign.left,
              builder: (_, __) => TutorialContent(
                icon: Icons.my_location_rounded,
                title: fr ? 'Ma position' : 'My location',
                body: fr
                    ? 'Appuyez pour recentrer la carte sur votre position GPS actuelle.'
                    : 'Tap to re-centre the map on your current GPS position.',
              ),
            ),
          ],
        ),
      ],
      colorShadow: AudaceColors.primary,
      opacityShadow: 0.82,
      paddingFocus: 12,
      textSkip: fr ? 'Passer' : 'Skip',
      alignSkip: Alignment.topRight,
      onFinish: () => OnboardingService.markShown('map'),
      onSkip: () { OnboardingService.markShown('map'); return true; },
    ).show(context: context, rootOverlay: true);
  }

  // Démarre le suivi GPS en direct : position initiale immédiate puis flux continu
  Future<void> _startLiveGps() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) return;

      // Position initiale immédiate
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() => _livePosition = LatLng(pos.latitude, pos.longitude));
        _mapController.move(_livePosition!, _gpsZoom);
        // Géocodage inverse : obtenir le nom du quartier/lieu
        _geoService.reverseGeocode(pos.latitude, pos.longitude).then((name) {
          if (mounted && name != null) setState(() => _locationName = name);
        });
      }

      // Puis flux continu (mise à jour seulement si déplacement notable)
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 200, // ne mettre à jour le nom que si déplacement > 200 m
        ),
      ).listen((p) {
        if (mounted) {
          setState(() => _livePosition = LatLng(p.latitude, p.longitude));
          // Met à jour le nom du lieu seulement si on s'est déplacé significativement
          _geoService.reverseGeocode(p.latitude, p.longitude).then((name) {
            if (mounted && name != null) setState(() => _locationName = name);
          });
        }
      });
    } catch (_) {
      // Permission refusée ou GPS indisponible — on reste sur la position des métriques
    }
  }

  // Recentre automatiquement la carte et recharge les cellules quand une nouvelle mesure arrive
  @override
  void didUpdateWidget(covariant CoverageMapScreen old) {
    super.didUpdateWidget(old);
    final newLat = widget.metrics?.context.latitude;
    final newLon = widget.metrics?.context.longitude;
    final oldLat = old.metrics?.context.latitude;
    final oldLon = old.metrics?.context.longitude;
    if (newLat != null && newLon != null && (newLat != oldLat || newLon != oldLon)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(LatLng(newLat, newLon), _gpsZoom);
      });
      _loadCells(); // recharger les cellules après une nouvelle mesure
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tutorialTimer?.cancel();
    _positionSub?.cancel();
    _searchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ── Chargement des hexagones ──────────────────────────────────────────────

  Future<void> _loadCells() async {
    setState(() => _cellsLoading = true);
    try {
      // 1. Essai serveur — toutes les mesures géolocalisées de tous les appareils
      final serverCells = await _hexService.loadCellsFromServer();
      if (serverCells.isNotEmpty && mounted) {
        setState(() { _cells = serverCells; _cellsLoading = false; });
        return;
      }
      // 2. Fallback local — mesures de cet appareil uniquement (hors ligne ou serveur vide)
      await _hexService.seedDemoData(widget.queue);
      final cells = await _hexService.loadCells(widget.queue);
      if (mounted) setState(() { _cells = cells; _cellsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _cellsLoading = false);
    }
  }

  // ── Recherche Nominatim ───────────────────────────────────────────────────

  // Recherche de lieux avec anti-rebond de 500ms (évite une requête par frappe)
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() { _searchResults = []; _showDropdown = false; });
      return;
    }
    setState(() => _searchLoading = true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await _geoService.search(value);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _showDropdown = results.isNotEmpty;
          _searchLoading = false;
        });
      }
    });
  }

  // Déplace la carte vers le résultat choisi et sélectionne la cellule H3 la plus proche
  void _onSearchResultSelected(GeoSearchResult result) {
    final latlng = LatLng(result.lat, result.lon);
    _mapController.move(latlng, 14.0);
    _searchCtrl.text = result.name;
    setState(() { _showDropdown = false; _searchResults = []; });
    FocusScope.of(context).unfocus();

    // Trouver la cellule H3 la plus proche de ce résultat
    final nearest = _nearestCell(latlng);
    setState(() => _selectedCell = nearest);
  }

  // Tap direct sur la carte : sélectionne la cellule H3 la plus proche du point touché
  void _onMapTap(LatLng latlng) {
    FocusScope.of(context).unfocus();
    setState(() {
      _showDropdown = false;
      _selectedCell = _nearestCell(latlng);
    });
  }

  // Trouve la cellule la plus proche d'un point, dans un rayon max de 700m
  HexCoverageCell? _nearestCell(LatLng point) {
    HexCoverageCell? nearest;
    double minDist = 700; // seuil max 700 m
    for (final cell in _cells) {
      final d = _distanceM(point, LatLng(cell.centerLat, cell.centerLon));
      if (d < minDist) { minDist = d; nearest = cell; }
    }
    return nearest;
  }

  // Formule de Haversine — distance en mètres entre deux points GPS
  double _distanceM(LatLng a, LatLng b) {
    const r = 6371000.0; // Rayon de la Terre en mètres
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final sinLat = math.sin(dLat / 2);
    final sinLon = math.sin(dLon / 2);
    final c = 2 * math.asin(math.sqrt(sinLat * sinLat +
        math.cos(a.latitude * math.pi / 180) *
        math.cos(b.latitude * math.pi / 180) *
        sinLon * sinLon));
    return r * c;
  }

  // Recentre la carte sur la position de l'utilisateur et désélectionne la cellule
  void _recenter() {
    _mapController.move(_userPosition, _hasGps ? _gpsZoom : _defaultZoom);
    setState(() => _selectedCell = null);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('coverage-map-screen'),
      fit: StackFit.expand,
      children: [
        // ── Carte OpenStreetMap ──────────────────────────────────────────
        RepaintBoundary(
          child: FlutterMap(
            key: const Key('coverage-heatmap'),
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userPosition,
              initialZoom: _hasGps ? _gpsZoom : _defaultZoom,
              onTap: (_, latlng) => _onMapTap(latlng),
              onMapEvent: (event) {
                // Quand l'utilisateur bouge la carte, on laisse les tuiles
                // retenter leur chargement et on masque le bandeau.
                if (_tuileHorsLigne &&
                    (event is MapEventMove ||
                        event is MapEventDoubleTapZoom ||
                        event is MapEventScrollWheelZoom)) {
                  setState(() => _tuileHorsLigne = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'cm.art.audace',
                maxZoom: 19,
                errorTileCallback: (tile, error, stackTrace) {
                  // Tuile inaccessible (hors ligne ou réseau restreint) —
                  // on affiche un bandeau discret au lieu de propager l'exception.
                  if (!_tuileHorsLigne && mounted) {
                    setState(() => _tuileHorsLigne = true);
                  }
                },
              ),
              // Bandeau hors-ligne discret (disparaît dès que les tuiles chargent)
              if (_tuileHorsLigne)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xCC1A1A2E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AudaceColors.textMuted.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.signal_wifi_off_rounded,
                              size: 13, color: AudaceColors.textMuted),
                          const SizedBox(width: 5),
                          Text(
                            'Fond de carte indisponible hors ligne',
                            style: AppTextStyles.body(
                                color: AudaceColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Hexagones H3 (chargés depuis le serveur ou la base SQLite locale)
              if (_cells.isNotEmpty)
                PolygonLayer(
                  polygons: _cells.map((cell) => Polygon(
                    points: cell.hexBoundary,
                    // Opacité et épaisseur de bordure augmentées si la cellule est sélectionnée
                    color: cell.color.withOpacity(
                      _selectedCell?.h3Index == cell.h3Index ? 0.55 : 0.30,
                    ),
                    borderColor: cell.color.withOpacity(
                      _selectedCell?.h3Index == cell.h3Index ? 1.0 : 0.75,
                    ),
                    borderStrokeWidth:
                        _selectedCell?.h3Index == cell.h3Index ? 2.5 : 1.5,
                  )).toList(),
                  polygonCulling: true, // N'affiche que les polygones visibles (perf)
                ),
              // Cercle de couverture signal + marqueur position pulsant
              if (_hasGps) ...[
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _userPosition,
                      radius: 120, // 120 mètres réels (useRadiusInMeter)
                      useRadiusInMeter: true,
                      color: _signalColor.withOpacity(0.18),
                      borderColor: _signalColor.withOpacity(0.70),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userPosition,
                      width: 60,
                      height: 60,
                      child: _PulseMarkerWidget(color: AudaceColors.primary),
                    ),
                  ],
                ),
              ],
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),

        // ── Barre de recherche + dropdown ───────────────────────────────
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Column(
            children: [
              _SearchBar(
                key: _keySearchBar,
                controller: _searchCtrl,
                loading: _searchLoading,
                onChanged: _onSearchChanged,
                onClear: () {
                  _searchCtrl.clear();
                  setState(() { _searchResults = []; _showDropdown = false; });
                },
              ),
              if (_showDropdown)
                _SearchDropdown(
                  results: _searchResults,
                  onSelect: _onSearchResultSelected,
                ),
            ],
          ),
        ),

        // ── Indicateur de chargement ────────────────────────────────────
        if (_cellsLoading)
          const Positioned(
            top: 72,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AudaceColors.primary,
                ),
              ),
            ),
          ),

        // ── Bouton recentrer ────────────────────────────────────────────
        Positioned(
          right: 14,
          bottom: 160,
          child: _RecenterButton(key: _keyRecenter, onTap: _recenter),
        ),

        // ── Panneau d'info (position actuelle ou cellule sélectionnée) ──
        Positioned(
          left: 12,
          right: 12,
          bottom: 10,
          child: _selectedCell != null
              ? _CellInfoPanel(
                  cell: _selectedCell!,
                  onClose: () => setState(() => _selectedCell = null),
                )
              : _PositionInfoPanel(
                  metrics: widget.metrics,
                  signalColor: _signalColor,
                  signalLabel: _signalLabel,
                  locationName: _locationName,
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marqueur de position avec animation pulse
// ─────────────────────────────────────────────────────────────────────────────

// Marqueur GPS animé : anneau qui pulse (grossit + s'estompe en boucle) autour
// d'un point central fixe, pour indiquer la position en direct sur la carte.
class _PulseMarkerWidget extends StatefulWidget {
  final Color color;
  const _PulseMarkerWidget({required this.color});

  @override
  State<_PulseMarkerWidget> createState() => _PulseMarkerWidgetState();
}

class _PulseMarkerWidgetState extends State<_PulseMarkerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(); // Boucle continue (sans va-et-vient, repart de 0 à chaque cycle)
    _scale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Anneau pulse (grossit et s'estompe progressivement)
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Transform.scale(
            scale: _scale.value,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(_opacity.value * 0.35),
                border: Border.all(
                  color: widget.color.withOpacity(_opacity.value),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        // Point central fixe (toujours visible, ne pulse pas)
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.45),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Barre de recherche
// ─────────────────────────────────────────────────────────────────────────────

// Champ de recherche flottant en haut de la carte (icône + texte + bouton effacer)
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    super.key,
    required this.controller,
    required this.loading,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AudaceColors.surface.withOpacity(0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AudaceColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icône de recherche remplacée par un spinner pendant le chargement
          loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AudaceColors.primary,
                  ),
                )
              : const Icon(Icons.search_rounded, color: AudaceColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppTextStyles.body(color: AudaceColors.textDark, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher une zone ou un lieu',
                hintStyle: AppTextStyles.body(
                  color: AudaceColors.textMuted,
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          // Bouton d'effacement visible seulement si du texte est saisi
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: onClear,
              child: const Icon(
                Icons.close_rounded,
                color: AudaceColors.textMuted,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dropdown résultats de recherche
// ─────────────────────────────────────────────────────────────────────────────

// Liste déroulante affichée sous la barre de recherche avec les résultats Nominatim
class _SearchDropdown extends StatelessWidget {
  final List<GeoSearchResult> results;
  final ValueChanged<GeoSearchResult> onSelect;

  const _SearchDropdown({required this.results, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AudaceColors.surface.withOpacity(0.97),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AudaceColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: results.map((r) {
          final isLast = r == results.last;
          return InkWell(
            onTap: () => onSelect(r),
            // Coins arrondis seulement sur le premier (haut) et le dernier (bas) élément
            borderRadius: BorderRadius.vertical(
              top: r == results.first ? const Radius.circular(14) : Radius.zero,
              bottom: isLast ? const Radius.circular(14) : Radius.zero,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  const Icon(
                    Icons.place_outlined,
                    color: AudaceColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.name,
                      style: AppTextStyles.body(
                        color: AudaceColors.textDark,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panneau info — position actuelle (pas de cellule sélectionnée)
// ─────────────────────────────────────────────────────────────────────────────

// Panneau du bas affichant soit un message d'invite (aucune mesure), soit
// l'opérateur + débit/upload/latence de la dernière mesure effectuée
class _PositionInfoPanel extends StatelessWidget {
  final NetworkMetrics? metrics;
  final Color signalColor;
  final String signalLabel;
  final String? locationName; // Nom du lieu obtenu par géocodage inverse

  const _PositionInfoPanel({
    required this.metrics,
    required this.signalColor,
    required this.signalLabel,
    this.locationName,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(AppSettings().languageCode.value);
    return _Card(
      child: metrics == null ? _buildVide(s) : _buildMetriques(s),
    );
  }

  // État vide : aucune mesure encore effectuée, juste une invite à analyser
  Widget _buildVide(AppStrings s) {
    return Row(
      children: [
        const Icon(Icons.location_on_rounded, color: AudaceColors.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.yourPosition,
                style: AppTextStyles.mono(
                  color: AudaceColors.textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                s.analyzeHint,
                style: AppTextStyles.body(
                  color: AudaceColors.textMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Affiche les métriques de la dernière mesure : opérateur, position GPS,
  // badge de signal, et chips débit/upload/latence
  Widget _buildMetriques(AppStrings s) {
    final m = metrics!;
    final lat = m.context.latitude;
    final lon = m.context.longitude;
    // Affiche le nom du lieu si disponible, sinon les coordonnées, sinon un message
    final posLabel = locationName
        ?? (lat != null && lon != null
            ? '${lat.toStringAsFixed(4)}°N, ${lon.toStringAsFixed(4)}°E'
            : 'GPS non disponible');
    final dl = m.connectivity.downloadMbps;
    final ul = m.connectivity.uploadMbps;
    final ping = m.connectivity.latencyMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on_rounded, color: AudaceColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                m.operatorName,
                style: AppTextStyles.mono(
                  color: AudaceColors.textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _SignalBadge(label: signalLabel, color: signalColor),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          posLabel,
          style: AppTextStyles.body(color: AudaceColors.textMuted, fontSize: 10),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _Chip(label: s.downloadLabel, value: dl != null ? '${dl.toStringAsFixed(1)} Mbps' : '—')),
            const SizedBox(width: 7),
            Expanded(child: _Chip(label: s.uploadLabel, value: ul != null ? '${ul.toStringAsFixed(1)} Mbps' : '—')),
            const SizedBox(width: 7),
            Expanded(child: _Chip(label: s.latencyLabel, value: ping != null ? '${ping.toStringAsFixed(0)} ms' : '—')),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panneau info — cellule H3 sélectionnée
// ─────────────────────────────────────────────────────────────────────────────

// Panneau du bas affichant les statistiques agrégées d'une cellule H3
// sélectionnée par tap sur la carte ou via la recherche
class _CellInfoPanel extends StatelessWidget {
  final HexCoverageCell cell;
  final VoidCallback onClose;

  const _CellInfoPanel({required this.cell, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(AppSettings().languageCode.value);
    final dl = cell.avgDownloadMbps;
    final ping = cell.avgLatencyMs;
    final avail = cell.avgAvailabilityPct;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Pastille colorée reprenant la couleur de l'hexagone sur la carte
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: cell.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cell.bestOperator,
                  style: AppTextStyles.mono(
                    color: AudaceColors.textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _SignalBadge(label: s.qualityLabel(cell.qualityScore), color: cell.color),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClose,
                child: const Icon(
                  Icons.close_rounded,
                  color: AudaceColors.textMuted,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.mapCellSubtitle(cell.measurementCount),
            style: AppTextStyles.body(
              color: AudaceColors.textMuted,
              fontSize: 10,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Chip(label: s.downloadLabel, value: dl != null ? '${dl.toStringAsFixed(1)} Mbps' : '—')),
              const SizedBox(width: 7),
              Expanded(child: _Chip(label: s.latencyLabel, value: ping != null ? '${ping.toStringAsFixed(0)} ms' : '—')),
              const SizedBox(width: 7),
              Expanded(child: _Chip(label: s.availability, value: avail != null ? '${avail.toStringAsFixed(0)}%' : '—')),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bouton recentrer
// ─────────────────────────────────────────────────────────────────────────────

// Bouton circulaire flottant qui recentre la carte sur la position de l'utilisateur
class _RecenterButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RecenterButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AudaceColors.surface.withOpacity(0.97),
          shape: BoxShape.circle,
          border: Border.all(color: AudaceColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.my_location_rounded,
          color: AudaceColors.primary,
          size: 20,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets partagés
// ─────────────────────────────────────────────────────────────────────────────

// Carte flottante semi-transparente utilisée comme conteneur des panneaux d'info
class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AudaceColors.surface.withOpacity(0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AudaceColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// Petit badge coloré affichant un verdict de qualité de signal (ex: "Fort", "Moyen")
class _SignalBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SignalBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: AppTextStyles.mono(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// Petite pastille label/valeur utilisée pour afficher débit, latence, disponibilité, etc.
class _Chip extends StatelessWidget {
  final String label;
  final String value;

  const _Chip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AudaceColors.background.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AudaceColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.body(color: AudaceColors.textMuted, fontSize: 9)),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.mono(color: AudaceColors.textDark, fontSize: 11, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
