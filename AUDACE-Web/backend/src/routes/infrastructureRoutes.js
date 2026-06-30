const express = require('express');
const { requireAuth } = require('../middleware/auth');
const { getByKind } = require('../controllers/snapshotController');

const router = express.Router();
router.get('/', requireAuth, getByKind('infrastructure'));
module.exports = router;
