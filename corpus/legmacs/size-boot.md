# P6.5: legmacs size and boot (measured 2026-10-02, checks/size-boot.sh --legmacs)

legmacs 187fea2 `main.lg`, lg 4e769212 (`lg-4e76921230`), headless Chromium via `checks/browser-boot.mjs --legmacs-time`, 5 runs per lane, medians.
Bundle = every file the page fetches except xterm.js + addon-fit, which both pages load from cdn.jsdelivr.net. Times are
from navigation: boot = first text in xterm, first frame = the *scratch* mode line on screen.

| lane | bundle raw | brotli -q 11 | gzip -9 | boot | first frame |
|---|---|---|---|---|---|
| lower-wasm (emitted) | 706 KB | 178 KB | 215 KB | 205 ms | 205 ms |
| stock Go (lg -w, let-go 4e769212) | 9.04 MB | 6.60 MB | 6.70 MB | does not boot | does not boot |

lower-wasm module alone: 2,265,456 B as emitted, 686,520 B after `wasm-opt -O3` (served), 170,699 B brotli, 206,570 B gzip.
Runs (ms) lower-wasm: boot [205, 247, 164, 242, 178], first frame [205, 247, 164, 242, 178].
stock boot: run 0: program ended before the first frame: error: getwd: not implemented on js --> main.lg:85:35 stack trace: at cwd (main.lg:85:35) at load-file-or-scratch (main.lg:156:45) at build-workspace (main.lg:168:19) at main (main.lg:179:27) 

The stock lane builds but does not boot legmacs: under js/wasm let-go's `os/cwd` raises "getwd: not implemented on js",
and main.lg calls it to set up the *scratch* buffer, so its boot column is empty and the comparison is bundle size only.
The lower-wasm runtime returns "" for `os/cwd` (D138: no file system in the module).
