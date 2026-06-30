// Tests end-to-end de l'API AUDACE
// Vérifient le chemin complet : requête HTTP → MongoDB → réponse JSON

const request  = require('supertest');
const mongoose = require('mongoose');
const app      = require('../src/app');
const Mesure   = require('../src/mesure.model');

const MONGO_TEST_URI = 'mongodb://127.0.0.1:27017/audace_test';

// ─── Mesure type produite par NetworkMetrics.toJson() ────────────────────────
function mesureValide(idSuffix = '001') {
  return {
    device_metric_id: `test-uuid-${idSuffix}`,
    schema_version:   '1.1.0',
    generated_at:     new Date().toISOString(),
    operateur: {
      nom:       'MTN Cameroon',
      mcc:       '624',
      mnc:       '01',
      pays_iso:  'CM',
      en_roaming: false,
    },
    session_active: { type: 'Mobile' },
    connectivite_qos: {
      debit_descendant_mbps: 22.5,
      debit_montant_mbps:    8.1,
      latence_ms:            48.0,
      gigue_ms:              3.2,
      taux_perte_paquets:    0.0,
    },
    experience_utilisateur_qoe: {
      http_success_rate_pct:  95.0,
      web_browsing_time_ms:   1240,
      app_failure_rate_pct:   5.0,
      url_teste:              'https://www.art.cm',
    },
    metadonnees_contexte: {
      h3_index:   '88abc123fff',
      coordonnees: { latitude: 3.848, longitude: 11.502 },
      horodatage_iso:      new Date().toISOString(),
      version_application: '1.0.0',
      identifiant_anonyme: 'sha256-test-hash',
    },
  };
}

// ─── Connexion / nettoyage ────────────────────────────────────────────────────
beforeAll(async () => {
  await mongoose.connect(MONGO_TEST_URI);
});

afterEach(async () => {
  await Mesure.deleteMany({});
});

afterAll(async () => {
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
});

// ─── GET /api/health ─────────────────────────────────────────────────────────
describe('GET /api/health', () => {
  test('retourne ok: true avec un horodatage ISO', async () => {
    const res = await request(app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.heure).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });
});

// ─── POST /api/metrics ───────────────────────────────────────────────────────
describe('POST /api/metrics — mesure unique', () => {
  test('enregistre une mesure valide et retourne 201', async () => {
    const res = await request(app)
      .post('/api/metrics')
      .send(mesureValide('a01'))
      .set('Content-Type', 'application/json');

    expect(res.status).toBe(201);
    expect(res.body.ok).toBe(true);
    expect(res.body.device_metric_id).toBe('test-uuid-a01');
  });

  test('la mesure est bien persistée dans MongoDB', async () => {
    await request(app).post('/api/metrics').send(mesureValide('a02'));

    const doc = await Mesure.findOne({ device_metric_id: 'test-uuid-a02' });
    expect(doc).not.toBeNull();
    expect(doc.operateur.nom).toBe('MTN Cameroon');
    expect(doc.connectivite_qos.debit_descendant_mbps).toBe(22.5);
    expect(doc.connectivite_qos.latence_ms).toBe(48.0);
    expect(doc.experience_utilisateur_qoe.http_success_rate_pct).toBe(95.0);
  });

  test('accepte une mesure sans coordonnées GPS (champ optionnel)', async () => {
    const m = mesureValide('a03');
    m.metadonnees_contexte.coordonnees = null;
    m.metadonnees_contexte.h3_index    = null;

    const res = await request(app).post('/api/metrics').send(m);
    expect(res.status).toBe(201);

    const doc = await Mesure.findOne({ device_metric_id: 'test-uuid-a03' });
    expect(doc).not.toBeNull();
  });

  test('est idempotent — deux envois du même id ne créent pas de doublon', async () => {
    const m = mesureValide('a04');
    await request(app).post('/api/metrics').send(m);
    const res2 = await request(app).post('/api/metrics').send(m);

    expect(res2.status).toBe(201);
    const count = await Mesure.countDocuments({ device_metric_id: 'test-uuid-a04' });
    expect(count).toBe(1);
  });

  test('retourne 400 si device_metric_id est absent', async () => {
    const m = mesureValide('a05');
    delete m.device_metric_id;

    const res = await request(app).post('/api/metrics').send(m);
    expect(res.status).toBe(400);
    expect(res.body.erreur).toMatch(/device_metric_id/);
  });

  test('retourne 400 si le corps est vide', async () => {
    const res = await request(app).post('/api/metrics').send({});
    expect(res.status).toBe(400);
  });

  test('enregistre les métriques de tous les opérateurs camerounais', async () => {
    const operateurs = ['MTN Cameroon', 'Orange Cameroun', 'Camtel', 'Nexttel'];
    for (let i = 0; i < operateurs.length; i++) {
      const m = mesureValide(`op-${i}`);
      m.operateur.nom = operateurs[i];
      await request(app).post('/api/metrics').send(m);
    }

    const count = await Mesure.countDocuments({});
    expect(count).toBe(4);

    const noms = await Mesure.distinct('operateur.nom');
    expect(noms.sort()).toEqual(operateurs.sort());
  });
});

// ─── POST /api/metrics/batch ─────────────────────────────────────────────────
describe('POST /api/metrics/batch — envoi groupé', () => {
  test('insère plusieurs mesures en une requête', async () => {
    const metrics = [mesureValide('b01'), mesureValide('b02'), mesureValide('b03')];
    const res = await request(app)
      .post('/api/metrics/batch')
      .send({ metrics });

    expect(res.status).toBe(201);
    expect(res.body.inserted).toBe(3);

    const count = await Mesure.countDocuments({});
    expect(count).toBe(3);
  });

  test('ne crée pas de doublons dans un batch avec ids répétés', async () => {
    const m = mesureValide('b04');
    const metrics = [m, { ...m }, { ...m }]; // même id 3 fois

    const res = await request(app).post('/api/metrics/batch').send({ metrics });
    expect(res.status).toBe(201);

    const count = await Mesure.countDocuments({ device_metric_id: 'test-uuid-b04' });
    expect(count).toBe(1);
  });

  test('retourne 400 si le tableau metrics est absent', async () => {
    const res = await request(app).post('/api/metrics/batch').send({});
    expect(res.status).toBe(400);
  });

  test('retourne 400 si le tableau metrics est vide', async () => {
    const res = await request(app).post('/api/metrics/batch').send({ metrics: [] });
    expect(res.status).toBe(400);
  });
});

// ─── GET /api/metrics ────────────────────────────────────────────────────────
describe('GET /api/metrics — liste des mesures', () => {
  test('retourne une liste vide si aucune mesure', async () => {
    const res = await request(app).get('/api/metrics');
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(0);
    expect(res.body.mesures).toHaveLength(0);
  });

  test('retourne les mesures insérées avec les champs essentiels', async () => {
    await request(app).post('/api/metrics').send(mesureValide('c01'));
    await request(app).post('/api/metrics').send(mesureValide('c02'));

    const res = await request(app).get('/api/metrics');
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(2);

    const m = res.body.mesures[0];
    expect(m['operateur.nom'] || m.operateur?.nom).toBeTruthy();
  });

  test('respecte le paramètre limit', async () => {
    for (let i = 0; i < 5; i++) {
      await request(app).post('/api/metrics').send(mesureValide(`c0${i + 10}`));
    }

    const res = await request(app).get('/api/metrics?limit=3');
    expect(res.body.mesures).toHaveLength(3);
  });
});

// ─── Route inconnue ───────────────────────────────────────────────────────────
describe('Route inconnue', () => {
  test('retourne 404 pour une route inexistante', async () => {
    const res = await request(app).get('/api/inconnu');
    expect(res.status).toBe(404);
    expect(res.body.erreur).toBeTruthy();
  });
});
