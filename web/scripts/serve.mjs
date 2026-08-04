#!/usr/bin/env node
import { createReadStream, promises as fs } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const port = Number(process.env.PORT || 4173);
const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.ts': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
};

const server = createServer(async (request, response) => {
  const pathname = decodeURIComponent(new URL(request.url || '/', 'http://localhost').pathname);
  const relative = pathname === '/' ? '/web/index.html' : pathname;
  const candidate = resolve(normalize(join(repositoryRoot, `.${relative}`)));
  if (candidate !== repositoryRoot && !candidate.startsWith(`${repositoryRoot}/`)) {
    response.writeHead(403); response.end('Forbidden'); return;
  }
  try {
    const info = await fs.stat(candidate);
    const file = info.isDirectory() ? join(candidate, 'index.html') : candidate;
    const extension = extname(file);
    const isCssModule = extension === '.css' && request.headers['sec-fetch-dest'] === 'script';
    if (isCssModule) {
      const css = await fs.readFile(file, 'utf8');
      const module = `const css = ${JSON.stringify(css)};\nconst style = document.createElement('style');\nstyle.textContent = css;\ndocument.head.append(style);\n`;
      response.writeHead(200, { 'Content-Type': 'text/javascript; charset=utf-8', 'Cache-Control': 'no-store' });
      response.end(module);
      return;
    }
    response.writeHead(200, { 'Content-Type': contentTypes[extension] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    createReadStream(file).pipe(response);
  } catch {
    response.writeHead(404); response.end('Not found');
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Doris offline demo: http://127.0.0.1:${port}/web/index.html`);
});
