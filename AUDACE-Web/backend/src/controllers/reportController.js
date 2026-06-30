const Report = require('../models/Report');
const AuditLog = require('../models/AuditLog');
const { sha256Hex, signHash, verifySignature } = require('../utils/crypto');

async function generate(req, res) {
  const { reportType, period, format } = req.body;
  if (!reportType || !period || !format) {
    return res.status(400).json({ message: 'reportType, period et format requis.' });
  }
  const issuedAt = new Date();
  const content = `${reportType}|${period}|${format}|${issuedAt.toISOString()}`;
  const hash = sha256Hex(content);
  const signature = signHash(hash);

  const report = await Report.create({
    reportType,
    period,
    format,
    hash,
    signature,
    issuedAt,
    issuedBy: req.user.userId,
  });

  await AuditLog.create({
    time: `${String(issuedAt.getHours()).padStart(2, '0')}:${String(issuedAt.getMinutes()).padStart(2, '0')}`,
    user: req.user.userId,
    action: `Export Rapport ${format} (${reportType})`,
  });

  res.status(201).json(report);
}

async function verify(req, res) {
  const { hash, signature } = req.body;
  if (!hash || !signature) {
    return res.status(400).json({ message: 'hash et signature requis.' });
  }
  const valid = verifySignature(hash, signature);
  res.json({ valid });
}

async function list(req, res) {
  const reports = await Report.find().sort({ createdAt: -1 }).limit(50);
  res.json(reports);
}

module.exports = { generate, verify, list };
