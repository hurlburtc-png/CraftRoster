# CraftRoster 0.8.0-beta.1 test candidate

Status: ready for controlled in-game testing; release approval still requires a real client run.
The declared TOC interface is 110200. Lua 5.1/LuaJIT checks use API mocks, not a WoW
installation. Record the actual client/flavor/build/interface with `/crdiagnostics`.
Do not treat the generated mockup images as runtime evidence.

## Automated review

```sh
python -m pip install -r tests/requirements.txt
python -m unittest discover -s tests -v
python tests/benchmark.py
```

Current review: 429 tests executed, 419 passed and 10 explicitly skipped for APIs
absent from the chosen profile. Both Lua 5.1 and LuaJIT 2.1 run modern, legacy and
minimal API scenarios. Isolated peer tests cover sync and request/status exchange.
Syntax and ZIP membership/integrity checks also pass.

The 5,000-recipe / 105,000-link workload keeps startup at 8 mocked UI objects,
adds 55 on first directory open, and adds only 4 more after 100 scrolls. A 20-event
recipe burst schedules one scan. Timings measure the mock runtime, not game FPS
or memory. Lua error storms retain at most 10 distinct reports, reuse the stack
for repeated messages, and print at most one capture notice per 10 seconds.

Review fixes include reliable whisper addressing; visible results after filtering
or shrinking a scrolled list; reset-before-first-open; preserving search-template
handlers; explicit addon-send failure handling; manual sync publishing the local
snapshot as well as requesting peers; and reporting interrupted chunk sends.

## In-game acceptance run

1. **Install and startup.** Install only the packaged CraftRoster directory. Test
   once with existing SavedVariables and once with a backed-up, clean profile.
   Record any out-of-date/interface warning. Check `/crdiagnostics` and startup
   for Lua errors. Exercise the supported APIs in the actual target client.
2. **Directory and settings.** Open `/cr`, all three tabs, and `/cr settings`.
   Move/resize at minimum, default and large sizes, including a non-default UI
   scale. Reload and verify geometry. Run `/cr reset` before first opening, too.
   Scroll deeply, then search/filter/favorite down to one or zero results.
3. **Recipes.** Open each profession, scan, learn a recipe, and scan unchanged
   data again. Inspect known names, quantities, required/optional slots and
   alternative reagent quality. Linked/guild profession views must not become
   the player's learned recipes. Verify temporarily uncached reagent data.
4. **Guild peers.** Use two characters running this candidate. Check manual
   refresh in both directions, received recipe names, offline/online and
   cross-realm identities, and a realistically large recipe collection. Retry
   after chat restrictions or a reported interrupted transfer.
5. **Whisper and mail.** Select a crafter. Whisper Player must open an addressed
   draft with bracketed recipe quantities, without sending it. Send with Enter;
   exercise `/crwhisper` for long material lists. Mail Player must fill the exact
   selected Name-Realm and recipe subject, including an already-open mailbox and
   a recipe with no material data. Confirm recipients and attachments manually.
6. **Shopping list.** Pin a recipe, close the directory, acquire/remove materials,
   and verify counts. Drag the list and reload; reopen with `/cr shopping`. Close
   its X and ensure it stays closed after reload. Select a crafter and click a
   material to enter their contribution. Check requirements, whisper wording,
   and trade/mail quantities; switching crafters must not reuse another's share.
7. **Trades.** Test sufficient, partial, locked and missing stacks; an occupied
   cursor; occupied offer slots; the wrong partner; cancellation before/after
   acceptance; an ordinary close; a retry; and successful exchange. The addon
   must never open/accept a trade or complete the craft itself. Verify real
   success/cancel event ordering and corresponding `/crrequests` material status.
   Without a recognized notification, status must remain unconfirmed. Confirm
   returned materials in the shopping list after cancellation.
8. **Craft completion.** Receive the crafted item, then mark the request complete
   manually with `/crstatus <id> completed`. Confirm the peer sees it and that a
   late accepted-status message cannot downgrade it.
9. **Bug report.** Open `/cr bug` (or the beetle in `/cr settings`). Copy with
   Ctrl+C / Cmd+C and paste into a text editor or issue. Confirm the report has
   the candidate version, client build/interface, captured message and stack,
   repeat count and first/last timestamps. It must remain available after
   reload. Test keyboard focus, scrolling, selection and Escape in-game.

## Known limits to include with test feedback

- Protected inventory/chat APIs, template layout, clipboard interaction and real
  trade/mail events require the client; cloud tests cannot certify them.
- Alternative reagent slots currently choose the first listed alternative.
  Confirm quality before using auto-fill. Material schematics are scanned
  locally; guild sync shares recipe IDs/names/professions, not schematics.
- One snapshot is bounded to 256 chunks of 200 payload bytes, with 60-second
  receive expiry and at most eight incoming senders. Oversized snapshots are
  rejected with a message. Timerless clients support small snapshots only.
- Trade close alone is not success. Successful material exchange is not proof of
  finished crafting. The shopping list counts current bags, not delivered items.
- Error capture starts when ErrorReporter.lua loads and records attributable
  CraftRoster errors, not every other addon's errors or errors caught privately
  by another error handler. Reports are copied manually and never uploaded.

For feedback, include the copied `/cr bug` report plus steps, expected/actual
behavior, recipient/quantity details where relevant, and whether other addons
were enabled. Avoid publishing account information or unrelated private chat.
