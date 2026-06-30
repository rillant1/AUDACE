const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const KEYS_DIR = path.join(__dirname, '..', '..', 'keys');
const PRIVATE_KEY_PATH = path.join(KEYS_DIR, 'art_private.pem');
const PUBLIC_KEY_PATH = path.join(KEYS_DIR, 'art_public.pem');

// Génère la paire de clés RSA-2048 de l'ART au premier démarrage du serveur,
// puis la réutilise — la clé privée signe les rapports, la publique vérifie /api/reports/verify.
function ensureKeyPair() {
  if (fs.existsSync(PRIVATE_KEY_PATH) && fs.existsSync(PUBLIC_KEY_PATH)) {
    return;
  }
  fs.mkdirSync(KEYS_DIR, { recursive: true });
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    privateKeyEncoding: { type: 'pkcs1', format: 'pem' },
    publicKeyEncoding: { type: 'pkcs1', format: 'pem' },
  });
  fs.writeFileSync(PRIVATE_KEY_PATH, privateKey);
  fs.writeFileSync(PUBLIC_KEY_PATH, publicKey);
  console.log('[Crypto] Paire de clés RSA-2048 ART générée dans backend/keys/');
}

function sha256Hex(content) {
  return crypto.createHash('sha256').update(content).digest('hex');
}

// Signe le hash SHA-256 du rapport avec la clé privée RSA-2048 de l'ART.
function signHash(hashHex) {
  ensureKeyPair();
  const privateKey = fs.readFileSync(PRIVATE_KEY_PATH, 'utf8');
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(hashHex);
  signer.end();
  return signer.sign(privateKey, 'base64');
}

function verifySignature(hashHex, signatureBase64) {
  ensureKeyPair();
  const publicKey = fs.readFileSync(PUBLIC_KEY_PATH, 'utf8');
  const verifier = crypto.createVerify('RSA-SHA256');
  verifier.update(hashHex);
  verifier.end();
  return verifier.verify(publicKey, signatureBase64, 'base64');
}

module.exports = { ensureKeyPair, sha256Hex, signHash, verifySignature };
