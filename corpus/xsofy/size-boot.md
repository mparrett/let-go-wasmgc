# P4.3: lane 5 size and boot (measured 2026-10-07, checks/size-boot.sh)

xsofy 0c38395, lg ff1e6dac (`lg-ff1e6dac76`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 528 KB | 149 KB | 176 KB | 4547 ms | 5712 ms |
| stock Go (lg -w, let-go ff1e6dac) | 9.15 MB | 6.66 MB | 6.75 MB | 6390 ms | 9220 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,868,762 B as emitted, 430,817 B after `wasm-opt -O3` (served), 114,983 B brotli, 137,133 B gzip.
Runs (ms): lane 5 title [4547, 4509, 4577, 4524, 4610], map [5712, 5693, 5811, 5675, 5777]; stock title [6399, 6353, 6417, 6390, 6170], map [9296, 9220, 9117, 9140, 9453].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
