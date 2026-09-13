import { put, list, del } from '@vercel/blob';

export const config = {
  api: { bodyParser: false },
};

export default async function handler(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(200).end();

  try {
    if (req.method === 'PUT') {
      const filename = req.query.filename;
      if (!filename) return res.status(400).json({ error: 'Missing filename' });

      // Prefix with uploads/ for organization
      const path = 'uploads/' + filename;
      const blob = await put(path, req, { access: 'public', addRandomSuffix: false });
      return res.status(200).json(blob);
    }

    if (req.method === 'GET') {
      const { blobs } = await list({ prefix: 'uploads/' });
      return res.status(200).json(blobs);
    }

    return res.status(405).json({ error: 'Method not allowed' });
  } catch (err) {
    console.error('Upload API error:', err);
    return res.status(500).json({ error: err.message });
  }
}
