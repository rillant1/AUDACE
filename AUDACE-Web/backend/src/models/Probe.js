const mongoose = require('mongoose');

const probeSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  region: { type: String, required: true },
  city: { type: String, required: true },
  lat: { type: Number, default: 0 },
  lng: { type: Number, default: 0 },
  status: { type: String, enum: ['En ligne', 'Hors ligne'], default: 'En ligne' },
  battery: { type: Number, required: true },
  lastSync: { type: Date, default: Date.now },
  restartRequested: { type: Boolean, default: false },
}, { timestamps: true });

module.exports = mongoose.model('Probe', probeSchema);
