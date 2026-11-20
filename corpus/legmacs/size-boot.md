# P6.5: legmacs size and boot (measured 2026-11-19, checks/size-boot.sh --legmacs)

legmacs 187fea2 `main.lg`, lg dbccbf0f (`lg-dbccbf0f63`), headless Chromium via `checks/browser-boot.mjs --legmacs-time`, 5 runs per lane, medians.
Bundle = every file the page fetches except xterm.js + addon-fit, which both pages load from cdn.jsdelivr.net. Times are
from navigation: boot = first text in xterm, first frame = the *scratch* mode line on screen.

| lane | bundle raw | brotli -q 11 | gzip -9 | boot | first frame |
|---|---|---|---|---|---|
| lower-wasm (emitted) | 744 KB | 186 KB | 225 KB | 170 ms | 170 ms |
| stock Go (lg -w, let-go dbccbf0f) | 9.22 MB | 6.74 MB | 6.84 MB | does not boot | does not boot |

lower-wasm module alone: 2,320,809 B as emitted, 715,461 B after `wasm-opt -O3` (served), 176,496 B brotli, 213,354 B gzip.
Runs (ms) lower-wasm: boot [192, 172, 170, 166, 160], first frame [192, 172, 170, 166, 160].
stock boot: run 0: program ended before the first frame: error: getwd: not implemented on js --> main.lg:85:35 stack trace: at cwd (main.lg:85:35) at load-file-or-scratch (main.lg:156:45) at build-workspace (main.lg:168:19) at main (main.lg:179:27) 

The stock lane builds but does not boot legmacs: under js/wasm let-go's `os/cwd` raises "getwd: not implemented on js",
and main.lg calls it to set up the *scratch* buffer, so its boot column is empty and the comparison is bundle size only.
The lower-wasm runtime returns "" for `os/cwd` (D138: no file system in the module).
