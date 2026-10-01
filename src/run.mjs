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
    workerData: { wasm: process.argv[2], argv: process.argv.slice(3) }, resourceLimits: { stackSizeMb: 256 },
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
  const argv = ['lg', ...workerData.argv];
  const env = {
    print_i64: (v) => emit(Buffer.from(String(v))),
    // copy: the module reuses the scratch region for the next string
    print_str: (ptr, len) => emit(Buffer.from(new Uint8Array(mem.buffer, ptr, len))),
    print_nl: () => emit(Buffer.from('\n')),
    // the host intrinsics (rt/wasm/INTRINSICS.md): fd 1 is the program's
    // stdout stream, fd 2 goes straight to stderr
    write: (fd, ptr, len) => {
      const b = Buffer.from(new Uint8Array(mem.buffer, ptr, len));
      if (fd === 1) emit(b); else { flush(); fs.writeSync(2, b); }
      return len;
    },
    sleep: (ms) => { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, Number(ms)); },
    nanotime: () => process.hrtime.bigint(),
    // os/args (P3.2, proposed ABI addition): `node run.mjs m.wasm prog.lg a b`
    // reads as native's [lg-path "prog.lg" "a" "b"]; arg follows getenv's
    // contract (returns the byte length, copies only when it fits in cap)
    // D100 (P4.1): js/emit and js/url-param. Native lg off the browser
    // emits nowhere and has no page URL, so: drop, and -1 (absent -> nil)
    emit: () => {},
    url_param: () => -1,
    argc: () => argv.length,
    arg: (i, buf, cap) => {
      const b = Buffer.from(argv[i] ?? '');
      if (b.length <= cap) new Uint8Array(mem.buffer, buf, b.length).set(b);
      return b.length;
    },
  };

  // D97 term imports: node has no terminal input here, so this host reads as
  // the runtime's reference does with no input queued: end of input, nothing
  // pending, the 80x24 default (host/ is the interactive JSPI host)
  // P3.2: size (-1, -1) = no terminal: this runner mirrors native lg run
  // headless, whose term/size is nil off a TTY (term.go), and xsofy keys
  // its title-card animation on that nil (lw-ext/term-size-v)
  const term = { read_key: () => 0, key_pending: () => 0, size: () => [-1, -1] };
  const { instance } = await WebAssembly.instantiate(fs.readFileSync(workerData.wasm), { env, term });
  // the backend's own exports have names no lg symbol can spell (a space),
  // so a program defn exported under its lg name never collides (P1.7 bug-09)
  const ex = instance.exports;
  mem = ex['lw mem'];
  const lgex = ex['lw lgex'];
  try {
    ex['lw main']();
    flush();
  } catch (e) {
    flush();
    fd = 2;
    emit(Buffer.from('error: '));
    if (e instanceof WebAssembly.Exception && e.is(lgex)) {
      // the module formats its own exception values (message / pr-str)
      ex['lw report'](e.getArg(lgex, 0));
    } else if (ex['lw trap'] && ex['lw trap']()) {
      // wasm/trap: the module printed the reference impl's message
    } else {
      emit(Buffer.from(String((e && e.message) || e)));
    }
    emit(Buffer.from('\n'));
    flush();
    process.exit(1);
  }
}
