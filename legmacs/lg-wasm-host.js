// lg-wasm-host.js — runs a lower-wasm module in a browser or under Node
// (P4.0; the import ABI is host/ABI.md, proposed as D88).
//
//   const host = new LgWasmHost({ onOutput: (text, fd) => ..., env: {...} });
//   const r = await host.run(bytesOrModule);   // { code, error, tFirstOutput, tTotal }
//   host.sendInput('a'); host.setSize(100, 30); host.closeInput();
//
// Keys follow let-go's ring (pkg/rt/wasm/lg-host-core.js producer,
// pkg/rt/keysource_js_wasm.go consumer): sendInput drops empty, >16-byte and
// over-capacity keys; read_key coalesces a run of identical queued keys into
// one read (D98) unless the host is built with coalesceKeys: false.
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

// Native let-go wakes a parked read-key on SIGWINCH by returning BEL
// (pkg/rt/keysource.go terminalWakeKey), so a program blocked on input can
// re-measure term/size and redraw; legmacs relies on it (keys.lg maps it to
// a harmless C-g). let-go's wasm ring has no wake (lg-host-core.js: "wake()
// is intentionally NOT in this slice"), so a stock-Go page only redraws on
// the next real key. wakeOnResize: true gives this host the native
// behaviour; it is off by default so xsofy's lane stays identical to the
// stock lane (lane5.sh compares them).
export const WAKE_KEY = new Uint8Array([7]);

export const hasJSPI = typeof WebAssembly !== 'undefined'
  && typeof WebAssembly.Suspending === 'function' && typeof WebAssembly.promising === 'function';

// The message a person sees when the browser lacks JSPI; the raw cause
// (a blocking import returned a Promise) is kept for the console.
export function noJSPIMessage() {
  const ua = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
  const ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && typeof navigator !== 'undefined' && navigator.maxTouchPoints > 1);
  const which = ios ? 'iOS (every browser there uses Safari\'s engine)' : /Firefox\//.test(ua) ? 'Firefox' : /Safari\//.test(ua) && !/Chrom/.test(ua) ? 'Safari' : /Edg\//.test(ua) ? 'Edge' : /Chrom/.test(ua) ? 'Chrome' : 'this browser';
  const ver = ios ? '' : (ua.match(/(?:Chrome|Firefox|Version|Edg)\/(\d+)/) || [])[1];
  return `this page needs WebAssembly JSPI (JavaScript Promise Integration), which ${which}${ver ? ' ' + ver : ''} does not provide. `
    + 'Chrome and Edge 137 or newer on desktop ship it; Firefox, Safari and iOS do not yet. '
    + '(A blocking import returned a Promise with WebAssembly.Suspending undefined.)';
}

const sameBytes = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

const now = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());

export class LgWasmHost {
  constructor({ onOutput = () => {}, env = {}, cols = 80, rows = 24, keyCapacity = KEY_CAPACITY, coalesceKeys = true,
    onEmit = () => {}, urlParams = null, argv = ['lg'], wakeOnResize = false } = {}) {
    this.argv = argv;              // os/args (D115): env.argc / env.arg
    this.wakeOnResize = wakeOnResize;
    this.onOutput = onOutput;
    this.onEmit = onEmit;          // (name, dataJson) for js/emit
    this.urlParams = urlParams;    // URLSearchParams for js/url-param; null off-browser
    this.keyCapacity = keyCapacity;
    this.coalesceKeys = coalesceKeys;
    this.envMap = env;
    this.cols = cols; this.rows = rows;
    this.keys = [];          // queued keys, each a Uint8Array (one sendInput call = one key)
    this.keyWaiter = null;   // wakes a parked read_key (it then reads the queue itself)
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
    if (this.keys.length >= this.keyCapacity) return false;
    // Always queue, then wake. The parked read_key resumes in a later
    // microtask and takes from the queue, so keys sent in the same task (an
    // auto-repeat burst, a paste split into keys) are all queued by the time
    // it looks and coalesce, as they would in let-go's ring.
    this.keys.push(b);
    this.wake();
    return true;
  }
  wake() { if (this.keyWaiter) { const w = this.keyWaiter; this.keyWaiter = null; w(); } }
  setSize(cols, rows) {
    const changed = (cols | 0) !== this.cols || (rows | 0) !== this.rows;
    this.cols = cols | 0; this.rows = rows | 0;
    // a wake is a key like any other: same capacity, same coalescing (two
    // resizes before the program reads are one wake, as one SIGWINCH is)
    if (changed && this.wakeOnResize && this.running && !this.inputClosed && this.keys.length < this.keyCapacity) {
      this.keys.push(WAKE_KEY);
      this.wake();
    }
  }
  closeInput() {
    this.inputClosed = true;
    this.wake();
  }

  // The consumer half of keysource_js_wasm.go:78-127: a head key outside
  // 1..16 bytes is drained alone and reads as nil; otherwise every following
  // key with the same bytes is drained with it (one read for a held key).
  // sendInput already refuses bad lengths, as let-go's producer does, so the
  // first branch only fires if something else fills the queue; D98 makes it
  // part of the read_key contract regardless.
  takeKey() {
    const k = this.keys.shift();
    if (k.length < 1 || k.length > MAX_KEY_LEN) return null;
    if (this.coalesceKeys) {
      while (this.keys.length && sameBytes(this.keys[0], k)) this.keys.shift();
    }
    return k;
  }

  // ---- output ---------------------------------------------------------------
  bytes(ptr, len) { return new Uint8Array(this.mem.buffer, ptr, len); }
  str(ptr, len) { return new TextDecoder().decode(this.bytes(ptr, len)); }
  // copy a string into [buf, buf+cap); returns its byte length (> cap means
  // nothing was copied and the caller retries with a bigger buffer)
  copyOut(s, buf, cap) {
    const v = enc.encode(s);
    if (v.length <= cap) this.bytes(buf, v.length).set(v);
    return v.length;
  }
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
      // os/getenv over `env` ({} in the browser, process.env under node).
      // Copies the value into [buf, buf+cap); returns its byte length
      // (> cap means "retry with a bigger buffer") or -1 when unset.
      getenv: (nptr, nlen, buf, cap) => {
        const name = h.str(nptr, nlen);
        if (!Object.prototype.hasOwnProperty.call(h.envMap, name)) return -1;
        return h.copyOut(String(h.envMap[name]), buf, cap);
      },
      // js/emit and js/url-param (xsofy uses both: the shell's title/quest/
      // stats arrive as xsofy/* events; ?seed= etc. as URL params), imported
      // since P4.1-backend (D100). emit hands the name and the JSON text
      // the runtime serialised (let-go's _lgEmit(name, dataJson) shape).
      // url_param has getenv's contract; -1 off-browser, as native's nil.
      // os/args (D115): getenv's copy contract per argument
      argc: () => h.argv.length,
      arg: (i, buf, cap) => h.copyOut(String(h.argv[i] ?? ''), buf, cap),
      emit: (nptr, nlen, dptr, dlen) => { h.onEmit(h.str(nptr, nlen), h.str(dptr, dlen)); },
      url_param: (nptr, nlen, buf, cap) => {
        const v = h.urlParams ? h.urlParams.get(h.str(nptr, nlen)) : null;
        return v === null ? -1 : h.copyOut(v, buf, cap);
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
        const next = () => {
          if (h.keys.length) return put(h.takeKey());
          if (h.inputClosed) return 0;
          return new Promise((r) => { h.keyWaiter = r; }).then(next);
        };
        return next();
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
      if (r && typeof r.then === 'function') throw new Error(noJSPIMessage());
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
