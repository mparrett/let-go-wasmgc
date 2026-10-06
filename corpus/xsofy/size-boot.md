# P4.3: lane 5 size and boot (measured 2026-10-05, checks/size-boot.sh)

xsofy 0c38395, lg 4e769212 (`lg-4e76921230`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 528 KB | 149 KB | 177 KB | 4562 ms | 5767 ms |
| stock Go (lg -w, let-go 4e769212) | 9.13 MB | 6.64 MB | 6.74 MB | 8846 ms | 12729 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,920,368 B as emitted, 430,814 B after `wasm-opt -O3` (served), 115,218 B brotli, 137,158 B gzip.
Runs (ms): lane 5 title [4600, 4562, 4533, 4603, 4490], map [5817, 5767, 5750, 5806, 5692]; stock title [8846, 8449, 9049, 9324, 8754], map [12729, 12166, 12815, 13024, 12555].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
