// Cihaz sayfasını ve ara depoyu yerelde denemek için (Google'a bağlanmaz):
//   node backend/apps-script/serve.js
// Sayfalar 8787'den, taklit ara depo 8788'den sunulur; böylece tarayıcı gerçekte olduğu gibi
// farklı kaynağa (cross-origin) istek atar. Apps Script gibi her yanıt önce 302 ile yönlenir.
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

const { createBackend } = require('./harness');

const SECRET = process.env.SECRET || 'secret';
const PAGES_PORT = Number(process.env.PAGES_PORT || 8787);
const BACKEND_PORT = Number(process.env.BACKEND_PORT || 8788);
const DOCS = path.join(__dirname, '..', '..', 'docs');
const BACKEND_URL = `http://127.0.0.1:${BACKEND_PORT}/exec`;

const backend = createBackend({ secret: SECRET });
const daysAgo = (days) => new Date(Date.now() - days * 86400000).toISOString();

backend.post({
  action: 'putDevices',
  key: SECRET,
  devices: [
    {
      id: 3,
      name: 'Philips Kahve Makinesi',
      room: 'Mutfak',
      category: 'Mutfak Aletleri',
      modelInfo: 'Philips EP2220/10',
      price: 8489.5,
      warranty: 24,
      purchaseDate: '2025-03-10T00:00:00.000',
      serviceInfo: 'Yetkili servis: 0850 000 00 00',
      notes: 'Filtre modeli <b>CA6903</b>',
      tasks: [
        { id: 11, name: 'Kireç çözme', intervalDays: 60, lastCompletedAt: daysAgo(5) },
        { id: 12, name: 'Çöp haznesi temizliği', intervalDays: 7, lastCompletedAt: daysAgo(10) },
        { id: 13, name: 'Demlik temizliği', intervalDays: 7, lastCompletedAt: daysAgo(1) },
      ],
    },
  ],
});

const deviceKey = (id) => crypto.createHmac('sha256', SECRET).update(String(id)).digest('hex').substring(0, 16);

const cors = { 'Access-Control-Allow-Origin': '*' };
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json' };

// --- Sayfalar: /homecare/... -> docs/... --------------------------------------------------------
http
  .createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (!url.pathname.startsWith('/homecare/')) {
      res.writeHead(404).end('404');
      return;
    }
    const relative = url.pathname.slice('/homecare/'.length);

    // Yerel deneme için docs/config.js yerine taklit ara depo adresi verilir.
    if (relative === 'config.js') {
      res.writeHead(200, { 'Content-Type': types['.js'] }).end(`window.HOMECARE_BACKEND_URL = '${BACKEND_URL}';`);
      return;
    }

    const file = path.join(DOCS, relative);
    if (!file.startsWith(DOCS) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404).end('404');
      return;
    }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'text/plain' }).end(fs.readFileSync(file));
  })
  .listen(PAGES_PORT, '127.0.0.1');

// --- Taklit Apps Script ---------------------------------------------------------------------------
const results = new Map();

http
  .createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');

    // Tarayıcı hata ayıklama: kayıtları görmek için.
    if (url.pathname === '/debug') {
      res.writeHead(200, { ...cors, 'Content-Type': types['.json'] });
      res.end(JSON.stringify({ records: backend.sheets.get('Kayitlar')?.rows ?? [], devices: backend.sheets.get('Cihazlar')?.rows ?? [] }));
      return;
    }

    if (url.pathname.startsWith('/echo/')) {
      const body = results.get(url.pathname.slice('/echo/'.length)) ?? JSON.stringify({ ok: false, error: 'expired' });
      res.writeHead(200, { ...cors, 'Content-Type': types['.json'] }).end(body);
      return;
    }

    if (url.pathname !== '/exec') {
      res.writeHead(404, cors).end('404');
      return;
    }

    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      const result =
        req.method === 'POST'
          ? backend.post(Buffer.concat(chunks).toString('utf8'))
          : backend.get(Object.fromEntries(url.searchParams));
      const id = crypto.randomUUID();
      results.set(id, JSON.stringify(result));
      res.writeHead(302, { ...cors, Location: `http://127.0.0.1:${BACKEND_PORT}/echo/${id}` }).end();
    });
  })
  .listen(BACKEND_PORT, '127.0.0.1');

console.log(`Cihaz sayfası: http://127.0.0.1:${PAGES_PORT}/homecare/device/index.html?id=3&k=${deviceKey(3)}`);
console.log(`Ara depo     : ${BACKEND_URL}  (SECRET=${SECRET})`);
console.log(`Kayıtlar     : http://127.0.0.1:${BACKEND_PORT}/debug`);
