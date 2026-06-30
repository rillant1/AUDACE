const express = require('express');
const { requireAuth } = require('../middleware/auth');
const { list, create, acknowledge } = require('../controllers/incidentController');

const router = express.Router();

router.use(requireAuth);
router.get('/', list);
router.post('/', create);
router.patch('/:id/acknowledge', acknowledge);

module.exports = router;
