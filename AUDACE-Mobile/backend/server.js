require('dotenv').config();
const mongoose = require('mongoose');
const app      = require('./src/app');

const PORT     = process.env.PORT     || 3000;
const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/audace';

mongoose.connect(MONGO_URI)
  .then(() => {
    console.log(`✅ MongoDB connecté → ${MONGO_URI}`);
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`✅ Serveur AUDACE démarré sur http://0.0.0.0:${PORT}`);
      console.log(`   POST http://0.0.0.0:${PORT}/api/metrics`);
      console.log(`   GET  http://0.0.0.0:${PORT}/api/health`);
    });
  })
  .catch((err) => {
    console.error('❌ Connexion MongoDB échouée :', err.message);
    process.exit(1);
  });
