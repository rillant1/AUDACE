/**
 * Orange Money Webpay API — Cameroun (XAF)
 * Documentation: https://developer.orange.com/apis/orange-money-webpay-cm
 * Sandbox:    configurable via ORANGE_API_BASE
 */
const axios = require('axios');
const { randomUUID } = require('crypto');

const API_BASE       = process.env.ORANGE_API_BASE       || 'https://api.orange.com';
const CLIENT_ID      = process.env.ORANGE_CLIENT_ID      || '';
const CLIENT_SECRET  = process.env.ORANGE_CLIENT_SECRET  || '';
const MERCHANT_KEY   = process.env.ORANGE_MERCHANT_KEY   || '';
const NOTIF_URL      = process.env.ORANGE_NOTIF_URL      || 'https://your-server.cm/api/payments/orange/webhook';
const RETURN_URL     = process.env.ORANGE_RETURN_URL     || 'https://your-server.cm/paiement/succes';
const CANCEL_URL     = process.env.ORANGE_CANCEL_URL     || 'https://your-server.cm/paiement/annule';

// Cache token en mémoire (durée de vie 3600 s en général)
let _cachedToken = null;
let _tokenExpiry = 0;

// --- Token OAuth2 (Client Credentials) ------------------------------------
async function getAccessToken() {
  if (_cachedToken && Date.now() < _tokenExpiry) return _cachedToken;

  if (!CLIENT_ID || !CLIENT_SECRET) {
    throw new Error('ORANGE_CLIENT_ID et ORANGE_CLIENT_SECRET sont requis dans .env');
  }

  const credentials = Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString('base64');
  const { data } = await axios.post(
    `${API_BASE}/oauth/v3/token`,
    'grant_type=client_credentials',
    {
      headers: {
        Authorization: `Basic ${credentials}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json',
      },
      timeout: 15000,
    }
  );

  _cachedToken = data.access_token;
  _tokenExpiry = Date.now() + (data.expires_in - 60) * 1000;
  return _cachedToken;
}

// --- Initier un paiement Orange Money ------------------------------------
async function initiatePayment({ amount, orderId, description }) {
  const token = await getAccessToken();
  const ref = orderId || `ART-${randomUUID().split('-')[0].toUpperCase()}`;

  const { data } = await axios.post(
    `${API_BASE}/orange-money-webpay/cm/v1/webpayment`,
    {
      merchant_key: MERCHANT_KEY,
      currency: 'OUV',
      order_id: ref,
      amount: Math.round(amount),
      return_url: RETURN_URL,
      cancel_url: CANCEL_URL,
      notif_url: NOTIF_URL,
      lang: 'fr',
      reference: description || 'Paiement AUDACE ART',
    },
    {
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      timeout: 30000,
    }
  );

  // data.payment_url : URL de redirection vers la page Orange Money
  return { paymentUrl: data.payment_url, orderId: ref, rawData: data };
}

// --- Vérifier le statut d'une transaction --------------------------------
async function getTransactionStatus(orderId) {
  const token = await getAccessToken();
  const { data } = await axios.get(
    `${API_BASE}/orange-money-webpay/cm/v1/transactionstatus`,
    {
      params: { order_id: orderId },
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
      timeout: 15000,
    }
  );
  return data;
}

module.exports = { initiatePayment, getTransactionStatus };
