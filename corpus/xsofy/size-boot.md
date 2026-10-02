# P4.3: lane 5 size and boot (measured 2026-10-01, checks/size-boot.sh)

xsofy 0c38395, lg 4e769212 (`lg-4e76921230`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 505 KB | 143 KB | 169 KB | 4477 ms | 5706 ms |
| stock Go (lg -w, let-go 4e769212) | 9.13 MB | 6.64 MB | 6.74 MB | 8817 ms | 12674 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,880,996 B as emitted, 416,741 B after `wasm-opt -O3` (served), 111,566 B brotli, 132,693 B gzip.
Runs (ms): lane 5 title [4488, 4536, 4477, 4432, 4475], map [5706, 5738, 5675, 5633, 5724]; stock title [9229, 8619, 8724, 8817, 8843], map [13075, 12480, 12470, 12714, 12674].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
