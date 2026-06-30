const Subscription = require('../models/Subscription');
const Invoice = require('../models/Invoice');

async function getSubscription(req, res) {
  let sub = await Subscription.findOne();
  if (!sub) sub = await Subscription.create({});
  res.json(sub);
}

async function changePlan(req, res) {
  const { plan } = req.body;
  if (!plan) return res.status(400).json({ message: 'Formule requise.' });
  let sub = await Subscription.findOne();
  if (!sub) sub = new Subscription();
  sub.plan = plan;
  await sub.save();
  res.json(sub);
}

async function pay(req, res) {
  const { methodLabel } = req.body;
  let sub = await Subscription.findOne();
  if (!sub) sub = new Subscription();
  sub.lastPaymentAction = `Paiement ${methodLabel || ''} confirmé`.trim();
  sub.lastPaymentMethod = methodLabel || null;
  await sub.save();
  res.json(sub);
}

async function listInvoices(req, res) {
  const invoices = await Invoice.find().sort({ date: -1 });
  res.json(invoices);
}

module.exports = { getSubscription, changePlan, pay, listInvoices };
