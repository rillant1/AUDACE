const mongoose = require('mongoose');

const thresholdSchema = new mongoose.Schema({
  metric: { type: String, required: true, unique: true },
  thresholdLabel: { type: String, required: true },
  status: { type: String, enum: ['CONFORME', 'ALERTE'], default: 'CONFORME' },
}, { timestamps: true });

module.exports = mongoose.model('Threshold', thresholdSchema);
