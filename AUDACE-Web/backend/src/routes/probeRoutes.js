const express = require('express');
const { requireAuth, requireRole } = require('../middleware/auth');
const { list, enroll, restart } = require('../controllers/probeController');

const router = express.Router();

router.use(requireAuth);
router.get('/', list);
router.post('/', requireRole('SUPER_ADMIN', 'REGULATOR_ART'), enroll);
router.patch('/:id/restart', requireRole('SUPER_ADMIN', 'REGULATOR_ART'), restart);

module.exports = router;
