// checks/compile-page-check.mjs — row P12.6 (D206): host/compile.html, the
// browser self-compilation demo, in headless Chromium. Builds the page with
// host/build-compile-serve.sh into a temporary directory (or uses
// LW_COMPILE_DIR, a directory that script produced), serves it from this
// process (plain HTTP: the JSPI lane needs no COOP/COEP, D91), and compiles
// two sources in the page:
//   fib    corpus/scalar/fib.clj: the compiler pane prints the text and
//          binary lines, the module's bytes equal `wasm-tools parse` of the
//          WAT the page kept (D211's oracle, with host/wat-asm on the page's
//          side), the program pane prints what native lg prints for the
//          file and exits 0, the module line offers both downloads;
//   limit  a defmulti: the compiler stops with native's named limit, there
//          is no module, and the page keeps working.
// Exit 0 all pass, 1 a failed assertion (each printed), 2 the page or its
// build script does not exist yet. Playwright comes from the workspace's
// smoke-script install, as in checks/explorer-page-check.mjs. A compile in
// the page takes tens of seconds (the P12.5 figures); the waits allow 15 min.
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
if (!fs.existsSync(path.join(root, 'host/compile.html')) || !fs.existsSync(path.join(root, 'host/build-compile-serve.sh'))) {
  console.log('NOT IMPLEMENTED: host/compile.html or host/build-compile-serve.sh missing');
  process.exit(2);
}
const toolsDir = process.env.LW_BROWSER_TOOLS || path.resolve(here, '../../../local-scripts');
const pwDir = path.resolve(toolsDir, 'browser-smoke-playwright');
const pw = await import(pathToFileURL(createRequire(path.join(pwDir, 'package.json')).resolve('playwright')).href);
const chromium = pw.chromium || pw.default.chromium;

const LG = process.env.LG;
if (!LG) { console.log('LG unset (source checks/env.sh)'); process.exit(2); }
const FIB = path.join(root, 'corpus/scalar/fib.clj');
const fibSrc = fs.readFileSync(FIB, 'utf8');
const nat = spawnSync(LG, [FIB], { encoding: 'utf8' });
if (nat.status !== 0) { console.log(`native lg failed on ${FIB}: ${nat.stderr}`); process.exit(1); }
const LIMIT_SRC = '(defmulti area :shape)\n(defmethod area :square [s] (* (:side s) (:side s)))\n(println (area {:shape :square :side 3}))\n';

let dir = process.env.LW_COMPILE_DIR, tmp = null;
if (!dir) {
  tmp = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'compile-page.'));
  dir = tmp;
  const r = spawnSync('bash', [path.join(root, 'host/build-compile-serve.sh'), dir], { stdio: ['ignore', 'inherit', 'inherit'] });
  if (r.status !== 0) { console.log(`build-compile-serve.sh failed (exit ${r.status})`); process.exit(1); }
}
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.edn': 'text/plain' };
const server = http.createServer((req, res) => {
  const f = path.join(dir, path.normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, ''));
  fs.readFile(f, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'content-type': TYPES[path.extname(f)] || 'application/octet-stream' });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

let failed = 0;
const check = (ok, what, got) => {
  if (ok) console.log(`ok   ${what}`);
  else { failed++; console.log(`FAIL ${what}${got === undefined ? '' : `\n     got: ${JSON.stringify(got)}`}`); }
};

const b = await chromium.launch();
const p = await b.newPage();
const errs = [];
p.on('pageerror', (e) => errs.push(String(e)));
const state = () => p.evaluate(() => {
  const S = window.__lwcompile;
  let bytesB64 = null;
  if (S.bytes) { let s = ''; for (let i = 0; i < S.bytes.length; i += 4096) s += String.fromCharCode(...S.bytes.subarray(i, i + 4096)); bytesB64 = btoa(s); }
  return { ...S, bytes: undefined, bytesLen: S.bytes ? S.bytes.length : null, bytesB64,
    status: document.getElementById('status').textContent, sizes: document.getElementById('sizes').textContent,
    modLine: document.getElementById('mod-line').textContent, programPane: document.getElementById('program-out').textContent,
    downloads: [...document.querySelectorAll('#mod-line a')].map((a) => [a.download, a.href.slice(0, 5)]),
    watShown: !document.getElementById('wat-details').hidden, elapsed: document.getElementById('elapsed').textContent,
    runDisabled: document.getElementById('run').disabled };
});
const submit = async (text) => {
  const n = await p.evaluate(() => window.__lwcompile.runs);
  await p.fill('#src', text);
  await p.click('#run');
  await p.waitForFunction((n) => window.__lwcompile.runs > n, n, { timeout: 900000 });
  return state();
};

try {
  await p.goto(`${base}/compile.html`, { waitUntil: 'domcontentloaded' });
  await p.waitForFunction(() => window.__lwcompile && (window.__lwcompile.ready || window.__lwcompile.error), null, { timeout: 180000 });
  const boot = await state();
  check(boot.ready && !boot.error && !boot.runDisabled, 'the page loads the compiler module, the snapshot and the assembler', boot);
  check(/^compile\.wasm · \d+ KB · snapshot \d+ KB · compiled in /.test(boot.status) && /^over the wire: compiler \d+ KB, snapshot \d+ KB, assembler \d+ KB/.test(boot.sizes),
    'header: the status line and the over-the-wire line from sizes.json', [boot.status, boot.sizes]);
  console.log(`     ${boot.status}\n     ${boot.sizes}`);

  // 1. fib: compiled in the page, assembled by wat-asm, run on the page
  const f = await submit(fibSrc);
  check(f.exit === 0 && !f.error, 'fib: the compiler module exits 0', { exit: f.exit, error: f.error, out: f.compilerOut.slice(-400) });
  const text = f.compilerOut.match(/^text (\d+) ([0-9a-f]{8})$/m), bin = f.compilerOut.match(/^binary (\d+)$/m);
  check(text && bin && Number(bin[1]) === f.bytesLen && f.wat && f.wat.length === Number(text[1]),
    'fib: the compiler prints the text and binary lines and the page kept both', { text: text && text[0], bin: bin && bin[0], bytesLen: f.bytesLen, watLen: f.wat && f.wat.length });
  if (f.wat && f.bytesB64) {
    const w = path.join(dir, 'check-fib.wat'), o = path.join(dir, 'check-fib.wasm');
    fs.writeFileSync(w, f.wat);
    const r = spawnSync('wasm-tools', ['parse', w, '-o', o], { encoding: 'utf8' });
    const oracle = r.status === 0 ? fs.readFileSync(o) : null;
    check(oracle && Buffer.compare(oracle, Buffer.from(f.bytesB64, 'base64')) === 0,
      `fib: the page's bytes are wasm-tools' for the same text (${f.bytesLen} bytes)`, r.status === 0 ? { oracle: oracle.length, page: f.bytesLen } : r.stderr);
  } else check(false, 'fib: no WAT or bytes to compare', f.modLine);
  const progOut = f.programOut.replace(/\n\[exit \d+, ran in [^\]]*\]\n$/, '');
  check(progOut === nat.stdout && f.programExit === 0, 'fib: the program pane prints native lg\'s output and exits 0', { page: f.programOut, native: nat.stdout, exit: f.programExit });
  check(/^\d+ bytes, assembled from \d+ bytes of WAT in /.test(f.modLine) && f.downloads.length === 2 && f.downloads.every(([, h]) => h === 'blob:') && f.watShown,
    'fib: the module line gives the size, the assembler time, both downloads and the WAT view', { modLine: f.modLine, downloads: f.downloads, watShown: f.watShown });
  console.log(`     ${f.elapsed}; assembler ${f.asmMs && f.asmMs.toFixed(1)} ms; ${f.modLine}`);

  // 2. a named limit: the compiler stops as the native driver does
  const l = await submit(LIMIT_SRC);
  check(l.exit !== 0 && /lower-wasm: unsupported top-level form defmulti/.test(l.compilerOut) && l.bytesLen === null,
    'limit: the compiler stops with native\'s named limit and keeps no module', { exit: l.exit, out: l.compilerOut.slice(-300), bytesLen: l.bytesLen });
  check(/^no module: the compiler exited \d+$/.test(l.modLine) && /nothing to run/.test(l.programPane) && !l.runDisabled && !l.watShown,
    'limit: the module line says so, the program pane has nothing to run, the page keeps working', { modLine: l.modLine, programPane: l.programPane, runDisabled: l.runDisabled });

  check(errs.length === 0, 'no uncaught page errors', errs);
} catch (e) {
  failed++; console.log(`FAIL ${String((e && e.stack) || e)}`);
} finally {
  await b.close(); server.close();
  if (tmp) fs.rmSync(tmp, { recursive: true, force: true });
}
console.log(failed ? `compile-page: ${failed} FAILED` : 'compile-page: all passed');
process.exit(failed ? 1 : 0);
