const bcrypt = require('bcryptjs');
const User = require('../models/User');
const { signToken } = require('../utils/jwt');

const EXPIRES_IN_MS = 8 * 60 * 60 * 1000;

async function login(req, res) {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ message: 'Nom d\'utilisateur et mot de passe requis.' });
  }

  const user = await User.findOne({ username });
  if (!user) {
    return res.status(401).json({
      message: 'Identifiants incorrects. Vérifiez votre nom d\'utilisateur et votre mot de passe.',
    });
  }

  const valid = await bcrypt.compare(password, user.passwordHash);
  if (!valid) {
    return res.status(401).json({
      message: 'Identifiants incorrects. Vérifiez votre nom d\'utilisateur et votre mot de passe.',
    });
  }

  const token = signToken(user);
  const issuedAt = new Date();
  const expiresAt = new Date(issuedAt.getTime() + EXPIRES_IN_MS);

  return res.json({
    userId: user.userId,
    username: user.username,
    email: user.email,
    role: user.role,
    jwtToken: token,
    issuedAt: issuedAt.toISOString(),
    expiresAt: expiresAt.toISOString(),
  });
}

async function me(req, res) {
  const user = await User.findOne({ userId: req.user.userId });
  if (!user) {
    return res.status(404).json({ message: 'Utilisateur introuvable.' });
  }
  return res.json({
    userId: user.userId,
    username: user.username,
    email: user.email,
    role: user.role,
  });
}

module.exports = { login, me };
