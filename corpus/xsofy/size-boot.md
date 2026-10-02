# P4.3: lane 5 size and boot (measured 2026-10-02, checks/size-boot.sh)

xsofy 0c38395, lg 4e769212 (`lg-4e76921230`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 520 KB | 147 KB | 174 KB | 4571 ms | 6111 ms |
| stock Go (lg -w, let-go 4e769212) | 9.13 MB | 6.64 MB | 6.74 MB | 8767 ms | 12767 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,920,330 B as emitted, 430,781 B after `wasm-opt -O3` (served), 115,109 B brotli, 137,134 B gzip.
Runs (ms): lane 5 title [4975, 4571, 4474, 4432, 4654], map [6564, 5879, 5774, 6116, 6111]; stock title [10335, 8829, 8767, 8514, 7625], map [14405, 12661, 12767, 12198, 15653].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
