// node-host.mjs — lg-wasm-host.js under Node, for CI and for the three-host
// matrix in checks/browser-boot.sh.
//
//   node host/node-host.mjs <module.wasm> [--keys abq] [--env K=V ...] [--size 100x30] [--coalesce]
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
const opts = { wasm: null, keys: null, env: {}, cols: 80, rows: 24, coalesce: false };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--keys') opts.keys = args[++i];
  else if (a === '--env') { const [k, ...v] = args[++i].split('='); opts.env[k] = v.join('='); }
  else if (a === '--coalesce') opts.coalesce = true;
  else if (a === '--size') { const [c, r] = args[++i].split('x').map(Number); opts.cols = c; opts.rows = r; }
  else opts.wasm = a;
}
if (!opts.wasm) { console.error('usage: node-host.mjs <module.wasm> [--keys STR] [--env K=V] [--size CxR]'); process.exit(2); }

const host = new LgWasmHost({
  env: opts.env, cols: opts.cols, rows: opts.rows,
  // piped/--keys input arrives faster than a human types; queue all of it
  keyCapacity: Infinity,
  coalesceKeys: opts.coalesce,
  onOutput: (text, fd) => fs.writeSync(fd === 2 ? 2 : 1, text),
});
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
