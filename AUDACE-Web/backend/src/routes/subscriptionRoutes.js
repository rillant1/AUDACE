const express = require('express');
const { requireAuth, requireRole } = require('../middleware/auth');
const {
  getSubscription, changePlan, pay, listInvoices,
} = require('../controllers/subscriptionController');

const router = express.Router();

router.use(requireAuth);
router.get('/', requireRole('SUPER_ADMIN', 'REGULATOR_ART'), getSubscription);
router.patch('/plan', requireRole('SUPER_ADMIN', 'REGULATOR_ART'), changePlan);
router.post('/pay', requireRole('SUPER_ADMIN', 'REGULATOR_ART'), pay);
router.get('/invoices', requireRole('SUPER_ADMIN', 'REGULATOR_ART'), listInvoices);

module.exports = router;
