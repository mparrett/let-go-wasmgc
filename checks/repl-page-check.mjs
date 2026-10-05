import path from 'node:path'; // External browser tools configuration (2026-10-03).
import { createRequire } from 'node:module'; import { pathToFileURL } from 'node:url'; const pwm = await import(pathToFileURL(createRequire(process.env.LW_BROWSER_TOOLS ? path.join(path.resolve(process.env.LW_BROWSER_TOOLS), 'browser-smoke-playwright/package.json') : new URL('../../../local-scripts/browser-smoke-playwright/package.json', import.meta.url).pathname).resolve('playwright')).href); const chromium = (pwm.default ?? pwm).chromium;
const b = await chromium.launch(); const p = await b.newPage();
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('http://127.0.0.1:8262/repl.html', { waitUntil: 'domcontentloaded' });
await p.waitForFunction(() => document.getElementById('out').textContent.includes('WasmGC'), null, { timeout: 30000 });
await p.waitForSelector('#input:not([disabled])'); await p.fill('#input', '(defn fib [n] (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))) (fib 25)');
await p.press('#input', 'Enter');
try { await p.waitForFunction(() => document.getElementById('out').textContent.includes('75025'), null, { timeout: 15000 }); } catch (e) { console.log('TIMEOUT'); console.log('status:', await p.evaluate(() => document.getElementById('status').textContent)); console.log('out:', JSON.stringify(await p.evaluate(() => document.getElementById('out').textContent))); console.log('input:', await p.evaluate(() => document.getElementById('input').value)); console.log('errors:', errs); await b.close(); process.exit(1); }
await p.selectOption('#examples', { label: 'frequencies' });
await p.press('#input', 'Enter');
await p.waitForFunction(() => document.getElementById('out').textContent.includes('["i" 4]'), null, { timeout: 30000 });
console.log(await p.evaluate(() => document.getElementById('status').textContent));
console.log(await p.evaluate(() => document.getElementById('out').textContent));
console.log('errors:', errs);
await b.close();
