const express = require('express');
const { requireAuth } = require('../middleware/auth');
const AuditLog = require('../models/AuditLog');

const router = express.Router();

router.get('/', requireAuth, async (req, res) => {
  const logs = await AuditLog.find().sort({ createdAt: -1 }).limit(20);
  res.json(logs);
});

module.exports = router;
