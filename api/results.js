import { put, list, head } from '@vercel/blob';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();

  const RESULTS_KEY = 'edko-results.json';

  try {
    // GET — return all results
    if (req.method === 'GET') {
      try {
        const meta = await head(RESULTS_KEY);
        const resp = await fetch(meta.url);
        const data = await resp.json();
        return res.status(200).json(data);
      } catch (e) {
        // File doesn't exist yet
        return res.status(200).json([]);
      }
    }

    // POST — add a new result
    if (req.method === 'POST') {
      const newResult = req.body;
      if (!newResult || !newResult.title) {
        return res.status(400).json({ error: 'Invalid result data' });
      }

      // Load existing results
      let existing = [];
      try {
        const meta = await head(RESULTS_KEY);
        const resp = await fetch(meta.url);
        existing = await resp.json();
      } catch (e) {
        // First result
      }

      existing.push(newResult);

      // Save back
      await put(RESULTS_KEY, JSON.stringify(existing, null, 2), {
        access: 'public',
        addRandomSuffix: false,
        contentType: 'application/json',
      });

      return res.status(200).json({ ok: true, total: existing.length });
    }

    // DELETE — clear all results
    if (req.method === 'DELETE') {
      await put(RESULTS_KEY, JSON.stringify([]), {
        access: 'public',
        addRandomSuffix: false,
        contentType: 'application/json',
      });
      return res.status(200).json({ ok: true });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  } catch (err) {
    console.error('Results API error:', err);
    return res.status(500).json({ error: err.message });
  }
}
