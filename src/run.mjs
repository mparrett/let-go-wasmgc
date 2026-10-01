// Run a lower-wasm module like lg runs a program (DECISIONS D11/D12):
//   node src/run.mjs <module.wasm>
// Program output goes to stdout through the env.print_* imports; an uncaught
// lg exception, wasm trap or host error prints `error: <message>` to stderr
// and exits 1.
//
// The module runs on a worker thread because the main thread's ~1 MB stack
// overflows near 10k non-tail lg frames, while native lg (growable Go stacks)
// recurses into the millions; 256 MB covers 3M int frames (measured).
import fs from 'node:fs';
import { Worker, isMainThread, workerData } from 'node:worker_threads';

if (isMainThread) {
  const w = new Worker(new URL(import.meta.url), {
    workerData: process.argv[2], resourceLimits: { stackSizeMb: 256 },
  });
  w.on('error', (e) => { fs.writeSync(2, `error: ${e && e.message || e}\n`); process.exitCode = 1; });
  w.on('exit', (c) => { if (c) process.exitCode = c; });
} else {
  const chunks = [];
  let pending = 0;
  let fd = 1;
  const flush = () => { if (chunks.length) { fs.writeSync(fd, Buffer.concat(chunks)); chunks.length = 0; pending = 0; } };
  const emit = (buf) => { chunks.push(buf); pending += buf.length; if (pending > 1 << 16) flush(); };

  let mem;
  const env = {
    print_i64: (v) => emit(Buffer.from(String(v))),
    // copy: the module reuses the scratch region for the next string
    print_str: (ptr, len) => emit(Buffer.from(new Uint8Array(mem.buffer, ptr, len))),
    print_nl: () => emit(Buffer.from('\n')),
  };

  const { instance } = await WebAssembly.instantiate(fs.readFileSync(workerData), { env });
  mem = instance.exports.mem;
  const lgex = instance.exports.lgex;
  try {
    instance.exports._main();
    flush();
  } catch (e) {
    flush();
    fd = 2;
    emit(Buffer.from('error: '));
    if (e instanceof WebAssembly.Exception && e.is(lgex)) {
      // the module formats its own exception values (message / pr-str)
      instance.exports._report(e.getArg(lgex, 0));
    } else {
      emit(Buffer.from(String((e && e.message) || e)));
    }
    emit(Buffer.from('\n'));
    flush();
    process.exit(1);
  }
}
