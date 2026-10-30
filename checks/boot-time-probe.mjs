// checks/boot-time-probe.mjs <dir> <port> <label> [reps]
// Time-to-title and time-to-game-screen per lane, repeated for a median.
// Serves <dir> with COOP/COEP from this process (the stock lane's key ring
// needs SharedArrayBuffer), then REPS fresh pages: navigation to "press any
// key" in the page text = time-to-title; Space; "hp" or "floor" in the page
// text (the map screen's HUD) = time-to-map. Prints one JSON line. Driven by
// checks/size-boot.sh (rows P4.3 and P7.4). Playwright is resolved the way
// checks/browser-boot.mjs does: LW_BROWSER_TOOLS, else ../../../local-scripts,
// each holding browser-smoke-playwright/.
import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const toolsDir = process.env.LW_BROWSER_TOOLS || path.resolve(here, '../../../local-scripts');
const pwDir = path.resolve(toolsDir, 'browser-smoke-playwright');
const pw = await import(pathToFileURL(createRequire(path.join(pwDir, 'package.json')).resolve('playwright')).href);
const chromium = pw.chromium || pw.default.chromium;
const dir = path.resolve(process.argv[2]), port = parseInt(process.argv[3]), label = process.argv[4];
const reps = parseInt(process.argv[5] || '3');
const types = { '.html':'text/html', '.js':'text/javascript', '.wasm':'application/wasm' };
const server = http.createServer((req,res)=>{
  const p = path.join(dir, req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  fs.readFile(p,(e,b)=>{ if(e){res.writeHead(404);return res.end('nf');}
    res.writeHead(200,{'Content-Type':types[path.extname(p)]||'application/octet-stream',
      'Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp'});
    res.end(b); });
});
await new Promise(r=>server.listen(port,r));
const browser = await chromium.launch();
const titles=[], screens=[];
for (let i=0;i<reps;i++){
  const page = await browser.newPage();
  const t0 = Date.now();
  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil:'domcontentloaded' });
  await page.waitForFunction(()=>/press any key/i.test(document.body.innerText), null, { timeout:120000 });
  const tTitle = Date.now()-t0;
  await page.keyboard.press('Space');
  await page.waitForFunction(()=>/hp[: ]/i.test(document.body.innerText)||/floor/i.test(document.body.innerText), null, { timeout:120000 });
  const tScreen = Date.now()-t0;
  titles.push(tTitle); screens.push(tScreen);
  await page.close();
}
const med = a => a.slice().sort((x,y)=>x-y)[Math.floor(a.length/2)];
console.log(JSON.stringify({label, titleMs: titles, titleMedian: med(titles), screenMs: screens, screenMedian: med(screens)}));
await browser.close(); server.close();
