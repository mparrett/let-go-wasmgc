// checks/browser-boot.mjs <base-url> <label> <hello-expected-stdout-file>
// Drives host/index.html in headless Chromium (driven by checks/browser-boot.sh):
//   hello: ?module=hello.wasm, wait for the run to finish, compare stdout
//          byte for byte with native lg's;
//   keys:  ?module=keys.wasm, wait for "ready", press a, b, q, compare the echo.
//
// checks/browser-boot.mjs --xsofy <base-url> [seed]
// P4.1 backend half: the emitted xsofy module in the real shell, see
// xsofyGame() below.
//
// checks/browser-boot.mjs --walk <base-url> <seed> <out.txt>
// P4.2 lane 5's second walk (checks/lane5.sh): held-key bursts, see
// heldWalk() below. Works on any lane whose page is the real shell.
//
// checks/browser-boot.mjs --xsofy-shell <base-url> <hello-expected-stdout-file>
// Drives host/build-xsofy-serve.sh's page (the real xsofy-shell.html on
// xsofy-shell-adapter.js) instead: see xsofyShell() below.
//
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

if (process.argv[2] === '--walk') {
  console.log(JSON.stringify(await heldWalk(...process.argv.slice(3))));
  process.exit(0);
}
if (process.argv[2] === '--xsofy') {
  console.log(JSON.stringify(await xsofyGame(...process.argv.slice(3))));
  process.exit(0);
}
if (process.argv[2] === '--xsofy-shell') {
  console.log(JSON.stringify(await xsofyShell(...process.argv.slice(3))));
  process.exit(0);
}
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

// ---- --xsofy-shell ---------------------------------------------------------
// hello: the shell boots (mode 'worker', Fairfax HD loaded before xterm
//        opened, #status hidden), stdout equals native lg's and the xterm
//        buffer shows the same lines; records time to first visible output.
// keys:  keys-probe prints the size the shell gave setSize; five 'j' keydowns
//        dispatched in one task (an auto-repeat burst, through xterm's own
//        textarea → term.onData → LetGoHost.sendInput) all reach the host and
//        come back as ONE read (D98); a real 'q' press ends the program.
async function xsofyShell(base, expectedFile) {
  const expected = fs.readFileSync(expectedFile, 'utf8');
  const browser = await chromium.launch();
  const out = { label: 'xsofy-shell' };
  // first time any xterm row holds text, page-relative
  const visibleProbe = () => {
    const tick = () => {
      const r = document.querySelector('.xterm-rows');
      if (r && r.textContent.trim()) { window.__tVisible = performance.now(); return; }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };
  const rows = (page) => page.evaluate(() =>
    [...document.querySelectorAll('.xterm-rows > div')].map((d) => d.textContent.replace(/\s+$/, '')));
  const visibleLines = (rs) => { const a = [...rs]; while (a.length && a[a.length - 1] === '') a.pop(); return a; };
  async function open(module) {
    const page = await browser.newPage();
    const errors = [], bad = [];
    page.on('pageerror', (e) => errors.push(String(e)));
    // build-info.json is optional for the shell (absent = ad-hoc bundle);
    // any other failed fetch, or a console error not caused by one, counts
    page.on('response', (r) => { if (r.status() >= 400 && !r.url().endsWith('/build-info.json')) bad.push(`${r.status()} ${r.url()}`); });
    page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text()); });
    await page.addInitScript(visibleProbe);
    await page.goto(`${base}/index.html?module=${module}`, { waitUntil: 'domcontentloaded' });
    return { page, errors, bad };
  }
  try {
    {
      const { page, errors, bad } = await open('hello.wasm');
      const last = expected.trimEnd().split('\n').pop();
      await page.waitForFunction((l) => window.__lgw && window.__lgw.done
        && [...document.querySelectorAll('.xterm-rows > div')].some((d) => d.textContent.trimEnd() === l), last, { timeout: 30000 });
      const r = await page.evaluate(() => {
        const st = document.getElementById('status');
        const app = document.getElementById('app');
        const faces = [...document.fonts].filter((f) => /Fairfax HD/.test(f.family));
        const rowsEl = document.querySelector('.xterm-rows');
        return { ...window.__lgw, tVisible: window.__tVisible,
          boot: {
            shellRoot: !!document.getElementById('xsofy-shell'),
            xtermAttached: !!(app && app.querySelector('.xterm .xterm-screen')),
            statusHidden: !!st && getComputedStyle(st).display === 'none',
            fontLoaded: faces.length > 0 && faces.every((f) => f.status === 'loaded'),
            fontInUse: !!rowsEl && /Fairfax HD/.test(getComputedStyle(rowsEl).fontFamily),
          } };
      });
      const lines = visibleLines(await rows(page));
      const bootOk = r.readyMode === 'worker' && Object.values(r.boot).every(Boolean);
      out.coi = r.coi; out.jspi = r.jspi;
      out.boot = { pass: bootOk, readyMode: r.readyMode, ...r.boot };
      out.hello = {
        pass: r.code === 0 && r.stdout === expected && lines.join('\n') === expected.trimEnd() && !errors.length && !bad.length,
        code: r.code, error: r.error || null, stdoutMatch: r.stdout === expected,
        xtermMatch: lines.join('\n') === expected.trimEnd(),
        // page-relative ms: program start (after the shell's first setSize),
        // first byte handed to the shell, first text painted in xterm
        mainStartMs: r.tMainStart, shellFirstOutputMs: r.tShellFirstOutput, visibleMs: r.tVisible,
        hostFirstOutputMs: r.tFirstOutput, totalMs: r.tTotal, errors, bad,
      };
      if (!out.hello.xtermMatch) out.hello.xterm = lines;
      await page.close();
    }
    {
      const { page, errors, bad } = await open('keys.wasm');
      await page.waitForFunction(() => [...document.querySelectorAll('.xterm-rows > div')].some((d) => d.textContent.trimEnd() === 'ready'), null, { timeout: 30000 });
      const before = await page.evaluate(() => window.__lgw.sent);
      await page.evaluate(() => {
        const ta = document.querySelector('.xterm-helper-textarea');
        for (let i = 0; i < 5; i++) {
          ta.dispatchEvent(new KeyboardEvent('keydown', { key: 'j', code: 'KeyJ', keyCode: 74, repeat: i > 0, bubbles: true, cancelable: true }));
        }
      });
      const sentJ = (await page.evaluate(() => window.__lgw.sent)) - before;
      await page.waitForFunction(() => /key 106\n/.test(window.__lgw.stdout), null, { timeout: 5000 });
      await page.waitForTimeout(300);   // any further j reads would show up here
      await page.keyboard.press('q');
      await page.waitForFunction(() => window.__lgw.done
        && [...document.querySelectorAll('.xterm-rows > div')].some((d) => d.textContent.trimEnd() === 'bye'), null, { timeout: 10000 });
      const r = await page.evaluate(() => window.__lgw);
      const lines = visibleLines(await rows(page));
      const nrows = lines.length ? (await rows(page)).length : 0;
      const [cols, rws] = r.size || [];
      const want = `size ${cols} ${rws}\nready\nkey 106\nkey 113\npending 0\nbye\n`;
      out.size = { pass: Number.isInteger(cols) && rws === nrows && r.stdout.startsWith(`size ${cols} ${rws}\n`),
        shellSetSize: r.size, xtermRows: nrows, printed: r.stdout.split('\n')[0] };
      const jReads = r.stdout.split('\n').filter((l) => l === 'key 106').length;
      out.held = { pass: sentJ === 5 && jReads === 1 && lines.filter((l) => l === 'key 106').length === 1,
        jAccepted: sentJ, jReads, dropped: r.dropped };
      out.quit = { pass: r.code === 0 && r.stdout === want && !errors.length && !bad.length, code: r.code, errors, bad };
      if (!out.quit.pass || !out.held.pass) out.keysStdout = r.stdout;
      await page.close();
    }
  } catch (e) {
    out.failure = String((e && e.message) || e).split('\n')[0];
  }
  await browser.close();
  return out;
}

// ---- --xsofy -----------------------------------------------------------------
// The emitted xsofy module (module.wasm, the adapter's default) in the real
// shell, booted the way local-scripts/browser-smoke-playwright/
// zz-boot-time-probe.mjs boots the four let-go lanes: page load to "press any
// key" in the page text (the title card) = time-to-title; Space; then "hp" or
// "floor" in the page text (the map screen's HUD) = time-to-map, both from
// navigation. Also asserts what only the D100 imports can make true: the
// title card prints the ?seed= the page was opened with (js/url-param), and
// the shell received xsofy/startup with a title and xsofy/stats (js/emit).
async function xsofyGame(base, seed = '424242') {
  const browser = await chromium.launch();
  const out = { label: 'xsofy', seed };
  const page = await browser.newPage();
  const errors = [], bad = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('response', (r) => { if (r.status() >= 400 && !r.url().endsWith('/build-info.json')) bad.push(`${r.status()} ${r.url()}`); });
  page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text()); });
  await page.addInitScript(() => {
    window.__events = [];
    for (const n of ['xsofy/startup', 'xsofy/stats']) {
      window.addEventListener(n, (e) => window.__events.push([n, e.detail]));
    }
  });
  try {
    const t0 = Date.now();
    await page.goto(`${base}/index.html?seed=${seed}`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => /press any key/i.test(document.body.innerText), null, { timeout: 120000 });
    out.titleMs = Date.now() - t0;
    out.titleSeed = await page.evaluate((s) => document.body.innerText.includes(`seed ${s}`), seed);
    await page.keyboard.press('Space');
    await page.waitForFunction(() => /hp[: ]/i.test(document.body.innerText) || /floor/i.test(document.body.innerText), null, { timeout: 120000 });
    out.mapMs = Date.now() - t0;
    await page.waitForTimeout(500);
    const r = await page.evaluate(() => ({ lgw: window.__lgw, events: window.__events }));
    const startup = r.events.find(([n]) => n === 'xsofy/startup');
    out.startup = startup ? startup[1] : null;
    out.stats = r.events.filter(([n]) => n === 'xsofy/stats').length;
    out.readyMode = r.lgw.readyMode; out.coi = r.lgw.coi; out.jspi = r.lgw.jspi;
    out.running = !r.lgw.done;
    out.error = r.lgw.error || null;
    out.errors = errors; out.bad = bad;
    out.pass = out.titleSeed && !!(out.startup && out.startup.title) && out.stats > 0
      && out.running && !errors.length && !bad.length;
  } catch (e) {
    out.failure = String((e && e.message) || e).split('\n')[0];
    out.pass = false;
    try { out.text = (await page.evaluate(() => document.body.innerText)).slice(-600); out.lgw = await page.evaluate(() => window.__lgw); } catch {}
  }
  await browser.close();
  return out;
}

// ---- --walk -------------------------------------------------------------------
// Lane 5's held-key walk. Boots like zz-determinism-probe.mjs (?seed=, title,
// Space, map, 3 s settle), then sends auto-repeat BURSTS: n keydowns of one
// key dispatched in a single task on xterm's textarea (what a held key does),
// each burst followed by a pause long enough for the turn to resolve. let-go's
// key ring coalesces a burst the game has not yet read into ONE read
// (keysource_js_wasm.go:96-122, D98), so the dump only matches across lanes
// if the emitted lane's host coalesces the same way. Bursts stay under the
// ring's 8 slots so neither lane drops keys. Writes document.body.innerText.
async function heldWalk(base, seed, outFile) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const out = { label: 'walk', seed };
  try {
    await page.goto(`${base}/?seed=${seed}`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => /press any key/i.test(document.body.innerText), null, { timeout: 120000 });
    await page.keyboard.press('Space');
    await page.waitForFunction(() => /hp[: ]/i.test(document.body.innerText) || /floor/i.test(document.body.innerText), null, { timeout: 120000 });
    await page.waitForTimeout(3000);
    const bursts = [['l', 5], ['j', 4], ['h', 6], ['k', 3], ['l', 6], ['j', 5]];
    for (const [key, n] of bursts) {
      await page.evaluate(([key, n]) => {
        const ta = document.querySelector('.xterm-helper-textarea');
        const code = 'Key' + key.toUpperCase();
        for (let i = 0; i < n; i++) {
          ta.dispatchEvent(new KeyboardEvent('keydown', { key, code, keyCode: key.toUpperCase().charCodeAt(0), repeat: i > 0, bubbles: true, cancelable: true }));
        }
      }, [key, n]);
      await page.waitForTimeout(1200);
    }
    await page.waitForTimeout(2000);
    const txt = await page.evaluate(() => document.body.innerText);
    fs.writeFileSync(outFile, txt);
    out.bytes = txt.length; out.bursts = bursts.map(([k, n]) => k + 'x' + n).join(' ');
  } catch (e) {
    out.failure = String((e && e.message) || e).split('\n')[0];
  }
  await browser.close();
  return out;
}
