# P4.4: xsofy turn latency (measured 2026-10-21, checks/turn-time.sh)

xsofy 0c38395, lg lg-e9789b7d53, headless Chromium via `checks/browser-boot.mjs --turn-time`, seed 424242, 40 keys per run, 3 runs per lane alternating lanes, load average at the end 3.25.
A turn = keydown on xterm's textarea to the game's `xsofy/stats` event, both timestamped in the page: the game
waking on the key plus the turn's compute, before the frame is drawn. Keys the game coalesced or ignored are not
counted. Per run the median over its counted turns; the lane row is the median of its runs.

| lane | median | mean | p90 | turns counted | runs (median ms) |
|---|---|---|---|---|---|
| lane 5: lower-wasm (emitted) | 42.9 ms | 42.9 ms | 48.5 ms | 27/27/27 of 40 | 42.1, 43.1, 42.9 |
| stock Go (lg -w, let-go e9789b7d) | 164.1 ms | 156.5 ms | 194.7 ms | 27/27/27 of 40 | 164.1, 160.1, 164.2 |

Median turn: lower-wasm 42.9 ms, stock Go 164.1 ms (3.82x).
lw run 1 turns: l:0>1 l:1>2 j:2>3 j:3>4 h:4>5 k:5>6 l:6>7 j:7>8 l:8>9 l:9>10 j:10>11 j:11>11 h:11>12 k:12>13 l:13>14 j:14>15 l:15>15 l:15>15 j:15>15 j:15>15 h:15>16 k:16>17 l:17>18 j:18>19 l:19>19 l:19>19 j:19>19 j:19>19 h:19>20 k:20>21 l:21>22 j:22>23 l:23>23 l:23>23 j:23>23 j:23>23 h:23>24 k:24>25 l:25>26 j:26>27
lw run 2 turns: l:0>1 l:1>2 j:2>3 j:3>4 h:4>5 k:5>6 l:6>7 j:7>8 l:8>9 l:9>10 j:10>11 j:11>11 h:11>12 k:12>13 l:13>14 j:14>15 l:15>15 l:15>15 j:15>15 j:15>15 h:15>16 k:16>17 l:17>18 j:18>19 l:19>19 l:19>19 j:19>19 j:19>19 h:19>20 k:20>21 l:21>22 j:22>23 l:23>23 l:23>23 j:23>23 j:23>23 h:23>24 k:24>25 l:25>26 j:26>27
lw run 3 turns: l:0>1 l:1>2 j:2>3 j:3>4 h:4>5 k:5>6 l:6>7 j:7>8 l:8>9 l:9>10 j:10>11 j:11>11 h:11>12 k:12>13 l:13>14 j:14>15 l:15>15 l:15>15 j:15>15 j:15>15 h:15>16 k:16>17 l:17>18 j:18>19 l:19>19 l:19>19 j:19>19 j:19>19 h:19>20 k:20>21 l:21>22 j:22>23 l:23>23 l:23>23 j:23>23 j:23>23 h:23>24 k:24>25 l:25>26 j:26>27
stock run 1 turns: l:0>1 l:1>2 j:2>3 j:3>4 h:4>5 k:5>6 l:6>7 j:7>8 l:8>9 l:9>10 j:10>11 j:11>11 h:11>12 k:12>13 l:13>14 j:14>15 l:15>15 l:15>15 j:15>15 j:15>15 h:15>16 k:16>17 l:17>18 j:18>19 l:19>19 l:19>19 j:19>19 j:19>19 h:19>20 k:20>21 l:21>22 j:22>23 l:23>23 l:23>23 j:23>23 j:23>23 h:23>24 k:24>25 l:25>26 j:26>27
stock run 2 turns: l:0>1 l:1>2 j:2>3 j:3>4 h:4>5 k:5>6 l:6>7 j:7>8 l:8>9 l:9>10 j:10>11 j:11>11 h:11>12 k:12>13 l:13>14 j:14>15 l:15>15 l:15>15 j:15>15 j:15>15 h:15>16 k:16>17 l:17>18 j:18>19 l:19>19 l:19>19 j:19>19 j:19>19 h:19>20 k:20>21 l:21>22 j:22>23 l:23>23 l:23>23 j:23>23 j:23>23 h:23>24 k:24>25 l:25>26 j:26>27
stock run 3 turns: l:0>1 l:1>2 j:2>3 j:3>4 h:4>5 k:5>6 l:6>7 j:7>8 l:8>9 l:9>10 j:10>11 j:11>11 h:11>12 k:12>13 l:13>14 j:14>15 l:15>15 l:15>15 j:15>15 j:15>15 h:15>16 k:16>17 l:17>18 j:18>19 l:19>19 l:19>19 j:19>19 j:19>19 h:19>20 k:20>21 l:21>22 j:22>23 l:23>23 l:23>23 j:23>23 j:23>23 h:23>24 k:24>25 l:25>26 j:26>27
