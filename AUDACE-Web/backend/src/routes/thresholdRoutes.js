const express = require('express');
const { requireAuth, requireRole } = require('../middleware/auth');
const { list, update } = require('../controllers/thresholdController');

const router = express.Router();

router.use(requireAuth);
router.get('/', list);
router.patch('/', requireRole('SUPER_ADMIN', 'REGULATOR_ART'), update);

module.exports = router;
