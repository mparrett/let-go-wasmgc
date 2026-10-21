# P4.3: lane 5 size and boot (measured 2026-10-21, checks/size-boot.sh)

xsofy 0c38395, lg e9789b7d (`lg-e9789b7d53`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 530 KB | 150 KB | 177 KB | 5037 ms | 6240 ms |
| stock Go (lg -w, let-go e9789b7d) | 9.16 MB | 6.66 MB | 6.76 MB | 9092 ms | 13177 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,871,675 B as emitted, 430,808 B after `wasm-opt -O3` (served), 115,354 B brotli, 137,331 B gzip.
Runs (ms): lane 5 title [5098, 5037, 4988, 5018, 5065], map [6315, 6240, 6159, 6218, 6282]; stock title [9092, 8887, 9214, 9210, 8984], map [13090, 13187, 13363, 13177, 13037].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
