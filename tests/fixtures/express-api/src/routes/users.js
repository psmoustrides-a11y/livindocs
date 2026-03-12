const express = require('express');
const router = express.Router();

// In-memory store (would be a database in production)
let users = [
  { id: 1, name: 'Alice Johnson', email: 'alice@example.com', role: 'admin' },
  { id: 2, name: 'Bob Smith', email: 'bob@example.com', role: 'user' },
];
let nextId = 3;

// GET /api/users — List all users
router.get('/', (req, res) => {
  const { role } = req.query;
  let result = users;
  if (role) {
    result = users.filter((u) => u.role === role);
  }
  res.json({ users: result, total: result.length });
});

// GET /api/users/:id — Get user by ID
router.get('/:id', (req, res) => {
  const user = users.find((u) => u.id === parseInt(req.params.id));
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }
  res.json(user);
});

// POST /api/users — Create a new user
router.post('/', (req, res) => {
  const { name, email, role } = req.body;
  if (!name || !email) {
    return res.status(400).json({ error: 'Name and email are required' });
  }
  const user = { id: nextId++, name, email, role: role || 'user' };
  users.push(user);
  res.status(201).json(user);
});

// PUT /api/users/:id — Update a user
router.put('/:id', (req, res) => {
  const user = users.find((u) => u.id === parseInt(req.params.id));
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }
  const { name, email, role } = req.body;
  if (name) user.name = name;
  if (email) user.email = email;
  if (role) user.role = role;
  res.json(user);
});

// DELETE /api/users/:id — Delete a user
router.delete('/:id', (req, res) => {
  const index = users.findIndex((u) => u.id === parseInt(req.params.id));
  if (index === -1) {
    return res.status(404).json({ error: 'User not found' });
  }
  users.splice(index, 1);
  res.status(204).end();
});

module.exports = router;
