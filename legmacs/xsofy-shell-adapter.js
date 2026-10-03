// xsofy-shell-adapter.js — window.LetGoHost backed by lg-wasm-host.js, so
// xsofy/tools/xsofy-shell.html runs a lower-wasm module unchanged (P4.1).
//
// A CLASSIC script, loaded before the shell is injected: the shell calls
// window.LetGoHost.onReady at parse time, so the surface must exist before
// any module script could run. It takes the place of let-go's lg-host-core.js
// in a `lg -w -w-shell none` bundle and keeps its shape: onReady(cb),
// onOutput(cb), onEmit(cb), sendInput(str), setSize(c, r). The host module is
// pulled in with a dynamic import.
//
// ?module=<url> names the .wasm (default module.wasm). window.__lgw is what
// checks/browser-boot.mjs reads back. A page may set window.LW_HOST_OPTIONS
// (extra LgWasmHost options, e.g. {wakeOnResize: true} on host/legmacs.html)
// before this script; xsofy's page sets none. Despite the name nothing here
// is xsofy-specific: host/legmacs.html runs let-go's stock xterm shell on it.
(function () {
  let outputSink = null; const outputBuffer = [];
  let readyCb = null, readyMode = null;
  let emitSink = (name, data) => window.dispatchEvent(new CustomEvent(name, { detail: data }));
  let host = null;
  let sized = null;                      // resolves on the shell's first setSize
  const firstSize = new Promise((r) => { sized = r; });
  const url = new URLSearchParams(location.search).get('module') || 'module.wasm';
  const result = window.__lgw = { module: url, stdout: '', stderr: '', done: false,
    readyMode: null, size: null, sent: 0, dropped: 0 };

  window.LetGoHost = {
    onReady(cb) { readyCb = cb; if (readyMode !== null) cb(readyMode); },
    onOutput(cb) { outputSink = cb; for (const s of outputBuffer.splice(0)) cb(s); },
    onEmit(cb) { emitSink = cb; },
    sendInput(s) {
      const ok = host ? host.sendInput(s) : false;
      if (ok) result.sent++; else result.dropped++;
      return ok;
    },
    setSize(c, r) {
      result.size = [c | 0, r | 0];
      if (host) host.setSize(c, r);
      sized();
    },
  };
  const output = (s) => {
    if (result.tShellFirstOutput === undefined) result.tShellFirstOutput = performance.now();
    if (outputSink) outputSink(s); else outputBuffer.push(s);
  };
  const ready = (mode) => { readyMode = result.readyMode = mode; if (readyCb) readyCb(mode); };

  const base = document.currentScript.src;
  (async () => {
    try {
      const { LgWasmHost, hasJSPI } = await import(new URL('lg-wasm-host.js', base).href);
      result.jspi = hasJSPI; result.coi = self.crossOriginIsolated === true;
      const bytes = await (await fetch(url)).arrayBuffer();
      host = new LgWasmHost({
        ...(window.LW_HOST_OPTIONS || {}),
        urlParams: new URLSearchParams(location.search),
        // let-go's main-thread _lgEmit: parse the JSON, hand it to the sink,
        // which by default fires the window CustomEvent the shell listens for
        onEmit(name, json) {
          try { emitSink(name, JSON.parse(json)); } catch (e) { console.error('emit', name, e); }
        },
        onOutput(text, fd) {
          if (fd === 2) result.stderr += text; else result.stdout += text;
          output(text);
        },
      });
      // 'worker', not 'jspi': xsofy-shell.html binds setSize / onData /
      // sendInput only when mode === 'worker' (D90, host/ABI.md). Input here
      // is a parked JSPI stack, not let-go's worker + SAB ring, but the shell
      // only needs to know that input is live.
      ready('worker');
      // The shell opens xterm (after awaiting its font) and only then calls
      // setSize. Start the program after that, or a fast module reads the
      // 80x24 default before the real grid exists. A shell that never calls
      // setSize gets the default after 2 s.
      await Promise.race([firstSize, new Promise((r) => setTimeout(r, 2000))]);
      result.tMainStart = performance.now();
      const r = await host.run(bytes);
      Object.assign(result, r, { tDone: performance.now() });
    } catch (e) {
      Object.assign(result, { code: -1, error: String((e && e.message) || e) });
      output(`\r\nlower-wasm host error: ${result.error}\r\n`);
    }
    result.done = true;
  })();
})();
