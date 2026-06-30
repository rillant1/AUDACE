const express = require('express');
const OperatorStat = require('../models/OperatorStat');
const Snapshot = require('../models/Snapshot');

const router = express.Router();

// Statistiques agrégées par opérateur (public — pas d'auth pour QoeScreen)
router.get('/', async (req, res) => {
  const stats = await OperatorStat.find();
  res.json(stats);
});

// Séries temporelles QoE 30 jours par opérateur
router.get('/timeseries', async (req, res) => {
  const snapshot = await Snapshot.findOne({ kind: 'qoe_timeseries' });
  if (!snapshot) return res.status(404).json({ message: 'Aucune série temporelle QoE disponible.' });
  res.json(snapshot.data);
});

module.exports = router;
