const mongoose = require('mongoose');

// Certificat de rapport généré: empreinte SHA-256 réelle + signature RSA-2048 ART.
const reportSchema = new mongoose.Schema({
  reportType: { type: String, required: true },
  period: { type: String, required: true },
  format: { type: String, enum: ['CSV', 'PDF'], required: true },
  hash: { type: String, required: true },
  signature: { type: String, required: true },
  issuedAt: { type: Date, required: true },
  issuedBy: { type: String, required: true },
}, { timestamps: true });

module.exports = mongoose.model('Report', reportSchema);
