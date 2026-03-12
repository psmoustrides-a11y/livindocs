const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const router = express.Router();

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-in-production';

// In-memory credential store
const credentials = [
  {
    email: 'alice@example.com',
    passwordHash: bcrypt.hashSync('password123', 10),
  },
];

// POST /api/auth/login — Authenticate and get token
router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  const cred = credentials.find((c) => c.email === email);
  if (!cred) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const valid = await bcrypt.compare(password, cred.passwordHash);
  if (!valid) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const token = jwt.sign({ email }, JWT_SECRET, { expiresIn: '24h' });
  res.json({ token, expiresIn: '24h' });
});

// POST /api/auth/register — Create new credentials
router.post('/register', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  if (credentials.find((c) => c.email === email)) {
    return res.status(409).json({ error: 'Email already registered' });
  }

  const passwordHash = await bcrypt.hash(password, 10);
  credentials.push({ email, passwordHash });
  res.status(201).json({ message: 'Registration successful' });
});

module.exports = router;
