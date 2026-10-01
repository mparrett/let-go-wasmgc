// checks/browser-boot.mjs <base-url> <label> <hello-expected-stdout-file>
// Drives host/index.html in headless Chromium (driven by checks/browser-boot.sh):
//   hello: ?module=hello.wasm, wait for the run to finish, compare stdout
//          byte for byte with native lg's;
//   keys:  ?module=keys.wasm, wait for "ready", press a, b, q, compare the echo.
// Prints one JSON line. Playwright comes from the workspace's smoke-script
// install (local-scripts/browser-smoke-playwright), not a local npm install.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const pwDir = path.resolve(here, '../../../local-scripts/browser-smoke-playwright');
const pw = await import(pathToFileURL(createRequire(path.join(pwDir, 'package.json')).resolve('playwright')).href);
const chromium = pw.chromium || pw.default.chromium;   // resolve() lands on the CJS entry

const [base, label, expectedFile] = process.argv.slice(2);
const expected = fs.readFileSync(expectedFile, 'utf8');
const KEYS_EXPECTED = 'size 80 24\nready\nkey 97\nkey 98\nkey 113\npending 0\nbye\n';

const browser = await chromium.launch();
const out = { label };
async function load(module) {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  const t0 = Date.now();
  await page.goto(`${base}/index.html?module=${module}`, { waitUntil: 'domcontentloaded' });
  return { page, errors, t0 };
}
const lgw = (page) => page.evaluate(() => window.__lgw);

try {
  {
    const { page, errors, t0 } = await load('hello.wasm');
    await page.waitForFunction(() => window.__lgw && window.__lgw.done, null, { timeout: 30000 });
    const r = await lgw(page);
    out.coi = r.coi; out.jspi = r.jspi; out.sab = r.sab;
    out.hello = {
      pass: r.code === 0 && r.stdout === expected,
      code: r.code, error: r.error || null,
      // host-relative (from run(): compile+instantiate+main) and page-relative
      firstOutputMs: r.tFirstOutput, totalMs: r.tTotal,
      pageFirstOutputMs: r.tFirstOutputPage, pageDoneMs: r.tDonePage, wallMs: Date.now() - t0,
      errors,
    };
    if (!out.hello.pass) out.hello.stdout = r.stdout;
    await page.close();
  }
  {
    const { page, errors } = await load('keys.wasm');
    await page.waitForFunction(() => window.__lgw && /ready\n/.test(window.__lgw.stdout), null, { timeout: 30000 });
    for (const k of ['a', 'b', 'q']) await page.keyboard.press(k);
    await page.waitForFunction(() => window.__lgw.done, null, { timeout: 10000 });
    const r = await lgw(page);
    out.keys = { pass: r.code === 0 && r.stdout === KEYS_EXPECTED, code: r.code, errors };
    if (!out.keys.pass) out.keys.stdout = r.stdout;
    await page.close();
  }
} catch (e) {
  out.failure = String((e && e.message) || e).split('\n')[0];
}
await browser.close();
console.log(JSON.stringify(out));
