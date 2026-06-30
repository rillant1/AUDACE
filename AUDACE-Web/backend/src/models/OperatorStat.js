const mongoose = require('mongoose');

// Correspond exactement au contrat attendu par ArtApiService.getOperatorStats() côté Flutter (lib/services/api_service.dart).
const operatorStatSchema = new mongoose.Schema({
  _id: { type: String, required: true }, // code opérateur, ex: 'MTN', 'ORANGE'
  avg_http_success: { type: Number, required: true },
  avg_web_time: { type: Number, required: true },
  avg_app_failure: { type: Number, required: true },
  avg_latence: { type: Number, required: true },
  avg_debit: { type: Number, required: true },
  total_tests: { type: Number, required: true },
}, { versionKey: false });

module.exports = mongoose.model('OperatorStat', operatorStatSchema);
