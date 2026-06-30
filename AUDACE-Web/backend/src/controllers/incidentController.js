const Incident = require('../models/Incident');

async function list(req, res) {
  const incidents = await Incident.find().sort({ createdAt: -1 });
  res.json(incidents);
}

async function create(req, res) {
  const { title, zone, operatorName, severity } = req.body;
  if (!title || !zone || !operatorName) {
    return res.status(400).json({ message: 'Titre, zone et opérateur requis.' });
  }
  const count = await Incident.countDocuments();
  const id = `INC-2025-${String(count + 1).padStart(3, '0')}`;
  const now = new Date();
  const openedAt = `${String(now.getDate()).padStart(2, '0')}/${String(now.getMonth() + 1).padStart(2, '0')}/${now.getFullYear()} ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  const incident = await Incident.create({
    id,
    title,
    zone,
    operatorName,
    severity: severity || 'Mineur',
    status: 'Ouvert',
    openedAt,
  });
  res.status(201).json(incident);
}

async function acknowledge(req, res) {
  const incident = await Incident.findOne({ id: req.params.id });
  if (!incident) return res.status(404).json({ message: 'Incident introuvable.' });
  incident.acknowledged = true;
  await incident.save();
  res.json(incident);
}

module.exports = { list, create, acknowledge };
