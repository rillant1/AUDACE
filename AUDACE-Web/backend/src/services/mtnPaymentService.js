/**
 * MTN Mobile Money Collection API — Cameroun (XAF)
 * Documentation: https://momodeveloper.mtn.com/
 * Sandbox:    https://sandbox.momodeveloper.mtn.com
 * Production: configurable via MTN_MOMO_BASE_URL
 */
const axios = require('axios');
const { randomUUID } = require('crypto');

const BASE_URL = process.env.MTN_MOMO_BASE_URL || 'https://sandbox.momodeveloper.mtn.com';
const SUBSCRIPTION_KEY = process.env.MTN_MOMO_SUBSCRIPTION_KEY || '';
const API_USER = process.env.MTN_MOMO_API_USER || '';
const API_KEY  = process.env.MTN_MOMO_API_KEY  || '';
const ENVIRONMENT = process.env.MTN_MOMO_ENVIRONMENT || 'sandbox';

// --- Token OAuth2 (Basic Auth) -------------------------------------------
async function getAccessToken() {
  if (!API_USER || !API_KEY) {
    throw new Error('MTN_MOMO_API_USER et MTN_MOMO_API_KEY sont requis dans .env');
  }
  const credentials = Buffer.from(`${API_USER}:${API_KEY}`).toString('base64');
  const { data } = await axios.post(
    `${BASE_URL}/collection/token/`,
    {},
    {
      headers: {
        Authorization: `Basic ${credentials}`,
        'Ocp-Apim-Subscription-Key': SUBSCRIPTION_KEY,
      },
      timeout: 15000,
    }
  );
  return data.access_token;
}

// --- Initier une collecte (demande de paiement au client) -----------------
async function requestToPay({ amount, phoneNumber, externalId, description }) {
  const token = await getAccessToken();
  const referenceId = randomUUID();

  await axios.post(
    `${BASE_URL}/collection/v1_0/requesttopay`,
    {
      amount: String(Math.round(amount)),
      currency: 'XAF',
      externalId: externalId || randomUUID(),
      payer: {
        partyIdType: 'MSISDN',
        partyId: phoneNumber.replace(/\s+/g, ''),
      },
      payerMessage: description || 'Paiement AUDACE ART',
      payeeNote: `AUDACE-ART-${Date.now()}`,
    },
    {
      headers: {
        Authorization: `Bearer ${token}`,
        'X-Reference-Id': referenceId,
        'X-Target-Environment': ENVIRONMENT,
        'Ocp-Apim-Subscription-Key': SUBSCRIPTION_KEY,
        'Content-Type': 'application/json',
      },
      timeout: 30000,
    }
  );

  return referenceId;
}

// --- Vérifier le statut d'un paiement ------------------------------------
async function getPaymentStatus(referenceId) {
  const token = await getAccessToken();
  const { data } = await axios.get(
    `${BASE_URL}/collection/v1_0/requesttopay/${referenceId}`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
        'X-Target-Environment': ENVIRONMENT,
        'Ocp-Apim-Subscription-Key': SUBSCRIPTION_KEY,
      },
      timeout: 15000,
    }
  );
  // status: PENDING | SUCCESSFUL | FAILED
  return data;
}

module.exports = { requestToPay, getPaymentStatus };
