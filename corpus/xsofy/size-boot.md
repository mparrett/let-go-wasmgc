# P4.3: lane 5 size and boot (measured 2026-10-01, checks/size-boot.sh)

xsofy 0c38395, lg 4e769212 (`lg-4e76921230`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 496 KB | 140 KB | 166 KB | 4588 ms | 6004 ms |
| stock Go (lg -w, let-go 4e769212) | 9.13 MB | 6.64 MB | 6.74 MB | 9380 ms | 13661 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,851,161 B as emitted, 408,330 B after `wasm-opt -O3` (served), 109,333 B brotli, 129,942 B gzip.
Runs (ms): lane 5 title [5034, 4588, 4655, 4573, 4455], map [6684, 6294, 6004, 5905, 5776]; stock title [10105, 11268, 9380, 8222, 7714], map [21221, 16751, 13661, 13171, 12632].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
