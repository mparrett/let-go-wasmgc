// node-host.mjs — lg-wasm-host.js under Node, for CI and for the three-host
// matrix in checks/browser-boot.sh.
//
//   node host/node-host.mjs <module.wasm> [--keys abq] [--env K=V ...] [--url seed=42&x=y] [--size 100x30] [--coalesce] [--no-fs]
//
// --url feeds js/url-param (what xsofy reads ?seed= through). os/getenv
// reads the host's own environment (process.env), as native lg does, so
// `XSOFY_DEV=1 node host/node-host.mjs xsofy.wasm` unlocks the dev console;
// --env K=V adds or overrides a single name on top of it. slurp reads the
// host's file system too (env.read_file, D208, in a module built with
// LW_HOST_FS=1): a relative path is taken from the process's cwd, as native
// lg does; --no-fs answers every read as missing, as the browser host does.
//
// Keys: each character of --keys is one key, sent once the module is
// running, then end of input; otherwise piped stdin feeds keys one character
// at a time (EOF = end of input, read-key → nil), and a TTY stdin goes raw
// (one keypress = one key). stdout/stderr and the exit code behave like
// src/run.mjs. LG_HOST_TIMING=1 adds a timing line on stderr.
//
// Coalescing (D98) is OFF here unless --coalesce is given: scripted and piped
// input should reach the program key for key ("jjj" is three reads), which is
// what this host did before D98. The browser host coalesces by default.
//
// Stack depth: under JSPI `lw main` runs on a V8 secondary stack whose size
// is --wasm-stack-switching-stack-size (default 984 kB, ~5-10k lg frames)
// and whose limit check also honours --stack-size. A worker's
// resourceLimits.stackSizeMb (run.mjs, D33) does not reach that stack, so
// this host runs on the main thread and re-execs node with both flags when
// they are missing; 256 MB matches run.mjs (1M-deep int recursion passes).
//
// Compiling at run time (stage 3b-i of docs/SELF-HOST-SPEC.md, D193):
//
//   node host/node-host.mjs <host.wasm> --forms <program.lg> [--mode compile|eval]
//
// <host.wasm> is a module built with LW_EXPORT_RT=1 LW_RUNTIME_COMPILE=1
// (corpus/emit/host/host.lg). Its `lw main` runs first; then each top-level
// form of the program, in order, is either compiled in the module and linked
// (compile, the default) or evaluated in the module (eval). The ABI:
//   lw compile (param p i32) (param n i32) (result i32)
//       the n UTF-8 bytes at p of `lw mem` are one form's source text, read
//       in the module's current ns; the result is the byte length of the
//       compiled module, written at p (memory grows as needed). A form the
//       emitter cannot compile, or a compile error, is thrown as the
//       runtime's exception (tag `lw lgex`); a message starting
//       "wasm.emit: " is the emitter's named limit.
//   lw eval (param p i32) (param n i32)
//       the same input, evaluated by wasm.eval/eval; errors are thrown.
//   the compiled module imports, from module "host", only exports of the
//       running instance: "lw rt <id>" (every runtime function, <id> its
//       wat id without the `$`), "lw rt true" / "lw rt false" and the tag
//       "lw lgex"; so its import object is { host: instance.exports }
//       (linkCompiled below, the one host import stage 4 makes
//       env.instantiate). It exports "lw run" () -> the form's value.
// A top-level (try body.. (catch ..)..) is compiled as a def of a thunk of
// its body, then the try itself is evaluated around a call of that thunk,
// so the evaluated try catches what the compiled code throws.
// Exit: 0, 1 (an uncaught error, printed as `error: <report>`), 4 (a
// wasm.emit named limit in compile mode). LG_HOST_TIMING=1 prints, per
// compiled form, its byte size and the compile / link / run times.
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const FLAGS = ['--stack-size=262000', '--wasm-stack-switching-stack-size=262144'];
if (!process.execArgv.some((a) => a.startsWith('--wasm-stack-switching-stack-size'))) {
  const r = spawnSync(process.execPath, [...FLAGS, fileURLToPath(import.meta.url), ...process.argv.slice(2)], { stdio: 'inherit' });
  process.exit(r.status ?? 1);
}

const { LgWasmHost } = await import('./lg-wasm-host.js');
const args = process.argv.slice(2);
const opts = { wasm: null, keys: null, env: {}, url: null, cols: 80, rows: 24, coalesce: false, forms: null, mode: 'compile', fs: true };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--keys') opts.keys = args[++i];
  else if (a === '--env') { const [k, ...v] = args[++i].split('='); opts.env[k] = v.join('='); }
  else if (a === '--url') opts.url = args[++i];
  else if (a === '--coalesce') opts.coalesce = true;
  else if (a === '--no-fs') opts.fs = false;
  else if (a === '--forms') opts.forms = args[++i];
  else if (a === '--mode') opts.mode = args[++i];
  else if (a === '--size') { const [c, r] = args[++i].split('x').map(Number); opts.cols = c; opts.rows = r; }
  else if (a.startsWith('-')) { console.error(`node-host.mjs: unknown flag ${a}`); process.exit(2); }
  else if (opts.wasm) { console.error(`node-host.mjs: unexpected argument '${a}' after the module path (a trailing shell comment pasted into zsh does this)`); process.exit(2); }
  else opts.wasm = a;
}
if (!opts.wasm) { console.error('usage: node-host.mjs <module.wasm> [--keys STR] [--env K=V] [--size CxR]'); process.exit(2); }

// D208: a regular file's bytes, else null (missing, a directory, unreadable)
function readHostFile(path) {
  try {
    return fs.statSync(path).isFile() ? fs.readFileSync(path) : null;
  } catch {
    return null;
  }
}

const host = new LgWasmHost({
  env: { ...process.env, ...opts.env }, cols: opts.cols, rows: opts.rows,
  urlParams: opts.url == null ? null : new URLSearchParams(opts.url),
  // piped/--keys input arrives faster than a human types; queue all of it
  keyCapacity: Infinity,
  coalesceKeys: opts.coalesce,
  readFile: opts.fs ? readHostFile : null,
  onOutput: (text, fd) => fs.writeSync(fd === 2 ? 2 : 1, text),
});
if (opts.forms !== null) process.exit(await runForms(host, fs.readFileSync(opts.wasm), fs.readFileSync(opts.forms, 'utf8'), opts.mode));
const done = host.run(fs.readFileSync(opts.wasm));
// keys are only accepted once the module is running (pre-boot keys are
// dropped, as in let-go); run() sets `running` just before entering lw main
let tty = false;
const feed = () => {
  if (!host.running) return setTimeout(feed, 1);
  if (opts.keys !== null) {
    for (const ch of opts.keys) host.sendInput(ch);
    host.closeInput();
  } else if (process.stdin.isTTY) {
    tty = true;
    process.stdin.setRawMode(true);
    process.stdin.on('data', (d) => { if (d[0] === 3) { process.stdin.setRawMode(false); process.exit(130); } host.sendInput(d.toString('utf8')); });
  } else {
    process.stdin.on('data', (d) => { for (const ch of d.toString('utf8')) host.sendInput(ch); });
    process.stdin.on('end', () => host.closeInput());
  }
};
feed();
const r = await done;
if (tty) process.stdin.setRawMode(false);
if (process.env.LG_HOST_TIMING) fs.writeSync(2, `timing first=${r.tFirstOutput == null ? '-' : r.tFirstOutput.toFixed(1)}ms total=${r.tTotal.toFixed(1)}ms\n`);
process.exit(r.code);

// ---- compiling at run time (header) ----------------------------------------

// Top-level forms of lg source text: brackets, strings, char literals and
// comments are respected; reader prefixes (' ` ~ @ # ^meta) stay with their form.
export function splitForms(s, name = 'source') {
  const out = [];
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    if (/[\s,]/.test(c)) { i++; continue; }
    if (c === ';') { while (i < s.length && s[i] !== '\n') i++; continue; }
    if (c === ')' || c === ']' || c === '}') throw readerError(s, i, name, `unmatched delimiter ${c}`);
    const start = i;
    i = skipForm(s, i);
    // every form consumes text; a splitter that stood still would loop forever
    if (i <= start) throw readerError(s, i, name, `unexpected ${JSON.stringify(s[start])}`);
    out.push(s.slice(start, i));
  }
  return out;
}

// Native's two-line reader error: the position is the column after the
// offending character (1-based line, so `)` at column 1 reports :1:2).
function readerError(s, i, name, msg) {
  const before = s.slice(0, i);
  const line = before.split('\n').length;
  const col = i - before.lastIndexOf('\n') + 1;
  return new Error(`Syntax error reading source at (${name}:${line}:${col}).\n${msg}`);
}

function skipWs(s, i) {
  for (;;) {
    while (i < s.length && /[\s,]/.test(s[i])) i++;
    if (s[i] !== ';') return i;
    while (i < s.length && s[i] !== '\n') i++;
  }
}

function skipForm(s, i) {
  while ("'`~@^#".includes(s[i])) {
    if (s[i] === '^') { i = skipWs(s, skipForm(s, skipWs(s, i + 1))); continue; }
    if (s[i] === '#' && s[i + 1] === '_') { i = skipWs(s, skipForm(s, skipWs(s, i + 2))); continue; }
    // a dispatch # takes its next character directly (#( #{ #" #'), but
    // quote, syntax-quote, unquote and deref read the next form across
    // whitespace, as native's reader does: ' 1 is one form. A comment, a
    // #_ or the end there gives native's prefix nothing to read (it takes
    // Go's VOID), so the prefix is a form of its own and what follows is
    // the next form: native reads [' ;; c\n1] as two elements.
    if (s[i] === '#') { i++; continue; }
    let j = i + 1;
    while (j < s.length && /[\s,]/.test(s[j])) j++;
    if (j >= s.length || s[j] === ';' || (s[j] === '#' && s[j + 1] === '_')) return i + 1;
    i = j;
  }
  const c = s[i];
  if (c === '"') return skipString(s, i);
  if (c === '\\') { i += 2; while (i < s.length && /[A-Za-z0-9]/.test(s[i])) i++; return i; }
  if (c === '(' || c === '[' || c === '{') {
    let depth = 0;
    while (i < s.length) {
      const d = s[i];
      if (d === '"') { i = skipString(s, i); continue; }
      if (d === ';') { while (i < s.length && s[i] !== '\n') i++; continue; }
      if (d === '\\') { i += 2; continue; }
      if (d === '(' || d === '[' || d === '{') depth++;
      else if (d === ')' || d === ']' || d === '}') { depth--; if (depth === 0) return i + 1; }
      i++;
    }
    return i;
  }
  while (i < s.length && !/[\s,()\[\]{}";]/.test(s[i])) i++;
  return i;
}

function skipString(s, i) {
  i++;
  while (i < s.length && s[i] !== '"') i += s[i] === '\\' ? 2 : 1;
  return i + 1;
}

// A top-level (try body.. clause..) as [def of a thunk of the body, the try
// around a call of it], or null for any other form.
function liftTry(form, k) {
  if (!/^\(try[\s,]/.test(form)) return null;
  const kids = splitForms(form.slice(1, -1)).slice(1);
  const at = kids.findIndex((x) => /^\((catch|finally)[\s,]/.test(x));
  if (at <= 0 || kids.slice(at).some((x) => !/^\((catch|finally)[\s,]/.test(x))) return null;
  const nm = `__lw_try_${k}`;
  return [`(def ${nm} (fn* [] ${kids.slice(0, at).join(' ')}))`, `(try (${nm}) ${kids.slice(at).join(' ')})`];
}

// Instantiate compiled bytes against the running instance and run them.
export async function linkCompiled(hostExports, bytes) {
  const { instance } = await WebAssembly.instantiate(bytes, { host: hostExports });
  const run = instance.exports['lw run'];
  return (WebAssembly.promising ? WebAssembly.promising(run) : run)();
}

async function runForms(host, wasmBytes, src, mode) {
  const promising = (f) => (WebAssembly.promising ? WebAssembly.promising(f) : f);
  let ex;
  try {
    ex = (await WebAssembly.instantiate(await WebAssembly.compile(wasmBytes), host.imports())).exports;
  } catch (e) {
    host.emitText(2, `error: ${(e && e.message) || e}\n`);
    return host.finish(1, null).code;
  }
  host.mem = ex['lw mem'];
  const lgex = ex['lw lgex'];
  const P = 1024;
  const put = (text) => {
    const b = new TextEncoder().encode(text);
    const need = P + b.length;
    if (host.mem.buffer.byteLength < need) host.mem.grow(Math.ceil((need - host.mem.buffer.byteLength) / 65536));
    new Uint8Array(host.mem.buffer, P, b.length).set(b);
    return b.length;
  };
  const compile = async (text) => {
    const n = await promising(ex['lw compile'])(P, put(text));
    return new Uint8Array(host.mem.buffer, P, n).slice();
  };
  const evalText = async (text) => { await promising(ex['lw eval'])(P, put(text)); };
  // LG_HOST_TIMING=1: one line per compiled form on stderr
  const timing = !!process.env.LG_HOST_TIMING;
  let nform = 0;
  const run = async (text) => {
    const t0 = performance.now();
    const bytes = await compile(text);
    const t1 = performance.now();
    if (!timing) return linkCompiled(ex, bytes);
    const { instance } = await WebAssembly.instantiate(bytes, { host: ex });
    const t2 = performance.now();
    const r = await promising(instance.exports['lw run'])();
    fs.writeSync(2, `timing form=${nform++} bytes=${bytes.length} compile=${(t1 - t0).toFixed(2)}ms link=${(t2 - t1).toFixed(2)}ms run=${(performance.now() - t2).toFixed(2)}ms\n`);
    return r;
  };
  let phase = 'main';
  try {
    host.running = true;
    await promising(ex['lw main'])();
    let k = 0;
    for (const form of splitForms(src, opts.forms.replace(/^.*\//, ''))) {
      if (mode === 'eval') { phase = 'eval'; await evalText(form); continue; }
      const lifted = liftTry(form, k++);
      phase = 'compile';
      if (lifted) { await run(lifted[0]); phase = 'eval'; await evalText(lifted[1]); } else await run(form);
    }
    return host.finish(0, null).code;
  } catch (e) {
    host.outFd = 2;
    let captured = '';
    const prev = host.onOutput;
    host.onOutput = (t, fd) => { if (fd === 2) captured += t; prev(t, fd); };
    host.emitText(2, 'error: ');
    if (lgex && e instanceof WebAssembly.Exception && e.is(lgex)) ex['lw report'](e.getArg(lgex, 0));
    else if (ex['lw trap'] && ex['lw trap']()) { /* the module printed the trap's message */ }
    else host.emitText(2, String((e && e.message) || e));
    host.emitText(2, '\n');
    host.onOutput = prev;
    const named = phase === 'compile' && captured.startsWith('error: wasm.emit: ');
    return host.finish(named ? 4 : 1, captured.replace(/\n$/, '')).code;
  }
}
