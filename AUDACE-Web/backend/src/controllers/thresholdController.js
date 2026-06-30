const Threshold = require('../models/Threshold');
const AuditLog = require('../models/AuditLog');

async function list(req, res) {
  const thresholds = await Threshold.find();
  res.json(thresholds);
}

async function update(req, res) {
  const { metric, thresholdLabel, status } = req.body;
  if (!metric) return res.status(400).json({ message: 'metric requis.' });
  const threshold = await Threshold.findOneAndUpdate(
    { metric },
    { thresholdLabel, status },
    { new: true, upsert: true }
  );
  await AuditLog.create({
    time: new Date().toTimeString().slice(0, 5),
    user: req.user.userId,
    action: `Mise à jour Seuil ${metric}`,
  });
  res.json(threshold);
}

module.exports = { list, update };
