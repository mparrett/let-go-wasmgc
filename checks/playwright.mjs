// checks/playwright.mjs — the Playwright the browser checks drive, found in
// the environment instead of at a fixed path. Candidates, in order:
//
//   1. $LW_BROWSER_TOOLS/browser-smoke-playwright, when that is set
//   2. the version package.json pins, through Node's own lookup from the
//      repo (its node_modules, then parent directories' and NODE_PATH)
//   3. the global npm root (`npm root -g`), one install for every worktree
//   4. `playwright` on PATH: a Node install's package, or the Node driver a
//      Python install bundles (site-packages/playwright/driver/package)
//
// The first that loads AND launches its Chromium wins. A Playwright version
// runs only its own browser build, so a candidate whose build is not
// installed is passed over rather than downloaded: the checks reuse whichever
// browser the machine already has.
//
//   import { findChromium } from './playwright.mjs';
//   const found = await findChromium();   // {chromium, from} or {why}
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sh = (cmd) => { try { return execFileSync('sh', ['-c', cmd], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return ''; } };

// each candidate is [where, thunk returning the module's entry file or null]
function candidates() {
  const fromDir = (dir) => () => createRequire(path.join(dir, 'package.json')).resolve('playwright');
  const c = [];
  if (process.env.LW_BROWSER_TOOLS)
    c.push([`LW_BROWSER_TOOLS`, fromDir(path.resolve(process.env.LW_BROWSER_TOOLS, 'browser-smoke-playwright'))]);
  c.push(["Node's lookup from the repo", fromDir(root)]);
  // the shell lookups run only when the candidates before them fail
  c.push(['the global npm root', () => {
    const g = sh('npm root -g');
    return g ? createRequire(path.join(g, 'package.json')).resolve('playwright') : null;
  }]);
  c.push(['playwright on PATH', () => {
    const bin = sh('command -v playwright');
    if (!bin) return null;
    const real = fs.realpathSync(bin);
    // a Node install: node_modules/playwright/cli.js (or its .bin link)
    const pkg = path.dirname(real);
    if (fs.existsSync(path.join(pkg, 'package.json')) && fs.existsSync(path.join(pkg, 'index.mjs'))) return path.join(pkg, 'index.mjs');
    // a Python install: <venv>/bin/playwright beside lib/python3.*/site-packages
    const lib = path.resolve(pkg, '..', 'lib');
    for (const py of fs.existsSync(lib) ? fs.readdirSync(lib) : []) {
      const drv = path.join(lib, py, 'site-packages/playwright/driver/package/index.mjs');
      if (fs.existsSync(drv)) return drv;
    }
    return null;
  }]);
  return c;
}

export async function findChromium() {
  const tried = [];
  for (const [where, entry] of candidates()) {
    let file;
    try { file = entry(); } catch { file = null; }
    if (!file) { tried.push(`${where}: not installed`); continue; }
    let chromium;
    try {
      const pw = await import(pathToFileURL(file).href);
      chromium = pw.chromium || pw.default?.chromium;   // a CJS entry puts it on default
    } catch (e) { tried.push(`${where}: does not load (${String(e).split('\n')[0]})`); continue; }
    // a launch, not executablePath(): headless Playwright runs the headless
    // shell, a separate download from the full browser that executablePath() names
    try { const b = await chromium.launch({ timeout: 30000 }); await b.close(); }
    catch (e) { tried.push(`${where}: its Chromium does not launch (${String(e).split('\n')[0]})`); continue; }
    return { chromium, from: where };
  }
  return { why: `no Playwright with an installed Chromium; tried ${tried.join('; ')}` };
}
