const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  userId: { type: String, required: true, unique: true },
  username: { type: String, required: true, unique: true },
  email: { type: String, required: true },
  passwordHash: { type: String, required: true },
  role: {
    type: String,
    enum: ['SUPER_ADMIN', 'REGULATOR_ART', 'OPERATOR_TECH'],
    required: true,
  },
}, { timestamps: true });

module.exports = mongoose.model('User', userSchema);
