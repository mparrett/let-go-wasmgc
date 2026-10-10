// host/compile-worker.js — the compiler module runs here, off the page's
// thread (D206): a compile takes tens of seconds of straight computation
// (JSPI suspends only at imports), so on the main thread the tab would
// freeze and the elapsed counter stop. compile.html sends one init message
// ({module: a WebAssembly.Module, snapshot: lw-rt's D209 snapshot bytes,
// asmUrl: host/wat-asm's module}) and then one {source} per compile; this
// worker answers {type: 'out', fd, text} for every write the compiler makes
// and one {type: 'exit', code, error, ms, asmMs, wat, bytes}, bytes being
// the assembled module (null when the compile stopped). The two files the
// compiler reads (D211's LW_RT_SNAPSHOT and LW_ASSEMBLE_IN) come from a Map;
// env.assemble is wat-asm: wasm-tools' own text parser compiled to wasm, so
// the bytes are what `wasm-tools parse` gives for the same text.
import { LgWasmHost } from './lg-wasm-host.js';

const enc = new TextEncoder(), dec = new TextDecoder();
let module = null, snapshot = null, asm = null;

// host/wat-asm's ABI: the text into alloc_bytes' buffer, parse answers 1
// (the binary) or -1 (the error text), both read back through out_ptr/out_len
function assemble(text) {
  const p = asm.alloc_bytes(text.length);
  new Uint8Array(asm.memory.buffer).set(text, p);
  const rc = asm.parse(p, text.length);
  const out = new Uint8Array(asm.memory.buffer, asm.out_ptr(), asm.out_len()).slice();
  asm.free_bytes(p, text.length);
  if (rc !== 1) throw new Error(dec.decode(out));
  return out;
}

self.onmessage = async (e) => {
  const m = e.data;
  if (m.type === 'init') {
    module = m.module; snapshot = m.snapshot;
    try {
      const { instance } = await WebAssembly.instantiate(await (await fetch(m.asmUrl)).arrayBuffer(), {});
      asm = instance.exports;
      postMessage({ type: 'ready' });
    } catch (err) { postMessage({ type: 'ready', error: String((err && err.message) || err) }); }
    return;
  }
  if (m.type !== 'compile') return;
  const files = new Map([['/rt-snapshot.edn', snapshot], ['/prog.lg', enc.encode(m.source)]]);
  const t0 = performance.now();
  let wat = null, asmMs = null;
  const host = new LgWasmHost({
    env: { LW_HOST_FS: '1', LW_HOST_ASM: '1', LW_RT_SNAPSHOT: '/rt-snapshot.edn', LW_ASSEMBLE_IN: '/prog.lg' },
    argv: ['lg', 'compile.lg'],
    readFile: (p) => files.get(p),
    onOutput: (text, fd) => postMessage({ type: 'out', fd, text }),
    assemble: (text) => { const a = performance.now(); wat = text; const bytes = assemble(text); asmMs = performance.now() - a; return bytes; },
  });
  let r;
  try { r = await host.run(module); }
  catch (err) { postMessage({ type: 'exit', code: -1, error: String((err && err.message) || err), ms: performance.now() - t0, asmMs: null, wat: null, bytes: null }); return; }
  const bytes = host.assembled;
  postMessage({ type: 'exit', code: r.code, error: r.error ? String(r.error.message || r.error) : null, ms: performance.now() - t0,
    asmMs, wat: wat ? dec.decode(wat) : null, bytes }, bytes ? [bytes.buffer] : []);
};
