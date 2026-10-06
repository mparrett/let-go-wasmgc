// checks/explorer-page-check.mjs — row P10.3 (D194): host/explorer.html in
// headless Chromium. Builds the page with host/build-explorer-serve.sh into a
// temporary directory (or uses LW_EXPLORER_DIR, a directory that script
// produced), serves it from this process (plain HTTP: the JSPI lane needs no
// COOP/COEP, D91), and submits three sources:
//   scalar  a defn and a call: both panes print the same values, the
//           indicator says agree, the module pane shows a size, the
//           encoder's sections and a hex view starting with the wasm magic;
//   limit   (defn f [] [1]): the compiled pane shows the emitter's named
//           limit as text, the eval pane the var, the page keeps working;
//   reader  (+ 1 2)): both panes show native's reader error;
//   print   (do (print "x") 1): output without a newline is output, 1 the value;
//   shadow  (def prn ..) then 42: the value still prints, both panes agree;
//   prefix  ' 1 is one form, value 1; ' then a comment then 1 is two forms,
//           as native reads it.
// Exit 0 all pass, 1 a failed assertion (each printed), 2 the page or its
// build script does not exist yet. Playwright comes from the workspace's
// smoke-script install, as in checks/browser-boot.mjs.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
if (!fs.existsSync(path.join(root, 'host/explorer.html')) || !fs.existsSync(path.join(root, 'host/build-explorer-serve.sh'))) {
  console.log('NOT IMPLEMENTED: host/explorer.html or host/build-explorer-serve.sh missing');
  process.exit(2);
}
const toolsDir = process.env.LW_BROWSER_TOOLS || path.resolve(here, '../../../local-scripts');
const pwDir = path.resolve(toolsDir, 'browser-smoke-playwright');
const pw = await import(pathToFileURL(createRequire(path.join(pwDir, 'package.json')).resolve('playwright')).href);
const chromium = pw.chromium || pw.default.chromium;   // resolve() lands on the CJS entry

// native's reader error for the third source, the text both panes must show
const LG = process.env.LG;
if (!LG) { console.log('LG unset (source checks/env.sh)'); process.exit(2); }
const READER_SRC = '(+ 1 2))';
const nat = spawnSync(LG, ['-e', READER_SRC], { encoding: 'utf8' });
const nativeReader = (nat.stdout + nat.stderr).replace(/\x1b\[[0-9;]*m/g, '').trimEnd();

let dir = process.env.LW_EXPLORER_DIR, tmp = null;
if (!dir) {
  tmp = fs.mkdtempSync(path.join(process.env.TMPDIR || '/tmp', 'explorer-page.'));
  dir = tmp;
  const r = spawnSync('bash', [path.join(root, 'host/build-explorer-serve.sh'), dir], { stdio: ['ignore', 'inherit', 'inherit'] });
  if (r.status !== 0) { console.log(`build-explorer-serve.sh failed (exit ${r.status})`); process.exit(1); }
}
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
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
const state = () => p.evaluate(() => ({
  ex: { ...window.__explorer, timing: undefined },
  ev: document.getElementById('eval-out').textContent,
  co: document.getElementById('compiled-out').textContent,
  agree: document.getElementById('agree').dataset.state,
  agreeText: document.getElementById('agree').textContent,
  size: document.getElementById('mod-size').textContent,
  sections: [...document.querySelectorAll('#mod-sections tbody tr')].map((r) => [r.dataset.key, ...[...r.cells].slice(1).map((c) => c.textContent)]),
  hex: document.getElementById('mod-hex').textContent,
  picks: document.getElementById('mod-pick').options.length,
}));
// submit a source and wait for its run to finish (the page runs its default
// source on load first; the explorer's run counter orders the two)
const submit = async (text) => {
  const n = await p.evaluate(() => window.__explorer.runs);
  await p.fill('#src', text);
  await p.click('#run');
  await p.waitForFunction((n) => window.__explorer.runs > n, n, { timeout: 180000 });
  return state();
};

try {
  await p.goto(`${base}/explorer.html`, { waitUntil: 'domcontentloaded' });
  await p.waitForFunction(() => window.__explorer && (window.__explorer.runs >= 1 || window.__explorer.error), null, { timeout: 180000 });
  const boot = await state();
  check(boot.ex.ready && !boot.ex.error, 'the page loads the compiler host and runs its default source', boot.ex);

  // the size breakdown: sizes.json beside the module, and the header's
  // second line from it
  let z = null;
  try { z = JSON.parse(fs.readFileSync(path.join(dir, 'sizes.json'), 'utf8')); } catch {}
  check(z && z.evaluator_and_runtime > 0 && z.kept_for_linking > 0 && z.compiler > 0
    && z.evaluator_and_runtime + z.kept_for_linking + z.compiler === z.served
    && z.served === fs.statSync(path.join(dir, 'explorer.wasm')).size,
    'sizes.json: positive deltas that sum to the served module', z);
  const hdr = await p.evaluate(() => {
    const n = (id) => { const e = document.getElementById(id); return e ? Number(e.textContent) : null; };
    const b = document.getElementById('sizes');
    return { total: n('size-total'), ev: n('size-eval'), link: n('size-link'), comp: n('size-compiler'),
      status: document.getElementById('status').textContent, line: b.hidden ? null : b.textContent, title: b.title };
  });
  check(hdr.ev > 0 && hdr.link > 0 && hdr.comp > 0 && Math.abs(hdr.ev + hdr.link + hdr.comp - hdr.total) <= 2,
    'header: the three breakdown figures sum to the module size within rounding', hdr);
  check(/^explorer\.wasm · \d+ KB( · \d+ KB over the wire)? · compiled in \d+ ms$/.test(hdr.status) && /uncompressed/.test(hdr.title),
    'header: one status line, the breakdown note in the title', hdr);
  console.log(`     ${hdr.status}\n     ${hdr.line}`);

  // record every time a pane gets the pulse class (the toggle, not its timing)
  await p.evaluate(() => {
    window.__pulses = {};
    const mo = new MutationObserver((ms) => { for (const m of ms) if (m.target.classList.contains('pulse')) window.__pulses[m.target.id] = (window.__pulses[m.target.id] || 0) + 1; });
    for (const id of ['eval-pane', 'compiled-pane', 'module']) mo.observe(document.getElementById(id), { attributes: true, attributeFilter: ['class'] });
  });
  const pulses = () => p.evaluate(() => ({ ...window.__pulses }));

  // 1. a scalar defn and a call
  const s = await submit('(defn sq [x] (* x x))\n(sq 7)');
  for (const [pane, text] of [['eval', s.ev], ['compiled', s.co]]) {
    check(text === "(defn sq [x] (* x x))\n=> #'user/sq\n(sq 7)\n=> 49\n", `scalar: the ${pane} pane shows the var and 49`, text);
  }
  // the indicator must say what the panes say, not only "agree"
  check(s.agree === (s.ev === s.co ? 'agree' : 'disagree') && s.agree === 'agree', 'scalar: the indicator says agree, and the panes are equal', [s.agree, s.agreeText]);
  check(s.picks === 2, 'scalar: one compiled module per form', s.picks);
  const bytes = Number((s.size.match(/^(\d+) bytes/) || [])[1]);
  check(bytes > 8, 'scalar: the module pane shows the module size', s.size);
  const keys = s.sections.map((r) => r[0]);
  check([':types', ':imports', ':funcs', ':exports', ':code'].every((k) => keys.includes(k)), 'scalar: the section table names the encoder model sections', keys);
  const sum = s.sections.reduce((a, r) => a + Number(r[1]), 0);
  check(sum > 0 && sum < bytes, 'scalar: section sizes fit inside the module', [sum, bytes]);
  check((s.sections.find((r) => r[0] === ':exports') || [])[3] === 'func "lw run"', 'scalar: the module exports "lw run" only', s.sections.find((r) => r[0] === ':exports'));
  check(/func host "lw rt /.test((s.sections.find((r) => r[0] === ':imports') || [])[3] || ''), 'scalar: the module imports the runtime from module "host"', s.sections.find((r) => r[0] === ':imports'));
  check(s.hex.startsWith('000000  00 61 73 6d 01 00 00 00'), 'scalar: the hex view starts with the wasm magic and version', s.hex.slice(0, 60));
  const p1 = await pulses();
  check(['eval-pane', 'compiled-pane', 'module'].every((id) => p1[id] >= 1), 'pulse: each pane gets the pulse class after a run', p1);
  await submit('(defn sq [x] (* x x))\n(sq 7)');
  const p2 = await pulses();
  check(['eval-pane', 'compiled-pane', 'module'].every((id) => p2[id] > p1[id]), 'pulse: a rerun with identical output pulses again', [p1, p2]);

  // 2. an emitter named limit
  const l = await submit('(defn f [] [1])');
  check(l.ev === "(defn f [] [1])\n=> #'user/f\n", 'limit: the eval pane shows the var', l.ev);
  check(/^\(defn f \[\] \[1\]\)\nnamed limit: wasm\.emit: unsupported form [^\n]+\n$/.test(l.co), 'limit: the compiled pane shows the named limit as text', l.co);
  check(l.agree === 'limit' && !l.ex.error, 'limit: the indicator says not compared, no host error', [l.agree, l.ex.error]);
  check(l.picks === 0 && l.hex === '', 'limit: no module is shown', [l.picks, l.size]);

  // 3. a reader error
  const r = await submit(READER_SRC);
  check(/^error: Syntax error reading source at \(EXPR:1:9\)\.\nunmatched delimiter \)$/.test(nativeReader), 'reader: native lg -e prints the reader error', nativeReader);
  for (const [pane, text] of [['eval', r.ev], ['compiled', r.co]]) {
    check(text === `${nativeReader}\n`, `reader: the ${pane} pane shows native's reader error`, text);
  }
  check(r.agree === 'agree' && !r.ex.error, 'reader: the indicator says agree, no host error', [r.agree, r.ex.error]);
  // 4. output without a newline stays output; the value is split at the
  // page's boundary, by one rule in both panes
  const o = await submit('(do (print "x") 1)');
  for (const [pane, text] of [['eval', o.ev], ['compiled', o.co]]) {
    check(text === '(do (print "x") 1)\nx\n=> 1\n', `print: the ${pane} pane shows x as output and 1 as the value`, text);
  }
  check(o.agree === 'agree', 'print: the indicator says agree', o.agree);

  // 5. a source that redefines prn does not change how values print
  const d = await submit('(def prn (fn [x] 7))\n42');
  check(d.ev === d.co && /\n42\n=> 42\n$/.test(d.ev), 'shadowed prn: both panes show 42 as the value', [d.ev, d.co]);
  check(d.agree === 'agree', 'shadowed prn: the indicator says agree', d.agree);

  // 6. a reader prefix reads its operand across whitespace: ' 1 is one form
  const q = await submit("' 1");
  for (const [pane, text] of [['eval', q.ev], ['compiled', q.co]]) {
    check(text === "' 1\n=> 1\n", `prefix: the ${pane} pane shows ' 1 as one form whose value is 1`, text);
  }
  check(q.agree === 'agree', 'prefix: the indicator says agree', q.agree);
  // ... but not across a comment: native quotes Go's VOID there and reads
  // the 1 as the next form ([' ;; c\n1] has two elements), so the prefix is
  // a form of its own; the module's reader cannot read a lone quote, and
  // both panes stop at that same error
  const qc = await submit("'\n;; a comment\n1");
  check(qc.ev.startsWith("'\nerror: ") && qc.ev === qc.co, 'prefix then comment: the quote is a form of its own, both panes show the same reader error', [qc.ev, qc.co]);
  check(qc.agree === 'agree', 'prefix then comment: the indicator says agree', qc.agree);
  check(errs.length === 0, 'no uncaught page errors', errs);
} catch (e) {
  failed++;
  console.log(`FAIL the check stopped: ${(e && e.message) || e}`);
  try { console.log(JSON.stringify(await state())); } catch {}
} finally {
  await b.close();
  server.close();
  if (tmp) fs.rmSync(tmp, { recursive: true, force: true });
}
console.log(failed ? `P10.3: ${failed} failed` : 'P10.3: all passed');
process.exit(failed ? 1 : 0);
