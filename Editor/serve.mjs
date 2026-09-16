import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
const root = new URL('../Sources/EditorHost/Resources/Editor/', import.meta.url);
const types = { 'index.html': 'text/html; charset=utf-8', 'editor.js': 'text/javascript; charset=utf-8', 'editor.css': 'text/css; charset=utf-8' };
createServer(async (request, response) => {
  const name = new URL(request.url, 'http://127.0.0.1').pathname.slice(1) || 'index.html';
  if (!Object.hasOwn(types, name)) { response.writeHead(404).end(); return; }
  try {
    response.writeHead(200, { 'Content-Type': types[name], 'Cache-Control': 'no-store' });
    response.end(await readFile(new URL(name, root)));
  } catch { response.writeHead(500).end('Run npm run build first'); }
}).listen(4178, '127.0.0.1', () => console.log('Editor harness ready at http://127.0.0.1:4178'));
