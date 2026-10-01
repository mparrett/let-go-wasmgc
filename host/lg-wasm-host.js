// lg-wasm-host.js — runs a lower-wasm module in a browser or under Node
// (P4.0; the import ABI is host/ABI.md, proposed as D88).
//
//   const host = new LgWasmHost({ onOutput: (text, fd) => ..., env: {...} });
//   const r = await host.run(bytesOrModule);   // { code, error, tFirstOutput, tTotal }
//   host.sendInput('a'); host.setSize(100, 30); host.closeInput();
//
// Blocking imports (env.sleep, term.read_key) are WebAssembly.Suspending and
// `lw main` runs under WebAssembly.promising, so the module blocks while the
// JS event loop keeps running. That is why input needs no SharedArrayBuffer
// and therefore no cross-origin isolation (ABI.md, "COI").

const enc = new TextEncoder();

// let-go's SAB ring (pkg/rt/wasm/lg-host-core.js) holds 8 keys of at most
// 16 UTF-8 bytes each and drops the rest; mirrored so held-key behaviour does
// not change between the Go lane and this one.
export const KEY_CAPACITY = 8;
export const MAX_KEY_LEN = 16;

export const hasJSPI = typeof WebAssembly !== 'undefined'
  && typeof WebAssembly.Suspending === 'function' && typeof WebAssembly.promising === 'function';

const now = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());

export class LgWasmHost {
  constructor({ onOutput = () => {}, env = {}, cols = 80, rows = 24, keyCapacity = KEY_CAPACITY } = {}) {
    this.onOutput = onOutput;
    this.keyCapacity = keyCapacity;
    this.envMap = env;
    this.cols = cols; this.rows = rows;
    this.keys = [];          // queued keys, each a Uint8Array (one sendInput call = one key)
    this.keyWaiter = null;   // resolve fn of a parked read_key
    this.inputClosed = false;
    this.running = false;
    // one streaming decoder per fd so a UTF-8 sequence split across two
    // writes still decodes
    this.decoders = { 1: new TextDecoder('utf-8'), 2: new TextDecoder('utf-8') };
    this.mem = null;
    this.tStart = 0; this.tFirstOutput = null;
  }

  // ---- host → module (the LetGoHost side) ---------------------------------
  sendInput(s) {
    if (!this.running || this.inputClosed) return false;   // pre-boot keys dropped, as in let-go
    const b = enc.encode(s);
    if (b.length === 0 || b.length > MAX_KEY_LEN) return false;
    if (this.keyWaiter) { const w = this.keyWaiter; this.keyWaiter = null; w(b); return true; }
    if (this.keys.length >= this.keyCapacity) return false;
    this.keys.push(b);
    return true;
  }
  setSize(cols, rows) { this.cols = cols | 0; this.rows = rows | 0; }
  closeInput() {
    this.inputClosed = true;
    if (this.keyWaiter) { const w = this.keyWaiter; this.keyWaiter = null; w(null); }
  }

  // ---- output ---------------------------------------------------------------
  bytes(ptr, len) { return new Uint8Array(this.mem.buffer, ptr, len); }
  emitBytes(fd, b) {
    if (this.tFirstOutput === null) this.tFirstOutput = now() - this.tStart;
    const text = this.decoders[fd === 2 ? 2 : 1].decode(b, { stream: true });
    if (text) this.onOutput(text, fd === 2 ? 2 : 1);
  }
  emitText(fd, s) { this.emitBytes(fd, enc.encode(s)); }

  imports() {
    const h = this;
    // print_* follow the "current" fd: 1 normally, 2 while the module formats
    // an uncaught error (run.mjs does the same with its `fd` variable)
    const env = {
      print_i64: (v) => h.emitText(h.outFd, String(v)),
      print_str: (ptr, len) => h.emitBytes(h.outFd, h.bytes(ptr, len)),
      print_nl: () => h.emitText(h.outFd, '\n'),
      write: (fd, ptr, len) => { h.emitBytes(fd === 2 ? 2 : h.outFd, h.bytes(ptr, len)); return len; },
      sleep: h.suspending((ms) => {
        const n = Number(ms);
        return new Promise((r) => setTimeout(r, n > 0 ? n : 0));
      }),
      nanotime: () => BigInt(Math.round(now() * 1e6)),
      // Not imported by any module yet (host-getenv is stubbed to nil in the
      // backend); defined so the runtime can switch to it without a host
      // change. Copies the value into [buf, buf+cap); returns its byte length
      // (> cap means "retry with a bigger buffer") or -1 when unset.
      getenv: (nptr, nlen, buf, cap) => {
        const name = new TextDecoder().decode(h.bytes(nptr, nlen));
        if (!Object.prototype.hasOwnProperty.call(h.envMap, name)) return -1;
        const v = enc.encode(String(h.envMap[name]));
        if (v.length <= cap) h.bytes(buf, v.length).set(v);
        return v.length;
      },
    };
    const term = {
      // Blocks until a key arrives. Copies its UTF-8 bytes (≤ 16) into
      // [buf, buf+cap) and returns the count; 0 = end of input (read-key → nil).
      read_key: h.suspending((buf, cap) => {
        const put = (b) => {
          if (b === null) return 0;
          const n = Math.min(b.length, cap);
          // re-read mem.buffer: memory may have grown while we were suspended
          new Uint8Array(h.mem.buffer, buf, n).set(b.subarray(0, n));
          return n;
        };
        if (h.keys.length) return put(h.keys.shift());
        if (h.inputClosed) return 0;
        return new Promise((r) => { h.keyWaiter = r; }).then(put);
      }),
      key_pending: () => (h.keys.length ? 1 : 0),
      size: () => [h.cols, h.rows],
      // term/write is (write *out* s) natively; a runtime may route it here or
      // through env.write fd 1, the bytes end up in the same stream either way
      write: (ptr, len) => { h.emitBytes(h.outFd, h.bytes(ptr, len)); return len; },
    };
    return { env, term };
  }

  // Suspending when JSPI exists; otherwise a function that refuses to block,
  // so a host without JSPI fails loudly instead of returning a Promise as an
  // i32 (V8 would coerce it to 0 and the program would silently run on).
  suspending(fn) {
    if (hasJSPI) return new WebAssembly.Suspending(fn);
    return (...a) => {
      const r = fn(...a);
      if (r && typeof r.then === 'function') throw new Error('lower-wasm host: blocking import needs JSPI (WebAssembly.Suspending)');
      return r;
    };
  }

  async run(src) {
    this.tStart = now(); this.tFirstOutput = null; this.outFd = 1;
    const mod = src instanceof WebAssembly.Module ? src : await WebAssembly.compile(src);
    let instance;
    try {
      instance = await WebAssembly.instantiate(mod, this.imports());
    } catch (e) {
      // a trap in the start function (_rt_init) surfaces here
      this.emitText(2, `error: ${(e && e.message) || e}\n`);
      return this.finish(1, String((e && e.message) || e));
    }
    const ex = instance.exports;
    this.mem = ex['lw mem'];
    const lgex = ex['lw lgex'];
    const main = hasJSPI ? WebAssembly.promising(ex['lw main']) : ex['lw main'];
    this.running = true;
    try {
      await main();
      return this.finish(0, null);
    } catch (e) {
      // identical to src/run.mjs: `error: ` + the module's own report
      this.outFd = 2;
      let captured = '';
      const prev = this.onOutput;
      this.onOutput = (t, fd) => { if (fd === 2) captured += t; prev(t, fd); };
      this.emitText(2, 'error: ');
      if (lgex && e instanceof WebAssembly.Exception && e.is(lgex)) {
        ex['lw report'](e.getArg(lgex, 0));
      } else if (ex['lw trap'] && ex['lw trap']()) {
        // wasm/trap: the module printed the reference impl's message
      } else {
        this.emitText(2, String((e && e.message) || e));
      }
      this.emitText(2, '\n');
      this.onOutput = prev;
      return this.finish(1, captured.replace(/\n$/, ''));
    }
  }

  finish(code, error) {
    this.running = false;
    for (const fd of [1, 2]) {
      const tail = this.decoders[fd].decode();
      if (tail) this.onOutput(tail, fd);
    }
    return { code, error, tFirstOutput: this.tFirstOutput, tTotal: now() - this.tStart };
  }
}
