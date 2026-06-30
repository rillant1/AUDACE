const Snapshot = require('../models/Snapshot');

function getByKind(kind) {
  return async (req, res) => {
    const snapshot = await Snapshot.findOne({ kind });
    if (!snapshot) return res.status(404).json({ message: `Aucun snapshot '${kind}' disponible.` });
    res.json(snapshot.data);
  };
}

module.exports = { getByKind };
