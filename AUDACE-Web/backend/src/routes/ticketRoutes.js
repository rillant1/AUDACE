const express = require('express');
const { requireAuth } = require('../middleware/auth');
const { list, create, advance, addComment } = require('../controllers/ticketController');

const router = express.Router();

router.use(requireAuth);
router.get('/', list);
router.post('/', create);
router.patch('/:id/advance', advance);
router.post('/:id/comments', addComment);

module.exports = router;
