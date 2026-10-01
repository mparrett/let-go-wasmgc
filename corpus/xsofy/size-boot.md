# P4.3: lane 5 size and boot (measured 2026-10-01, checks/size-boot.sh)

xsofy 0c38395, lg 4e769212 (`lg-4e76921230`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 497 KB | 140 KB | 166 KB | 4473 ms | 5748 ms |
| stock Go (lg -w, let-go 4e769212) | 9.13 MB | 6.64 MB | 6.74 MB | 11649 ms | 18213 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,844,281 B as emitted, 408,609 B after `wasm-opt -O3` (served), 109,283 B brotli, 129,668 B gzip.
Runs (ms): lane 5 title [4708, 4521, 4473, 4381, 4409], map [6245, 5748, 5723, 5579, 5870]; stock title [15894, 8649, 11649, 13328, 8230], map [32902, 21753, 18213, 17904, 15442].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
