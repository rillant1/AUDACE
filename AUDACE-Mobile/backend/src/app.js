const express = require('express');
const cors    = require('cors');
const routes  = require('./routes');

const app = express();

app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(routes);

// Route 404 explicite
app.use((_req, res) => res.status(404).json({ erreur: 'Route inconnue' }));

module.exports = app;
