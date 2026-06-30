const mongoose = require('mongoose');

const invoiceSchema = new mongoose.Schema({
  number: { type: String, required: true, unique: true },
  date: { type: Date, default: Date.now },
  amountFcfa: { type: Number, required: true },
  status: { type: String, enum: ['Payé', 'En attente', 'Impayé'], default: 'Payé' },
}, { timestamps: true });

module.exports = mongoose.model('Invoice', invoiceSchema);
