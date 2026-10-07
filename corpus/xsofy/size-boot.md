# P4.3: lane 5 size and boot (measured 2026-10-06, checks/size-boot.sh)

xsofy 0c38395, lg ff1e6dac (`lg-ff1e6dac76`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 528 KB | 149 KB | 177 KB | 4598 ms | 5865 ms |
| stock Go (lg -w, let-go ff1e6dac) | 9.15 MB | 6.66 MB | 6.75 MB | 8248 ms | 12539 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,920,529 B as emitted, 430,779 B after `wasm-opt -O3` (served), 115,060 B brotli, 137,155 B gzip.
Runs (ms): lane 5 title [4590, 4652, 4598, 4528, 4693], map [5840, 5865, 5952, 5824, 6067]; stock title [7370, 8585, 8248, 8913, 7896], map [11636, 12618, 12539, 13031, 12053].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
