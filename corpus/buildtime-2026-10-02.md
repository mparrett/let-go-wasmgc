# Where a legmacs module build spends its time (probe, 2026-10-02 ~09:50 PDT)

One build of legmacs main.lg (187fea2) through the backend at tree 014df62 +
agents B/C in flight, load average 21-36 (two agents compiling alongside), so
wall times are inflated and CPU time is the honest number for the driver.

| phase | wall | notes |
|---|---|---|
| driver (`lg driver.lg`: reading, IR build + optimize, `lower_wasm.lg` lowering, WAT print) | 232 s (150 s CPU) | one lg process; the front-end vs lowering split needs an `LW_TIMING` probe inside driver.lg, not built |
| `wasm-tools parse` (12.4 MB WAT → 2.2 MB wasm) | 2.4 s | |
| `wasm-opt -O3` (2.2 MB → 671 KB) | 42 s | binaryen; skippable in dev (`LW_NO_OPT=1`) |
| node session on the optimised module (boot, defn, call, quit) | 1.5 s | |
| same session on the unoptimised module | 0.9 s | boot is faster without -O3's inlining? one sample, not a finding |

Reading for let-go-lab#43's question: node test execution is noise (≈1 s per
run); the driver is 80%+ of the build even with wasm-opt counted, so caching
compiles is the right investment, and the next probe is INSIDE the driver:
stamp `System/nanoTime` after read, after `ir.build`, after each optimize pass
group, after lowering, after the WAT print. Round-1's perf-report.md measured
the same shape for small oracle programs (driver >98%, wasm-tools 0.15 s,
node 0.2 s).
