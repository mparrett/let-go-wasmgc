# P4.3: lane 5 size and boot (measured 2026-10-02, checks/size-boot.sh)

xsofy 0c38395, lg 4e769212 (`lg-4e76921230`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 520 KB | 147 KB | 174 KB | 4586 ms | 5869 ms |
| stock Go (lg -w, let-go 4e769212) | 9.13 MB | 6.64 MB | 6.74 MB | 9240 ms | 13877 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,920,368 B as emitted, 430,814 B after `wasm-opt -O3` (served), 115,216 B brotli, 137,158 B gzip.
Runs (ms): lane 5 title [4582, 4598, 4586, 4609, 4532], map [5869, 5843, 5868, 5957, 6812]; stock title [9264, 8979, 9240, 8891, 9263], map [13877, 13058, 13487, 14975, 14129].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
