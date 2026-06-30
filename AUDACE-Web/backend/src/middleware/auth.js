const { verifyToken } = require('../utils/jwt');

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ message: 'Authentification requise.' });
  }
  try {
    const payload = verifyToken(token);
    req.user = { userId: payload.sub, role: payload.role };
    next();
  } catch (err) {
    return res.status(401).json({ message: 'Jeton invalide ou expiré.' });
  }
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ message: 'Permission refusée pour ce rôle.' });
    }
    next();
  };
}

module.exports = { requireAuth, requireRole };
