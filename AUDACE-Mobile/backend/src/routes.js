const { Router } = require('express');
const path   = require('path');
const fs     = require('fs');
const Mesure = require('./mesure.model');

const router = Router();

// ── GET /api/app/version — version courante de l'APK ─────────────────────────
router.get('/api/app/version', (_req, res) => {
  try {
    const versionFile = path.join(__dirname, 'app-version.json');
    const data = JSON.parse(fs.readFileSync(versionFile, 'utf8'));
    return res.json(data);
  } catch (err) {
    return res.status(500).json({ erreur: err.message });
  }
});

// ── GET /api/app/download — télécharge le dernier APK ────────────────────────
router.get('/api/app/download', (req, res) => {
  const apkPath = path.join(__dirname, '..', 'public', 'AUDACE.apk');
  if (!fs.existsSync(apkPath)) {
    return res.status(404).json({ erreur: 'APK non disponible sur le serveur' });
  }
  res.download(apkPath, 'AUDACE.apk');
});

// ── POST /api/metrics — reçoit une mesure unique ─────────────────────────────
router.post('/api/metrics', async (req, res) => {
  try {
    const data = req.body;

    if (!data || !data.device_metric_id) {
      return res.status(400).json({ erreur: 'Champ device_metric_id obligatoire' });
    }

    // Tente d'insérer ; si l'id existe déjà → idempotent (pas d'erreur)
    const mesure = await Mesure.findOneAndUpdate(
      { device_metric_id: data.device_metric_id },
      { $setOnInsert: data },
      { upsert: true, new: true, runValidators: false },
    );

    return res.status(201).json({
      ok: true,
      id: mesure._id,
      device_metric_id: mesure.device_metric_id,
    });
  } catch (err) {
    console.error('[POST /api/metrics]', err.message);
    return res.status(500).json({ erreur: err.message });
  }
});

// ── POST /api/metrics/batch — reçoit un tableau de mesures ───────────────────
router.post('/api/metrics/batch', async (req, res) => {
  try {
    const { metrics } = req.body;
    if (!Array.isArray(metrics) || metrics.length === 0) {
      return res.status(400).json({ erreur: 'Tableau metrics[] obligatoire et non vide' });
    }

    const ops = metrics.map((m) => ({
      updateOne: {
        filter: { device_metric_id: m.device_metric_id },
        update: { $setOnInsert: m },
        upsert: true,
      },
    }));

    const result = await Mesure.bulkWrite(ops, { ordered: false });
    return res.status(201).json({
      ok: true,
      inserted: result.upsertedCount,
      doublons: result.matchedCount,
    });
  } catch (err) {
    console.error('[POST /api/metrics/batch]', err.message);
    return res.status(500).json({ erreur: err.message });
  }
});

// ── GET /api/metrics — liste les N dernières mesures (debug) ─────────────────
router.get('/api/metrics', async (req, res) => {
  try {
    const limite = Math.min(parseInt(req.query.limit) || 50, 500);
    const mesures = await Mesure.find({})
      .sort({ recu_le: -1 })
      .limit(limite)
      .select('-__v');
    return res.json({ total: mesures.length, mesures });
  } catch (err) {
    return res.status(500).json({ erreur: err.message });
  }
});

// ── GET /api/rankings — classement des opérateurs (toutes mesures) ───────────
router.get('/api/rankings', async (req, res) => {
  try {
    const [results, totalMeasurements] = await Promise.all([
      Mesure.aggregate([
        { $match: { 'operateur.nom': { $exists: true, $nin: [null, '', 'Inconnu', 'Nexttel'] } } },
        { $group: {
          _id: '$operateur.nom',
          measurementCount: { $sum: 1 },
          avgDownloadMbps:  { $avg: '$connectivite_qos.debit_descendant_mbps' },
          avgUploadMbps:    { $avg: '$connectivite_qos.debit_montant_mbps' },
          avgLatencyMs:     { $avg: '$connectivite_qos.latence_ms' },
          avgJitterMs:      { $avg: '$connectivite_qos.gigue_ms' },
          avgPacketLoss:    { $avg: '$connectivite_qos.taux_perte_paquets_pct' },
          avgRsrpDbm:       { $avg: '$signal_radio.rsrp_dbm' },
          lastSeen:         { $max: '$recu_le' },
        }},
        { $sort: { avgDownloadMbps: -1 } },
      ]),
      Mesure.countDocuments({}),
    ]);
    return res.json({ ok: true, operators: results, totalMeasurements });
  } catch (err) {
    console.error('[GET /api/rankings]', err.message);
    return res.status(500).json({ erreur: err.message });
  }
});

// ── GET /api/coverage — cellules hexagonales H3 (toutes mesures géolocalisées)
router.get('/api/coverage', async (req, res) => {
  try {
    const results = await Mesure.aggregate([
      { $match: { 'metadonnees_contexte.h3_index': { $exists: true, $ne: null } } },
      { $sort: { 'connectivite_qos.debit_descendant_mbps': -1 } },
      { $group: {
        _id: '$metadonnees_contexte.h3_index',
        measurementCount: { $sum: 1 },
        bestOperator:     { $first: '$operateur.nom' },
        avgDownloadMbps:  { $avg: '$connectivite_qos.debit_descendant_mbps' },
        avgUploadMbps:    { $avg: '$connectivite_qos.debit_montant_mbps' },
        avgLatencyMs:     { $avg: '$connectivite_qos.latence_ms' },
        centerLat:        { $avg: '$metadonnees_contexte.coordonnees.latitude' },
        centerLon:        { $avg: '$metadonnees_contexte.coordonnees.longitude' },
        lastSeen:         { $max: '$recu_le' },
      }},
    ]);
    return res.json({ ok: true, cells: results });
  } catch (err) {
    console.error('[GET /api/coverage]', err.message);
    return res.status(500).json({ erreur: err.message });
  }
});

// ── GET /api/health — vérification que le serveur tourne ─────────────────────
router.get('/api/health', (_req, res) => {
  res.json({ ok: true, heure: new Date().toISOString() });
});

module.exports = router;
