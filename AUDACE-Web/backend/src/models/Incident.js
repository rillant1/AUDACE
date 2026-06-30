const mongoose = require('mongoose');

const incidentSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  title: { type: String, required: true },
  zone: { type: String, required: true },
  operatorName: { type: String, required: true },
  severity: { type: String, enum: ['Critique', 'Majeur', 'Mineur'], required: true },
  status: { type: String, enum: ['Ouvert', 'Clos'], default: 'Ouvert' },
  openedAt: { type: Date, default: Date.now },
  acknowledged: { type: Boolean, default: false },
}, { timestamps: true });

module.exports = mongoose.model('Incident', incidentSchema);
