const Probe = require('../models/Probe');

async function list(req, res) {
  const probes = await Probe.find().sort({ createdAt: -1 });
  res.json(probes);
}

async function enroll(req, res) {
  const { region, city } = req.body;
  const count = await Probe.countDocuments();
  const regionCode = (region || 'XX').slice(0, 2).toUpperCase();
  const id = `NP-${regionCode}-${String(1000 + count).padStart(4, '0')}`;
  const probe = await Probe.create({
    id,
    region: region || 'Centre',
    city: city || 'Yaoundé',
    status: 'En ligne',
    battery: 100,
    lastSync: 'À l\'instant',
  });
  res.status(201).json(probe);
}

async function restart(req, res) {
  const probe = await Probe.findOne({ id: req.params.id });
  if (!probe) return res.status(404).json({ message: 'Sonde introuvable.' });
  probe.restartRequested = true;
  await probe.save();
  res.json(probe);
}

module.exports = { list, enroll, restart };
