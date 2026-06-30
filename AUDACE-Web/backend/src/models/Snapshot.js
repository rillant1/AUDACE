const mongoose = require('mongoose');

// Modèle générique "document NoSQL" pour les sections du dashboard dont la forme
// est riche et déjà figée côté Flutter (overview, infrastructure, qos, benchmark).
// Chaque domaine a un seul document actif identifié par `kind`, stocké tel quel (Mixed)
// pour reproduire fidèlement les anciens fichiers JSON d'assets sans dupliquer un schéma
// strict champ par champ.
const snapshotSchema = new mongoose.Schema({
  kind: { type: String, required: true, unique: true },
  data: { type: mongoose.Schema.Types.Mixed, required: true },
}, { timestamps: true });

module.exports = mongoose.model('Snapshot', snapshotSchema);
