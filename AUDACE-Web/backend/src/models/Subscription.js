const mongoose = require('mongoose');

// Document unique représentant le contrat ART actif (un seul abonnement national pour l'instant).
const subscriptionSchema = new mongoose.Schema({
  plan: { type: String, default: 'Pack National Premium' },
  status: { type: String, default: 'Actif' },
  startDate: { type: String, default: '01/03/2025' },
  endDate: { type: String, default: '30/06/2025' },
  autoRenewal: { type: Boolean, default: true },
  amountFcfa: { type: Number, default: 5000000 },
  daysRemaining: { type: Number, default: 45 },
  lastPaymentAction: { type: String, default: 'Aucune opération récente' },
  lastPaymentMethod: { type: String, default: null },
}, { timestamps: true });

module.exports = mongoose.model('Subscription', subscriptionSchema);
