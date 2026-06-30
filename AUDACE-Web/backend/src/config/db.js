const mongoose = require('mongoose');

async function connectDb() {
  const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/audace_art';
  await mongoose.connect(uri);
  console.log(`[MongoDB] Connecté à ${uri}`);
}

module.exports = { connectDb };
