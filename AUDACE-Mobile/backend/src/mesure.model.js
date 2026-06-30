const { Schema, model } = require('mongoose');

// Sous-schémas — reflètent exactement NetworkMetrics.toJson()
const ConnectiviteSchema = new Schema({
  debit_descendant_mbps: Number,
  debit_montant_mbps:    Number,
  latence_ms:            Number,
  gigue_ms:              Number,
  taux_perte_paquets:    Number,
}, { _id: false });

const QoeSchema = new Schema({
  http_success_rate_pct:       Number,
  web_browsing_time_ms:        Number,
  video_start_delay_ms:        Number,
  video_buffering_interruptions: Number,
  video_buffering_total_ms:    Number,
  app_failure_rate_pct:        Number,
  url_teste:                   String,
}, { _id: false });

const OperateurSchema = new Schema({
  nom:       String,
  mcc:       String,
  mnc:       String,
  pays_iso:  String,
  en_roaming: Boolean,
}, { _id: false });

const CoordonneesSchema = new Schema({
  latitude:  Number,
  longitude: Number,
}, { _id: false });

const ContexteSchema = new Schema({
  h3_index:            String,
  coordonnees:         CoordonneesSchema,
  horodatage_iso:      String,
  version_application: String,
  identifiant_anonyme: String,
}, { _id: false, strict: false });

const MesureSchema = new Schema({
  device_metric_id: { type: String, unique: true, required: true },
  schema_version:   String,
  generated_at:     String,
  operateur:        OperateurSchema,
  connectivite_qos:             ConnectiviteSchema,
  experience_utilisateur_qoe:   QoeSchema,
  metadonnees_contexte:         ContexteSchema,
  recu_le: { type: Date, default: Date.now },
}, {
  strict: false,          // accepte les champs supplémentaires
  collection: 'mesures',
});

module.exports = model('Mesure', MesureSchema);
