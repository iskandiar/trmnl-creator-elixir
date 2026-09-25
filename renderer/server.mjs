import http from 'node:http';
import {chromium} from 'playwright';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {timingSafeEqual} from 'node:crypto';
const exec = promisify(execFile);
const secret = process.env.RENDERER_SECRET;
if (!secret) throw new Error('RENDERER_SECRET is required');
let browser;
let busy = false;
const authorized = value => {
  const a = Buffer.from(value || ''), b = Buffer.from(`Bearer ${secret}`);
  return a.length === b.length && timingSafeEqual(a, b);
};
const server = http.createServer(async (req, res) => {
  if (req.url === '/health' && req.method === 'GET') {res.writeHead(browser?.isConnected() ? 200 : 503); return res.end('ok');}
  if (req.url !== '/render' || req.method !== 'POST') {res.writeHead(404);return res.end();}
  if (!authorized(req.headers.authorization)) {res.writeHead(401);return res.end();}
  if (busy) {res.writeHead(503);return res.end('Renderer busy; retry');}
  busy = true;
  let context, dir;
  try {
    const chunks = []; let length = 0;
    for await (const chunk of req) {length += chunk.length;if (length > 2_000_000) throw new Error('Too large');chunks.push(chunk);}
    const {html} = JSON.parse(Buffer.concat(chunks));
    if (typeof html !== 'string') throw new Error('Invalid request');
    if (!browser?.isConnected()) browser = await chromium.launch({headless: true, args: ['--disable-dev-shm-usage']});
    context = await browser.newContext({viewport: {width: 800,height: 480}, deviceScaleFactor: 1, javaScriptEnabled: false});
    await context.route('**/*', route => route.abort());
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    await page.setContent(html, {waitUntil: 'load'});
    await page.evaluate(async () => {
      await document.fonts.ready;
      for (const block of document.querySelectorAll('section')) {
        const elements = block.querySelectorAll('.content, .day, h2');
        if ([...elements].some(el => el.scrollHeight > el.clientHeight + 1 || el.scrollWidth > el.clientWidth + 1)) {
          block.querySelector('.overflow').style.display = 'block';
          const bottom = block.getBoundingClientRect().bottom - 20;
          for (const row of block.querySelectorAll('.event')) {
            if (row.getBoundingClientRect().bottom > bottom) row.style.visibility = 'hidden';
          }
        }
      }
    });
    dir = await mkdtemp(join(tmpdir(), 'trmnl-'));
    const source = join(dir,'source.png'), output = join(dir,'screen.png');
    await page.screenshot({path: source, animations: 'disabled'});
    await exec(process.env.MAGICK_BIN || 'convert', [source, '-alpha', 'off', '-colorspace', 'Gray', '-threshold', '65%', '-type', 'bilevel', '-define', 'png:color-type=0', '-depth', '1', output], {timeout: 10000});
    const image = await readFile(output);
    res.writeHead(200, {'Content-Type': 'image/png'});res.end(image);
  } catch {
    res.writeHead(500);res.end('Render failed');
  } finally {
    await context?.close();
    if (dir) await rm(dir, {recursive:true,force:true});
    busy = false;
  }
});
browser = await chromium.launch({headless:true, args:['--disable-dev-shm-usage']});
server.requestTimeout = 20000;
server.headersTimeout = 10000;
server.listen(3001, process.env.RENDERER_HOST || '0.0.0.0');
process.on('SIGTERM', async () => {server.close();await browser.close();process.exit(0);});
