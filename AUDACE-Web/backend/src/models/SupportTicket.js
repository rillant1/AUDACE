const mongoose = require('mongoose');

const supportTicketSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  title: { type: String, required: true },
  description: { type: String, required: true },
  author: { type: String, required: true },
  category: { type: String, required: true },
  priority: {
    type: String,
    enum: ['basse', 'normale', 'haute', 'critique'],
    default: 'normale',
  },
  status: {
    type: String,
    enum: ['ouvert', 'enCours', 'resolu', 'clos'],
    default: 'ouvert',
  },
  slaDeadline: { type: Date, default: null },
  comments: { type: [String], default: [] },
}, { timestamps: { createdAt: 'createdAt', updatedAt: 'updatedAt' } });

module.exports = mongoose.model('SupportTicket', supportTicketSchema);
