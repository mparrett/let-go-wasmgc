# P4.3: lane 5 size and boot (measured 2026-10-02, checks/size-boot.sh)

xsofy 0c38395, lg 4e769212 (`lg-4e76921230`), headless Chromium via zz-boot-time-probe.mjs, 5 runs per lane, medians.
Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself
animates for part of the time-to-title on every lane.

| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 518 KB | 146 KB | 173 KB | 4511 ms | 5691 ms |
| stock Go (lg -w, let-go 4e769212) | 9.13 MB | 6.64 MB | 6.74 MB | 8507 ms | 12327 ms |
| TinyGo (recorded 2026-09-20, not re-run) | 2.3 MB | 1.27 MB (floor build) | 1.70 MB (floor build) | 8725 ms | 12553 ms |

Lane 5 module alone: 1,913,198 B as emitted, 428,886 B after `wasm-opt -O3` (served), 114,478 B brotli, 136,410 B gzip.
Runs (ms): lane 5 title [4547, 4425, 4511, 4511, 4508], map [5783, 5642, 5760, 5682, 5691]; stock title [8830, 8507, 8428, 8585, 8363], map [12760, 12306, 12228, 12571, 12327].
TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is
the raw bundle, its compressed figures are the 2026-09-20 footprint audit's floor build (wasm-opt -Oz, external wasm).
