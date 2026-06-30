const express = require('express');
const { requireAuth, requireRole } = require('../middleware/auth');
const { generate, verify, list } = require('../controllers/reportController');

const router = express.Router();

router.use(requireAuth);
router.get('/', list);
router.post('/generate', requireRole('SUPER_ADMIN', 'REGULATOR_ART'), generate);
router.post('/verify', verify);

module.exports = router;
