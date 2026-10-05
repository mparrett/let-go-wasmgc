# P4.3: lane 5 size and boot (measured 2026-10-03, checks/size-boot.sh)

xsofy 0c38395, lg 4e769212 (`lg-4e76921230`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 521 KB | 147 KB | 174 KB | 4060 ms | 5144 ms |
| stock Go (lg -w, let-go 4e769212) | 9.13 MB | 6.64 MB | 6.74 MB | 5026 ms | 7209 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,920,368 B as emitted, 430,783 B after `wasm-opt -O3` (served), 115,153 B brotli, 137,162 B gzip.
Runs (ms): lane 5 title [4153, 4055, 4058, 4060, 4061], map [5236, 5139, 5155, 5144, 5144]; stock title [4901, 5026, 5174, 5205, 4912], map [6987, 7209, 7342, 7409, 6963].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
