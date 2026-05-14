'use strict';
const express = require('express');
const cors    = require('cors');
const redis   = require('redis');

const app = express();
app.use(cors());
app.use(express.json());

const BOARD_KEY  = 'quiz:leaderboard';
const MAX_ENTRIES = 50;

const client = redis.createClient({ url: process.env.REDIS_URL || 'redis://redis:6379' });
client.on('error', err => console.error('Redis error:', err));

app.get('/health', (_req, res) => {
  res.json({ status:'ok', service:'leaderboard-service', redis: client.isReady ? 'connected':'disconnected', ts: new Date().toISOString() });
});

app.get('/leaderboard', async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 10, 50);
    const entries = await client.zRangeWithScores(BOARD_KEY, 0, limit - 1, { REV: true });
    res.json({
      leaderboard: entries.map((e, i) => {
        const p = JSON.parse(e.value);
        return { rank: i + 1, name: p.name, score: e.score, totalQuestions: p.totalQuestions, percentage: Math.round((e.score / p.totalQuestions) * 100), date: p.date };
      }),
    });
  } catch (err) { console.error(err); res.status(500).json({ error:'Failed to fetch leaderboard' }); }
});

app.post('/score', async (req, res) => {
  try {
    const { name, score, totalQuestions } = req.body;
    if (!name || score == null || !totalQuestions) return res.status(400).json({ error:'name, score and totalQuestions required' });
    const entry = JSON.stringify({ name: String(name).trim().slice(0,20), totalQuestions, date: new Date().toISOString().slice(0,10), id: Date.now() });
    await client.zAdd(BOARD_KEY, { score: Math.max(0, Math.min(score, totalQuestions)), value: entry });
    const total = await client.zCard(BOARD_KEY);
    if (total > MAX_ENTRIES) await client.zRemRangeByRank(BOARD_KEY, 0, total - MAX_ENTRIES - 1);
    const rank = await client.zRevRank(BOARD_KEY, entry);
    res.json({ success:true, rank: rank + 1 });
  } catch (err) { console.error(err); res.status(500).json({ error:'Failed to submit score' }); }
});

const PORT = process.env.PORT || 3002;
client.connect()
  .then(() => app.listen(PORT, () => console.log(`✅ leaderboard-service listening on :${PORT}`)))
  .catch(err => { console.error('Redis connect failed:', err); process.exit(1); });
