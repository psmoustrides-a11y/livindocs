import express from 'express';
import { validateInput, formatResponse } from '@monorepo/shared';

const app = express();
app.use(express.json());

app.get('/health', (req, res) => {
  res.json(formatResponse({ status: 'ok' }));
});

app.get('/api/users', (req, res) => {
  res.json(formatResponse({ users: [] }));
});

app.post('/api/users', (req, res) => {
  const valid = validateInput(req.body);
  if (!valid) {
    res.status(400).json(formatResponse({ error: 'Invalid input' }));
    return;
  }
  res.status(201).json(formatResponse({ created: true }));
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`API running on port ${PORT}`));

export default app;
