const SupportTicket = require('../models/SupportTicket');

const NEXT_STATUS = { ouvert: 'enCours', enCours: 'resolu', resolu: 'clos', clos: null };

async function list(req, res) {
  const tickets = await SupportTicket.find().sort({ createdAt: -1 });
  res.json(tickets);
}

async function create(req, res) {
  const { title, description, author, category, priority } = req.body;
  if (!title || !description) {
    return res.status(400).json({ message: 'Titre et description requis.' });
  }
  const count = await SupportTicket.countDocuments();
  const id = `TKT-2025-${String(count + 1).padStart(3, '0')}`;
  const now = new Date();
  const ticket = await SupportTicket.create({
    id,
    title,
    description,
    author: author || 'admin.art',
    category: category || 'Autre',
    priority: priority || 'normale',
    status: 'ouvert',
    createdAt: now,
    updatedAt: now,
  });
  res.status(201).json(ticket);
}

async function advance(req, res) {
  const ticket = await SupportTicket.findOne({ id: req.params.id });
  if (!ticket) return res.status(404).json({ message: 'Ticket introuvable.' });
  const next = NEXT_STATUS[ticket.status];
  if (!next) return res.status(400).json({ message: 'Le ticket est déjà clos.' });
  ticket.status = next;
  ticket.updatedAt = new Date();
  await ticket.save();
  res.json(ticket);
}

async function addComment(req, res) {
  const { comment } = req.body;
  if (!comment || !comment.trim()) {
    return res.status(400).json({ message: 'Commentaire requis.' });
  }
  const ticket = await SupportTicket.findOne({ id: req.params.id });
  if (!ticket) return res.status(404).json({ message: 'Ticket introuvable.' });
  ticket.comments.push(comment.trim());
  ticket.updatedAt = new Date();
  await ticket.save();
  res.json(ticket);
}

module.exports = { list, create, advance, addComment };
