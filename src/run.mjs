// Run a lower-wasm module like lg runs a program (DECISIONS D11/D12):
//   node src/run.mjs <module.wasm>
// Program output goes to stdout through the env.print_* imports; an uncaught
// wasm exception or trap prints `error: <message>` and exits 1.
import fs from 'node:fs';

const chunks = [];
let pending = 0;
const flush = () => { if (chunks.length) { fs.writeSync(1, Buffer.concat(chunks)); chunks.length = 0; pending = 0; } };
const emit = (buf) => { chunks.push(buf); pending += buf.length; if (pending > 1 << 16) flush(); };

let mem;
const env = {
  print_i64: (v) => emit(Buffer.from(String(v))),
  // copy: the module reuses the scratch region for the next string
  print_str: (ptr, len) => emit(Buffer.from(new Uint8Array(mem.buffer, ptr, len))),
  print_nl: () => emit(Buffer.from('\n')),
};

const { instance } = await WebAssembly.instantiate(fs.readFileSync(process.argv[2]), { env });
mem = instance.exports.mem;
try {
  instance.exports._main();
  flush();
} catch (e) {
  flush();
  // lg's message for checked-arithmetic overflow (pkg/vm/numbers.go)
  const msg = (e instanceof WebAssembly.Exception && e.is(instance.exports.overflow))
    ? 'integer overflow' : (e && e.message) || String(e);
  fs.writeSync(2, `error: ${msg}\n`);
  process.exit(1);
}
