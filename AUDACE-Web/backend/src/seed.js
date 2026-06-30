require('dotenv').config();
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');

const { connectDb } = require('./config/db');
const User = require('./models/User');
const SupportTicket = require('./models/SupportTicket');
const Incident = require('./models/Incident');
const Probe = require('./models/Probe');
const Subscription = require('./models/Subscription');
const Invoice = require('./models/Invoice');
const Threshold = require('./models/Threshold');
const OperatorStat = require('./models/OperatorStat');
const Snapshot = require('./models/Snapshot');
const AuditLog = require('./models/AuditLog');

const ASSETS_DIR = path.join(__dirname, '..', '..', 'assets');

function readJsonAsset(filename) {
  const raw = fs.readFileSync(path.join(ASSETS_DIR, filename), 'utf8');
  return JSON.parse(raw);
}

// Génère les N derniers jours comme "JJ/MM"
function lastNDays(n) {
  const result = [];
  const now = new Date();
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(now);
    d.setDate(d.getDate() - i);
    result.push(`${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`);
  }
  return result;
}

async function seed() {
  await connectDb();
  const now = Date.now();

  // ── Utilisateurs ──────────────────────────────────────────────────────────
  const users = [
    { username: 'admin.art', password: 'ART@2025', email: 'admin@art.cm', role: 'SUPER_ADMIN', userId: 'usr-001' },
    { username: 'regulateur', password: 'REG@2025', email: 'reg@art.cm', role: 'REGULATOR_ART', userId: 'usr-002' },
    { username: 'tech.ops', password: 'TECH@2025', email: 'tech@art.cm', role: 'OPERATOR_TECH', userId: 'usr-003' },
  ];
  for (const u of users) {
    const passwordHash = await bcrypt.hash(u.password, 10);
    await User.findOneAndUpdate(
      { username: u.username },
      { userId: u.userId, username: u.username, email: u.email, passwordHash, role: u.role },
      { upsert: true }
    );
  }
  console.log(`[Seed] ${users.length} utilisateurs créés/à jour.`);

  // ── Tickets de support ────────────────────────────────────────────────────
  await SupportTicket.deleteMany({});
  await SupportTicket.insertMany([
    {
      id: 'TKT-2025-014',
      title: 'Données H3 non rechargées après filtre opérateur',
      description: 'Lors du filtrage par opérateur MTN sur la vue cartographique, les hexagones H3 ne se rechargent pas automatiquement.',
      author: 'sophie.ndo',
      category: 'Bug Cartographie',
      priority: 'haute',
      status: 'enCours',
      createdAt: new Date('2025-04-28T09:30:00'),
      updatedAt: new Date('2025-04-29T14:00:00'),
      slaDeadline: new Date(now + 2 * 86400_000),
      comments: ['Reproductible sur Chrome 124. Piste: WebSocket ferme la connexion.'],
    },
    {
      id: 'TKT-2025-013',
      title: "Export PDF rapport QoS — signature absente",
      description: "Le rapport PDF généré pour la période avril 2025 ne contient pas l'empreinte SHA-256 en bas de page.",
      author: 'admin.art',
      category: 'Rapports & Certification',
      priority: 'critique',
      status: 'ouvert',
      createdAt: new Date('2025-04-30T11:00:00'),
      updatedAt: new Date('2025-04-30T11:00:00'),
      slaDeadline: new Date(now + 1 * 86400_000),
      comments: [],
    },
    {
      id: 'TKT-2025-010',
      title: 'Webhook MoMo MTN en timeout lors du renouvellement',
      description: "Le webhook de confirmation de paiement MTN Mobile Money ne répond pas dans le délai SLA de 30 secondes.",
      author: 'regulateur',
      category: 'Facturation & Paiement',
      priority: 'haute',
      status: 'resolu',
      createdAt: new Date('2025-04-20T08:15:00'),
      updatedAt: new Date('2025-04-26T17:30:00'),
      slaDeadline: new Date(now - 5 * 86400_000),
      comments: ['Solution: timeout étendu à 60s côté Node.js. Déployé en prod.'],
    },
    {
      id: 'TKT-2025-007',
      title: "Demande d'accès données RSRQ région Adamaoua",
      description: "L'opérateur Camtel demande un accès en lecture seule aux données RSRQ de la région Adamaoua.",
      author: 'tech.ops',
      category: 'Accès & Permissions',
      priority: 'normale',
      status: 'clos',
      createdAt: new Date('2025-04-10T10:00:00'),
      updatedAt: new Date('2025-04-15T16:00:00'),
      slaDeadline: null,
      comments: ['Accès accordé via rôle OPERATOR_TECH. Ticket fermé.'],
    },
  ]);
  console.log('[Seed] 4 tickets de support créés.');

  // ── Incidents ─────────────────────────────────────────────────────────────
  await Incident.deleteMany({});
  await Incident.insertMany([
    { id: 'INC-2025-041', title: 'Dégradation latence 4G', zone: 'Douala V', operatorName: 'Orange', severity: 'Critique', status: 'Ouvert', openedAt: new Date(now - 2 * 3600_000) },
    { id: 'INC-2025-038', title: 'Perte paquets sur backhaul', zone: 'Yaoundé VI', operatorName: 'MTN', severity: 'Majeur', status: 'Ouvert', openedAt: new Date(now - 4 * 3600_000) },
    { id: 'INC-2025-032', title: 'Site radio indisponible', zone: 'Bafoussam', operatorName: 'Camtel', severity: 'Mineur', status: 'Clos', openedAt: new Date(now - 27 * 3600_000) },
  ]);
  console.log('[Seed] 3 incidents créés.');

  // ── Sondes ────────────────────────────────────────────────────────────────
  await Probe.deleteMany({});
  await Probe.insertMany([
    // Centre
    { id: 'NP-CE-0441', region: 'Centre',       city: 'Yaoundé',      lat: 3.848,  lng: 11.502, status: 'En ligne',   battery: 87, lastSync: new Date(now -  3 * 60_000) },
    { id: 'NP-CE-0512', region: 'Centre',       city: 'Yaoundé',      lat: 3.866,  lng: 11.517, status: 'En ligne',   battery: 72, lastSync: new Date(now -  8 * 60_000) },
    { id: 'NP-CE-0603', region: 'Centre',       city: 'Mbalmayo',     lat: 3.516,  lng: 11.503, status: 'En ligne',   battery: 61, lastSync: new Date(now - 12 * 60_000) },
    // Littoral
    { id: 'NP-LT-1024', region: 'Littoral',     city: 'Douala',       lat: 4.061,  lng:  9.703, status: 'En ligne',   battery: 84, lastSync: new Date(now -  2 * 60_000) },
    { id: 'NP-LT-1105', region: 'Littoral',     city: 'Douala',       lat: 4.049,  lng:  9.731, status: 'En ligne',   battery: 91, lastSync: new Date(now -  1 * 60_000) },
    { id: 'NP-LT-1210', region: 'Littoral',     city: 'Nkongsamba',   lat: 4.952,  lng:  9.934, status: 'Hors ligne', battery:  5, lastSync: new Date(now - 90 * 60_000) },
    // Ouest
    { id: 'NP-OU-0188', region: 'Ouest',        city: 'Bafoussam',    lat: 5.476,  lng: 10.417, status: 'Hors ligne', battery: 12, lastSync: new Date(now - 60 * 60_000) },
    { id: 'NP-OU-0294', region: 'Ouest',        city: 'Dschang',      lat: 5.449,  lng: 10.053, status: 'En ligne',   battery: 55, lastSync: new Date(now - 18 * 60_000) },
    // Nord-Ouest
    { id: 'NP-NO-0371', region: 'Nord-Ouest',   city: 'Bamenda',      lat: 5.961,  lng: 10.153, status: 'En ligne',   battery: 78, lastSync: new Date(now -  7 * 60_000) },
    { id: 'NP-NO-0412', region: 'Nord-Ouest',   city: 'Kumbo',        lat: 6.200,  lng: 10.683, status: 'Hors ligne', battery:  3, lastSync: new Date(now - 120 * 60_000) },
    // Sud-Ouest
    { id: 'NP-SO-0533', region: 'Sud-Ouest',    city: 'Buea',         lat: 4.154,  lng:  9.241, status: 'En ligne',   battery: 66, lastSync: new Date(now - 14 * 60_000) },
    { id: 'NP-SO-0614', region: 'Sud-Ouest',    city: 'Limbé',        lat: 4.016,  lng:  9.197, status: 'En ligne',   battery: 43, lastSync: new Date(now - 22 * 60_000) },
    // Adamaoua
    { id: 'NP-AD-0729', region: 'Adamaoua',     city: 'Ngaoundéré',   lat: 7.326,  lng: 13.584, status: 'En ligne',   battery: 59, lastSync: new Date(now - 11 * 60_000) },
    { id: 'NP-AD-0815', region: 'Adamaoua',     city: 'Meiganga',     lat: 6.519,  lng: 14.305, status: 'Hors ligne', battery: 18, lastSync: new Date(now - 75 * 60_000) },
    // Nord
    { id: 'NP-NO-0931', region: 'Nord',         city: 'Garoua',       lat: 9.299,  lng: 13.396, status: 'En ligne',   battery: 74, lastSync: new Date(now -  6 * 60_000) },
    { id: 'NP-NO-1044', region: 'Nord',         city: 'Ngong',        lat: 8.692,  lng: 13.553, status: 'En ligne',   battery: 88, lastSync: new Date(now -  4 * 60_000) },
    // Extrême-Nord
    { id: 'NP-EN-1156', region: 'Extrême-Nord', city: 'Maroua',       lat: 10.591, lng: 14.316, status: 'En ligne',   battery: 49, lastSync: new Date(now - 28 * 60_000) },
    { id: 'NP-EN-1247', region: 'Extrême-Nord', city: 'Kousseri',     lat: 12.076, lng: 15.030, status: 'Hors ligne', battery:  7, lastSync: new Date(now - 180 * 60_000) },
    // Est
    { id: 'NP-ES-1362', region: 'Est',          city: 'Bertoua',      lat: 4.578,  lng: 13.683, status: 'En ligne',   battery: 82, lastSync: new Date(now -  9 * 60_000) },
    // Sud
    { id: 'NP-SU-1478', region: 'Sud',          city: 'Ebolowa',      lat: 2.902,  lng: 11.152, status: 'En ligne',   battery: 70, lastSync: new Date(now - 16 * 60_000) },
  ]);
  console.log('[Seed] 20 sondes créées (10 régions, coordonnées GPS réelles).');

  // ── Abonnement & Factures ─────────────────────────────────────────────────
  await Subscription.deleteMany({});
  await Subscription.create({});
  await Invoice.deleteMany({});
  await Invoice.insertMany([
    { number: 'FAC-2025-001', date: new Date('2025-03-01T00:00:00Z'), amountFcfa: 5000000, status: 'Payé' },
    { number: 'FAC-2024-123', date: new Date('2024-03-01T00:00:00Z'), amountFcfa: 5000000, status: 'Payé' },
    { number: 'FAC-2023-105', date: new Date('2023-03-01T00:00:00Z'), amountFcfa: 4500000, status: 'Payé' },
  ]);
  console.log('[Seed] Abonnement et 3 factures créés.');

  // ── Seuils réglementaires ART ─────────────────────────────────────────────
  await Threshold.deleteMany({});
  await Threshold.insertMany([
    { metric: 'Débit Download', thresholdLabel: '> 15 Mbps', status: 'CONFORME' },
    { metric: 'Latence', thresholdLabel: '< 50 ms', status: 'CONFORME' },
    { metric: 'Taux Échec', thresholdLabel: '< 2%', status: 'ALERTE' },
  ]);
  console.log('[Seed] 3 seuils réglementaires créés.');

  // ── Logs d'audit ──────────────────────────────────────────────────────────
  await AuditLog.deleteMany({});
  await AuditLog.insertMany([
    { user: 'admin.art', action: 'Export Rapport QoS', createdAt: new Date(now - 80 * 60_000) },
    { user: 'sophie.ndo', action: 'Mise à jour Seuil Latence', createdAt: new Date(now - 122 * 60_000) },
    { user: 'system', action: 'Nettoyage cache système', createdAt: new Date(now - 158 * 60_000) },
    { user: 'admin.art', action: 'Connexion établie', createdAt: new Date(now - 205 * 60_000) },
  ]);
  console.log('[Seed] 4 logs d\'audit créés.');

  // ── Statistiques opérateurs (QoE) ─────────────────────────────────────────
  await OperatorStat.deleteMany({});
  await OperatorStat.insertMany([
    { _id: 'MTN',     avg_http_success: 97.1, avg_web_time: 2120, avg_app_failure: 2.2, avg_latence: 51, avg_debit: 21.45, total_tests: 1428300 },
    { _id: 'Orange',  avg_http_success: 96.5, avg_web_time: 2630, avg_app_failure: 3.1, avg_latence: 63, avg_debit: 24.73, total_tests: 1417468 },
    { _id: 'Nexttel', avg_http_success: 91.3, avg_web_time: 3450, avg_app_failure: 5.4, avg_latence: 78, avg_debit: 14.32, total_tests: 612900  },
    { _id: 'Camtel',  avg_http_success: 93.8, avg_web_time: 2980, avg_app_failure: 4.1, avg_latence: 70, avg_debit: 17.90, total_tests: 540200  },
  ]);
  console.log('[Seed] 4 statistiques opérateur (QoE) créées.');

  // ── Snapshots NoSQL ───────────────────────────────────────────────────────
  const overviewData      = readJsonAsset('vue_panoramique_data.json');
  const infrastructureData = readJsonAsset('cartographie_infrastructure_data.json');

  const days = lastNDays(30);

  // Séries temporelles QoS nationales (30 jours)
  // Valeurs déterministes basées sur des profils réseau réalistes Cameroun
  const dlSeries = [22.1,22.8,21.5,23.2,24.1,23.7,22.4,21.8,20.9,22.3,
                    23.5,24.2,25.1,24.6,23.9,22.7,21.3,22.0,23.4,24.8,
                    25.3,24.7,23.6,22.9,21.7,22.5,23.8,24.4,25.0,24.2];
  const ulSeries = [8.8, 9.1, 8.5, 9.3, 9.7, 9.5, 8.9, 8.6, 8.2, 8.7,
                    9.2, 9.6,10.1, 9.9, 9.6, 9.1, 8.4, 8.8, 9.3, 9.8,
                   10.2, 9.9, 9.5, 9.2, 8.6, 9.0, 9.5, 9.8,10.0, 9.7];
  const plSeries = [1.2, 1.4, 1.8, 1.3, 1.1, 1.0, 1.5, 2.1, 2.8, 2.2,
                    1.7, 1.4, 1.2, 1.1, 1.3, 1.6, 2.0, 1.9, 1.5, 1.2,
                    1.0, 1.1, 1.3, 1.5, 1.8, 1.6, 1.4, 1.2, 1.1, 1.0];
  const ltSeries = [42, 40, 45, 38, 36, 34, 39, 44, 51, 47,
                    43, 40, 37, 35, 38, 41, 46, 44, 40, 37,
                    34, 35, 37, 40, 43, 41, 38, 36, 34, 35];

  const qosData = {
    kpis: {
      debit_dl_mbps:    parseFloat((dlSeries.reduce((s,v)=>s+v,0)/dlSeries.length).toFixed(2)),
      debit_ul_mbps:    parseFloat((ulSeries.reduce((s,v)=>s+v,0)/ulSeries.length).toFixed(2)),
      latence_ms:       Math.round(ltSeries.reduce((s,v)=>s+v,0)/ltSeries.length),
      perte_paquets_pct:parseFloat((plSeries.reduce((s,v)=>s+v,0)/plSeries.length).toFixed(2)),
      index_qos: 82.6,
    },
    throughput: days.map((date, i) => ({
      date,
      download: dlSeries[i],
      upload:   ulSeries[i],
    })),
    packet_loss: days.map((date, i) => ({
      date,
      value: plSeries[i],
    })),
    latency_by_hour: Array.from({ length: 24 }, (_, h) => {
      const base = 35 + Math.round(Math.sin(h * Math.PI / 12) * 15);
      return {
        label: `${String(h).padStart(2,'0')}h`,
        p10: base - 8,
        p25: base - 3,
        p50: base + 2,
        p75: base + 10,
        p90: base + 22,
      };
    }),
    voip_quality: [
      { label: 'Douala',     jitter: 4.2, mos: 4.1 },
      { label: 'Yaoundé',    jitter: 5.1, mos: 3.9 },
      { label: 'Bafoussam',  jitter: 7.3, mos: 3.5 },
      { label: 'Garoua',     jitter: 9.8, mos: 3.1 },
      { label: 'Maroua',     jitter: 12.4, mos: 2.7 },
      { label: 'Bamenda',    jitter: 6.7, mos: 3.6 },
      { label: 'Ngaoundéré', jitter: 8.9, mos: 3.2 },
      { label: 'Bertoua',    jitter: 11.2, mos: 2.9 },
    ],
  };

  // Séries temporelles QoE par opérateur (30 jours)
  const opProfiles = {
    MTN: {
      debit:   [20.8,21.2,20.5,22.1,22.9,22.4,21.3,20.8,20.1,21.5,
                22.3,23.0,23.8,23.4,22.7,21.6,20.4,21.0,22.2,23.5,
                24.0,23.5,22.6,21.9,20.8,21.4,22.6,23.2,23.8,23.1],
      latence: [54,52,56,49,47,45,51,57,64,59,55,51,48,46,50,53,59,57,52,48,
                45,46,48,52,55,53,50,47,45,46],
      success: [97.2,97.0,96.8,97.3,97.5,97.6,97.1,96.9,96.5,96.8,
                97.0,97.2,97.4,97.5,97.3,97.1,96.7,96.9,97.2,97.5,
                97.7,97.5,97.3,97.1,96.8,97.0,97.3,97.5,97.6,97.4],
      failure: [2.4,2.6,2.9,2.3,2.1,2.0,2.5,2.8,3.2,2.9,2.6,2.4,2.1,1.9,2.2,2.5,2.9,2.8,2.4,2.1,
                1.9,2.0,2.2,2.5,2.8,2.6,2.3,2.1,2.0,2.1],
    },
    Orange: {
      debit:   [24.1,24.5,23.8,25.2,26.0,25.5,24.4,23.9,23.1,24.4,
                25.5,26.2,27.0,26.5,25.8,24.7,23.5,24.1,25.4,26.7,
                27.2,26.7,25.7,25.0,23.9,24.5,25.7,26.4,27.0,26.2],
      latence: [66,64,68,61,59,57,63,70,77,72,68,64,60,58,62,65,71,69,64,60,
                57,58,60,64,67,65,62,59,57,58],
      success: [96.6,96.4,96.1,96.8,97.0,97.1,96.6,96.4,96.0,96.3,
                96.5,96.7,96.9,97.0,96.8,96.5,96.2,96.4,96.7,97.0,
                97.2,97.0,96.8,96.6,96.2,96.5,96.8,97.0,97.1,96.9],
      failure: [3.2,3.4,3.7,3.0,2.8,2.7,3.2,3.6,4.1,3.7,3.3,3.1,2.7,2.5,2.9,3.2,3.7,3.5,3.1,2.7,
                2.5,2.6,2.8,3.1,3.4,3.2,2.9,2.7,2.5,2.7],
    },
    Nexttel: {
      debit:   [14.0,14.3,13.8,14.8,15.4,15.0,14.2,13.8,13.2,14.0,
                14.8,15.4,16.0,15.6,15.0,14.2,13.4,13.9,14.7,15.5,
                15.9,15.5,14.9,14.3,13.6,14.1,14.9,15.4,15.8,15.3],
      latence: [81,79,83,76,73,71,77,84,91,87,83,79,75,72,76,80,86,84,79,75,
                71,72,75,79,82,80,77,73,71,72],
      success: [91.5,91.2,90.9,91.7,92.0,92.1,91.4,91.1,90.7,91.0,
                91.3,91.6,91.9,92.0,91.7,91.4,91.0,91.2,91.5,91.9,
                92.1,91.9,91.6,91.4,90.9,91.2,91.5,91.8,92.0,91.8],
      failure: [5.6,5.9,6.2,5.4,5.1,5.0,5.5,6.0,6.6,6.2,5.8,5.5,5.1,4.9,5.3,5.6,6.1,5.9,5.5,5.1,
                4.9,5.0,5.2,5.5,5.8,5.6,5.3,5.0,4.9,5.0],
    },
    Camtel: {
      debit:   [17.5,17.8,17.2,18.3,19.0,18.6,17.7,17.2,16.6,17.5,
                18.3,19.0,19.7,19.2,18.5,17.6,16.7,17.3,18.2,19.2,
                19.6,19.1,18.4,17.8,16.9,17.5,18.4,19.0,19.5,18.8],
      latence: [73,71,75,68,65,63,69,76,83,79,75,71,67,64,68,72,78,76,71,67,
                63,64,67,71,74,72,69,65,63,64],
      success: [93.9,93.7,93.4,94.1,94.4,94.5,93.9,93.6,93.2,93.5,
                93.8,94.0,94.3,94.5,94.2,93.9,93.5,93.7,94.0,94.4,
                94.6,94.4,94.1,93.9,93.4,93.7,94.0,94.3,94.5,94.3],
      failure: [4.3,4.5,4.9,4.1,3.8,3.7,4.2,4.7,5.3,4.9,4.5,4.2,3.8,3.6,4.0,4.3,4.8,4.6,4.2,3.8,
                3.6,3.7,3.9,4.2,4.5,4.3,4.0,3.7,3.6,3.7],
    },
  };

  const qoeTimeseriesData = {
    days,
    operators: Object.entries(opProfiles).map(([id, p]) => ({
      id,
      series: days.map((date, i) => ({
        date,
        avg_debit:        p.debit[i],
        avg_latence:      p.latence[i],
        avg_http_success: p.success[i],
        avg_app_failure:  p.failure[i],
      })),
    })),
  };

  const benchmarkData = {
    national_ranking: [
      { rang: 1, indicateur: 'Débit Download (Mbps)', poids_pct: 20, orange: 24.73, mtn: 21.45, nexttel: 14.32, camtel: 17.9 },
      { rang: 2, indicateur: 'Débit Upload (Mbps)',   poids_pct: 10, orange: 9.38,  mtn: 8.76,  nexttel: 6.21,  camtel: 7.8 },
      { rang: 3, indicateur: 'Latence Moyenne (ms)',  poids_pct: 15, orange: 63,    mtn: 51,    nexttel: 78,    camtel: 70 },
      { rang: 4, indicateur: 'Taux de Succès HTTP (%)',poids_pct:10, orange: 96.5,  mtn: 97.1,  nexttel: 91.3,  camtel: 93.8 },
      { rang: 5, indicateur: 'Score QoE Global (/100)',poids_pct:15, orange: 81.4,  mtn: 82.7,  nexttel: 64.7,  camtel: 73.5 },
    ],
    device_segmentation_brand: [
      { brand: 'Samsung', part_pct: 28.4, debit_dl: 22.14, latence_ms: 36 },
      { brand: 'Apple',   part_pct: 8.6,  debit_dl: 24.91, latence_ms: 31 },
      { brand: 'Xiaomi',  part_pct: 12.1, debit_dl: 18.65, latence_ms: 39 },
      { brand: 'Tecno',   part_pct: 22.7, debit_dl: 16.28, latence_ms: 42 },
    ],
    device_segmentation_model: [
      { model: 'Galaxy A54', part_pct: 12.6, debit_dl: 23.02, latence_ms: 34 },
      { model: 'iPhone 15',  part_pct: 7.1,  debit_dl: 25.66, latence_ms: 29 },
      { model: 'Spark 20',   part_pct: 9.3,  debit_dl: 15.18, latence_ms: 46 },
      { model: 'Redmi 13C',  part_pct: 8.9,  debit_dl: 17.72, latence_ms: 41 },
    ],
    connection_type_donut: [
      { type: 'Mobile', pct: 68.7 },
      { type: 'WiFi',   pct: 31.3 },
    ],
  };

  for (const [kind, data] of Object.entries({
    overview:        overviewData,
    infrastructure:  infrastructureData,
    qos:             qosData,
    benchmark:       benchmarkData,
    qoe_timeseries:  qoeTimeseriesData,
  })) {
    await Snapshot.findOneAndUpdate({ kind }, { kind, data }, { upsert: true });
  }
  console.log('[Seed] Snapshots overview/infrastructure/qos/benchmark/qoe_timeseries créés.');

  console.log('[Seed] Terminé avec succès.');
  await mongoose.disconnect();
}

seed().catch((err) => {
  console.error('[Seed] Erreur :', err);
  process.exit(1);
});
