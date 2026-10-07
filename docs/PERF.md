# Performance, size and memory: what has been measured (as of 2026-10-07)

Every number here is dated and comes from a run recorded at the time; nothing was
re-measured for this page. All runs were on one arm64 MacBook Air (macOS 25.x),
often with other jobs running, so compare rows **within** a table, not across
tables. Medians unless noted.

How lg reaches a machine, as compared below:

| lane | what runs |
|---|---|
| **vm** | let-go's bytecode VM, native `lg` |
| **aot** | gogen: IR lowered to Go, built natively (`lg compile`) |
| **stock Go wasm** | the VM compiled to wasm by Go (`lg -w`), what xsofy.quest ships |
| **TinyGo wasm** | the VM compiled to wasm by TinyGo |
| **WasmGC** | this backend: IR lowered to one WasmGC module, runtime written in lg |
| **linear** | this backend's experimental `--target linear` (no GC yet; bump allocator) |

## 1. Browser bundle size and boot (2026-10-06)

Full tables, per-run times and method: [`corpus/xsofy/size-boot.md`](../corpus/xsofy/size-boot.md),
[`corpus/legmacs/size-boot.md`](../corpus/legmacs/size-boot.md) (`checks/size-boot.sh`,
headless Chromium, 5 runs). Bundle = every file the page fetches.

**xsofy** (xsofy `0c38395`, lg `ff1e6dac`):

| lane | bundle, brotli | time to title | time to map |
|---|---|---|---|
| WasmGC | 149 KB | 4.6 s | 5.9 s |
| stock Go wasm | 6.66 MB | 8.2 s | 12.5 s |
| TinyGo wasm (2026-09-20, not re-run) | 1.27 MB (`wasm-opt -Oz` floor build) | 8.7 s | 12.6 s |

The title card animates for part of time-to-title on every lane, so the map column
is the better comparison. The WasmGC module alone is 1.92 MB as emitted, 431 KB
after `wasm-opt -O3`, 115 KB brotli.

**legmacs** (legmacs `187fea2`): WasmGC bundle 180 KB brotli, first frame 346 ms.
The stock Go wasm build (6.62 MB brotli) does not boot it. Without the evaluator
(`LW_NO_EVAL=1`), the module was 120 KB brotli instead of 166 KB (2026-10-02).

## 2. Runtime CPU and peak memory, native hosts (2026-10-05)

Seven small programs, each run on four lanes: vm and aot at lg `dbaf59cb`; linear
modules under wazero's optimizing compiler (wazevo, no compilation cache, so each
run includes compiling the module); WasmGC modules under Node 25. hyperfine `-N`,
1 warmup + 5 runs, **user CPU**; peak RSS from one `/usr/bin/time -l` run. All
lanes print identical output.

This table is the second run, after the linear target's runtime was shaken
(PR #11); the machine was quieter than in the first run.

| program | vm | aot | linear (wazevo) | WasmGC (Node) |
|---|---|---|---|---|
| empty (startup floor) | 8 ms | 7 ms | **3 ms** | 57 ms |
| fib 35 | 3.55 s | 167 ms | **95 ms** | 125 ms |
| tak 30 22 12 | 3.44 s | 104 ms | **92 ms** | 114 ms |
| loop to 1e7 | 713 ms | **10 ms** | 27 ms | 86 ms |
| vec-conj 1e6 | 540 ms | 488 ms | 440 ms | **153 ms** |
| map-assoc 2e5 | 1.03 s | 985 ms | 571 ms | **307 ms** |
| seq-pipeline 2e6 | 864 ms | 896 ms | 2.68 s | **444 ms** |
| str-build 2e5 | 60 ms | 59 ms | 442 ms | 228 ms |

Peak RSS (MiB), first run (before the linear shake; WasmGC and VM numbers are
unaffected by it):

| program | vm | aot | linear (wazevo) | WasmGC (Node) |
|---|---|---|---|---|
| empty | 19 | 17 | 14 (7 after shake) | 57 |
| fib 35 (second run) | 19 | 18 | 7 | 58 |
| vec-conj | 83 | 86 | 473 (524 after) | 102 |
| map-assoc | 58 | 57 | 730 (811 after) | 145 |
| seq-pipeline | 128 | 22 | 919 (920 after) | 161 |
| str-build | 43 | 41 | 288 (310 after) | 116 |

Reading:

- **Scalar code:** both of the backend's targets run at or above gogen AOT speed, and
  are 20–40× faster than the VM on fib and tak.
- **Allocating code:** WasmGC under V8 is the fastest lane, 2–4× ahead of AOT on
  vec-conj and map-assoc. Its memory floor is Node's own (~57 MiB for an empty
  program); on these programs its peak is 1.2–2.7× the VM's.
- **The linear target is not usable for allocating programs yet.** Its milestone-1
  bump allocator never frees, so RSS climbs to 0.3–0.9 GiB and seq-pipeline and
  str-build are slower than the VM. A collector (M2,
  [`LINEAR-TARGET-SPEC.md`](LINEAR-TARGET-SPEC.md)) is the gate; re-run this
  table after it lands.
- vm and aot user CPU exceeds wall time on allocating programs because Go's GC runs
  on other cores.

## 3. The first probe (2026-09-30)

Before the backend existed, a ~120-line prototype lowered `fib` from let-go's IR
(lg main `4e769212`) to WasmGC. fib(32), boxed integers:

| lane | time | artifact |
|---|---|---|
| prototype WasmGC, Node 25 | 28 ms | 301 B |
| VM as wasip1 under wasmtime 47 | 3469 ms | 29.6 MB |
| VM, native arm64 | 605 ms | – |
| aot, native arm64 | 26 ms | 14.2 MB |
| aot built to wasip1 by stock Go, wasmtime 47 | 108 ms | 27.5 MB |
| aot built to wasi by TinyGo `-opt=2`, wasmtime 47 | 1554 ms | 15.8 MB |

So the prototype tied native AOT and ran ~120× faster than the VM inside wasm
(~860× on a typed-integer loop). It skipped overflow checks, closures, vars and
exceptions, so these numbers flatter it. The shipped backend, with checked
arithmetic, holds fib(32) within 1.37× of that prototype (`checks/bench-fib.sh`,
2026-10-01).

## 4. Compile time (2026-10-04/05)

Warm builds of legmacs (the largest corpus program) through the driver:

- Faster module shaking (PR #3): −27% wall (77.4 → 58.3 s under load;
  53.0 → 41.5 s on a quieter repeat), output byte-identical.
- Lowering hotspots (PR #7): −22% wall, −30% CPU (39.3 → 31.2 s), output
  byte-identical across 2,002 modules.

Biggest remaining costs: typeinfer (5.2 s, two runs), the shake's live set (3.0 s),
IR build (2.0 s).

## Not measured yet

- The gogen-to-wasm browser builds (stock Go and TinyGo) against WasmGC on one
  harness. Both lanes run xsofy, but each has only been measured on its own.
- Peak memory in the browser for any lane; the RSS table above is native hosts only.
- Anything on a quiet machine with more than 5 runs.
