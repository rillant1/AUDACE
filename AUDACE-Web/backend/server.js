require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const { connectDb } = require('./src/config/db');

const authRoutes = require('./src/routes/authRoutes');
const ticketRoutes = require('./src/routes/ticketRoutes');
const incidentRoutes = require('./src/routes/incidentRoutes');
const probeRoutes = require('./src/routes/probeRoutes');
const subscriptionRoutes = require('./src/routes/subscriptionRoutes');
const overviewRoutes = require('./src/routes/overviewRoutes');
const infrastructureRoutes = require('./src/routes/infrastructureRoutes');
const qosRoutes = require('./src/routes/qosRoutes');
const benchmarkRoutes = require('./src/routes/benchmarkRoutes');
const statsRoutes = require('./src/routes/statsRoutes');
const reportRoutes = require('./src/routes/reportRoutes');
const thresholdRoutes = require('./src/routes/thresholdRoutes');
const auditLogRoutes = require('./src/routes/auditLogRoutes');
const paymentRoutes  = require('./src/routes/paymentRoutes');

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));
app.use(rateLimit({ windowMs: 60 * 1000, max: 300 }));

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));
app.get('/api/time', (req, res) => res.json({ now: new Date().toISOString() }));

app.use('/api/auth', authRoutes);
app.use('/api/tickets', ticketRoutes);
app.use('/api/incidents', incidentRoutes);
app.use('/api/probes', probeRoutes);
app.use('/api/subscription', subscriptionRoutes);
app.use('/api/overview', overviewRoutes);
app.use('/api/infrastructure', infrastructureRoutes);
app.use('/api/qos', qosRoutes);
app.use('/api/benchmark', benchmarkRoutes);
app.use('/api/stats', statsRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/thresholds', thresholdRoutes);
app.use('/api/audit-logs', auditLogRoutes);
app.use('/api/payments',  paymentRoutes);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ message: 'Erreur interne du serveur.' });
});

const PORT = process.env.PORT || 3000;

connectDb()
  .then(() => {
    app.listen(PORT, () => console.log(`[AUDACE backend] Serveur démarré sur le port ${PORT}`));
  })
  .catch((err) => {
    console.error('[MongoDB] Échec de connexion :', err.message);
    process.exit(1);
  });

module.exports = app;
