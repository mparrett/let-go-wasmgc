// node checks/bench-fib.mjs <backend.wasm> <probe.wasm> [reps]
// fib(32) through each module's exported fib(i64) in ONE process, as
// ../emit-wasm-probe/ext/bench.mjs times it: 3 warm-ups each, then `reps`
// timed runs (interleaved backend/probe so drift hits both), median per module.
import fs from 'node:fs';
const [, , backendFile, probeFile, repsArg] = process.argv;
const reps = Number(repsArg ?? 5);
const nop = () => {};
const load = async (f) => (await WebAssembly.instantiate(fs.readFileSync(f),
  { env: { print_i64: nop, print_str: nop, print_nl: nop } })).instance.exports;
const mods = { backend: await load(backendFile), probe: await load(probeFile) };
const run = (ex) => ex.fib(32n);
for (const ex of Object.values(mods)) for (let i = 0; i < 3; i++) run(ex);
const times = { backend: [], probe: [] };
const result = {};
for (let i = 0; i < reps; i++) {
  for (const [k, ex] of Object.entries(mods)) {
    const t = performance.now(); result[k] = run(ex); times[k].push(performance.now() - t);
  }
}
const med = (a) => [...a].sort((x, y) => x - y)[a.length >> 1];
for (const k of Object.keys(mods)) {
  if (Number(result[k]) !== 2178309) { console.log(`${k}: wrong result ${result[k]}`); process.exit(1); }
  console.log(`${k.padEnd(8)} fib(32)=${result[k]} median=${med(times[k]).toFixed(2)}ms all=[${times[k].map((t) => t.toFixed(1)).join(' ')}]`);
}
const ratio = med(times.backend) / med(times.probe);
console.log(`ratio backend/probe = ${ratio.toFixed(3)} (limit 1.5)`);
process.exit(ratio <= 1.5 ? 0 : 1);
