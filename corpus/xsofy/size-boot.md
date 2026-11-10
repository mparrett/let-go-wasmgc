# P4.3: lane 5 size and boot (measured 2026-11-09, checks/size-boot.sh)

xsofy feeb420, lg dbccbf0f (`lg-dbccbf0f63`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 545 KB | 153 KB | 181 KB | 4108 ms | 5213 ms |
| stock Go (lg -w, let-go dbccbf0f) | 9.34 MB | 6.80 MB | 6.91 MB | 4920 ms | 6836 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,915,587 B as emitted, 446,252 B after `wasm-opt -O3` (served), 118,366 B brotli, 140,719 B gzip.
Runs (ms): lane 5 title [4165, 4089, 4108, 4074, 4112], map [5251, 5209, 5213, 5192, 5228]; stock title [4919, 5040, 4966, 4919, 4920], map [6819, 7005, 6916, 6786, 6836].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
