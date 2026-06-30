const { randomUUID } = require('crypto');
const mtnService    = require('../services/mtnPaymentService');
const orangeService = require('../services/orangePaymentService');
const Subscription  = require('../models/Subscription');
const Invoice       = require('../models/Invoice');

// ── MTN Mobile Money ───────────────────────────────────────────────────────

async function mtnInitiate(req, res) {
  const { amount, phoneNumber, description } = req.body;
  if (!amount || !phoneNumber) {
    return res.status(400).json({ message: 'amount et phoneNumber sont requis.' });
  }
  try {
    const referenceId = await mtnService.requestToPay({
      amount,
      phoneNumber,
      externalId: randomUUID(),
      description: description || `Abonnement AUDACE ART`,
    });
    res.json({ referenceId, status: 'PENDING', provider: 'MTN_MOMO' });
  } catch (err) {
    console.error('[MTN MoMo] Erreur initiation:', err.message);
    res.status(502).json({ message: `Erreur MTN MoMo : ${err.message}` });
  }
}

async function mtnStatus(req, res) {
  const { referenceId } = req.params;
  if (!referenceId) return res.status(400).json({ message: 'referenceId requis.' });
  try {
    const data = await mtnService.getPaymentStatus(referenceId);
    // Si le paiement est confirmé, on met à jour l'abonnement
    if (data.status === 'SUCCESSFUL') {
      await _recordPayment('MTN Mobile Money', data.amount, data.externalId);
    }
    res.json(data);
  } catch (err) {
    console.error('[MTN MoMo] Erreur statut:', err.message);
    res.status(502).json({ message: `Erreur MTN MoMo : ${err.message}` });
  }
}

// Webhook MTN (callback de confirmation asynchrone)
async function mtnWebhook(req, res) {
  const payload = req.body;
  console.log('[MTN MoMo Webhook]', JSON.stringify(payload));
  if (payload.status === 'SUCCESSFUL') {
    await _recordPayment('MTN Mobile Money', payload.amount, payload.externalId).catch(console.error);
  }
  res.sendStatus(200);
}

// ── Orange Money ───────────────────────────────────────────────────────────

async function orangeInitiate(req, res) {
  const { amount, orderId, description } = req.body;
  if (!amount) return res.status(400).json({ message: 'amount est requis.' });
  try {
    const result = await orangeService.initiatePayment({ amount, orderId, description });
    res.json({ ...result, status: 'PENDING', provider: 'ORANGE_MONEY' });
  } catch (err) {
    console.error('[Orange Money] Erreur initiation:', err.message);
    res.status(502).json({ message: `Erreur Orange Money : ${err.message}` });
  }
}

async function orangeStatus(req, res) {
  const { orderId } = req.params;
  if (!orderId) return res.status(400).json({ message: 'orderId requis.' });
  try {
    const data = await orangeService.getTransactionStatus(orderId);
    if (data.status === 'SUCCESS') {
      await _recordPayment('Orange Money', data.amount, orderId);
    }
    res.json(data);
  } catch (err) {
    console.error('[Orange Money] Erreur statut:', err.message);
    res.status(502).json({ message: `Erreur Orange Money : ${err.message}` });
  }
}

// Webhook Orange Money (notification de paiement)
async function orangeWebhook(req, res) {
  const payload = req.body;
  console.log('[Orange Money Webhook]', JSON.stringify(payload));
  if (payload.status === 'SUCCESS') {
    await _recordPayment('Orange Money', payload.amount, payload.order_id).catch(console.error);
  }
  res.sendStatus(200);
}

// ── Helpers internes ───────────────────────────────────────────────────────

async function _recordPayment(methodLabel, amount, externalRef) {
  const invoiceNumber = `FAC-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`;
  await Invoice.create({
    number: invoiceNumber,
    date: new Date(),
    amountFcfa: Number(amount) || 5000000,
    status: 'Payé',
  });
  let sub = await Subscription.findOne();
  if (!sub) sub = new Subscription();
  sub.lastPaymentAction = `Paiement ${methodLabel} confirmé`;
  sub.lastPaymentMethod = methodLabel;
  await sub.save();
  console.log(`[Paiement] ${methodLabel} enregistré — réf. ${externalRef}`);
}

module.exports = { mtnInitiate, mtnStatus, mtnWebhook, orangeInitiate, orangeStatus, orangeWebhook };
