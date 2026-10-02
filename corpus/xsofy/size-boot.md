# P4.3: lane 5 size and boot (measured 2026-10-02, checks/size-boot.sh)

xsofy 0c38395, lg 4e769212 (`lg-4e76921230`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 513 KB | 145 KB | 172 KB | 4466 ms | 5751 ms |
| stock Go (lg -w, let-go 4e769212) | 9.13 MB | 6.64 MB | 6.74 MB | 8043 ms | 12405 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,920,676 B as emitted, 423,669 B after `wasm-opt -O3` (served), 113,626 B brotli, 135,280 B gzip.
Runs (ms): lane 5 title [4466, 4609, 4435, 4580, 4404], map [5751, 5877, 5685, 5764, 5689]; stock title [8020, 7848, 9252, 8382, 8043], map [12405, 11656, 13170, 12944, 11942].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
