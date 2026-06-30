const express = require('express');
const { requireAuth } = require('../middleware/auth');
const {
  mtnInitiate, mtnStatus, mtnWebhook,
  orangeInitiate, orangeStatus, orangeWebhook,
} = require('../controllers/paymentController');

const router = express.Router();

// ── MTN Mobile Money ───────────────────────────────────────────────────────
router.post('/mtn/initiate', requireAuth, mtnInitiate);
router.get('/mtn/status/:referenceId', requireAuth, mtnStatus);
router.post('/mtn/webhook', mtnWebhook);          // pas d'auth — appelé par MTN

// ── Orange Money ───────────────────────────────────────────────────────────
router.post('/orange/initiate', requireAuth, orangeInitiate);
router.get('/orange/status/:orderId', requireAuth, orangeStatus);
router.post('/orange/webhook', orangeWebhook);    // pas d'auth — appelé par Orange

module.exports = router;
