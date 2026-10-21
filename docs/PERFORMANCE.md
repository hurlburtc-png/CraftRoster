# Performance baseline and resource limits

Measured with `tests/benchmark.py` in the container on 2026-10-21. These Lua 5.1
and LuaJIT mocked-client results are reproducible workload checks, not in-game
FPS, taint, network-latency or native-frame-memory measurements.

| Workload | Lua 5.1 | LuaJIT |
| --- | ---: | ---: |
| Idle Lua heap added by full addon and 2,511-recipe database | 3,987.5 KiB | 2,974.2 KiB |
| Additional Lua heap for 500 work orders | 446.8 KiB | 334.4 KiB |
| Open 500-order panel | 1.27 ms | 0.65 ms |
| Average refresh of full 500-order queue | 0.787 ms | 0.236 ms |
| Additional order UI objects after 100 scrolls | 0 | 0 |
| Per-frame OnUpdate handlers | 0 | 0 |
| Directory first open: 5,000 recipes / 105,000 ownership links | 221.13 ms | 118.26 ms |
| Profession scans triggered by 20 update events | 1 | 1 |

The large directory workload still does meaningful work on first open. Its cache
and reused rows avoid rebuilding all recipe frames while scrolling. The bundled
recipe database is an explicit, fixed startup memory cost; it avoids downloading
recipe/source data during play. Only the active locale's database payload is used.

Work is driven by game events and direct clicks, with no polling/frame loop.
Directory/shopping/profession refreshes coalesce event bursts using short one-shot
timers. Hidden panels do not redraw; shopping bag listeners are removed on close.
Guild sync is throttled and caches unchanged serialized data. Work orders build
only visible rows and reuse them while scrolling; other-character orders are
viewed from saved data, not duplicated into the active queue.

Storage limits per character:

- 500 orders; closed history is pruned first, active orders are not silently lost.
- 100 outstanding material transfers; existing progress survives short-log cleanup.
- 1,000 mail receipts and 1 MiB of retained mail-signature text. Reaching either
  limit refuses another automatic import with manual-entry guidance.
- At most six outgoing trade slots are examined per trade snapshot. Inventory
  loading walks bags once, rather than once per material type.

Transient selection/batch/click caches are cleared when closed orders are pruned.
Numbers depend on recipe/material counts, character history and the real client.
A live Forever test must measure addon memory and CPU before making an FPS claim.

Beta 11 adds lazy composer/notes UI, scanned materials on the owning character,
and a separate on-demand details protocol. Startup creates 13 mocked UI objects;
the synthetic directory adds 94 on first open and 8 over 100 scrolls. The new
composer is allocated only when opened. There are still no per-frame updates.
The latest measurements ran alongside the regression suite; timings are workload
samples, not a stable in-game performance guarantee.

Details traffic uses at most 32 chunks of 200 payload bytes per transfer, eight
concurrent incoming senders and 128 queued outgoing chunks. Requests are limited
to 100 recently selected recipe/crafter pairs and throttled for 30 seconds; a
received list is reused for five minutes. Recipe records retain at most eight
peer schematics each, with at most 32 reagents per schema. Public and private
member notes are capped at 240 UTF-8 bytes. No private note is serialized.
