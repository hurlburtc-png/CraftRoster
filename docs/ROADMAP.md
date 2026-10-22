# Remaining development

These are gaps identified against the requests discussed so far, not implemented
features. In-game testing remains required for the current candidate.

- Add independently verified Forever drop percentages beyond the four labeled
  Classic references. Expanded bundled acquisition lists, totals, skill requirements
  and provenance are now displayed; they do not establish verified drop rates.
- Review request transport privacy: addon messages currently use the guild
  channel with target filtering; user-sent whisper drafts are private whispers.
- Validate Work Orders on two Forever clients: profession opening, direct recipe
  craft/enchant calls and batches, manual item targeting, trade-person filtering,
  received-mail imports, other-character views, linked whisper capture and status
  sync. Orders remain manually confirmed after craft.
- Verify performance in the actual Forever client. Mock baselines cover 500 orders,
  5,000 recipes, 105,000 ownership links, Lua heap growth and row reuse.
- Validate actual Forever tooltips, layout, cache events and protected inventory,
  trade and mail APIs with two guild clients. Automated checks use mocked APIs.

Roster updates are event-driven plus manual Refresh; periodic polling is not
implemented. Trades, mail sending and crafting completion remain user-confirmed.

## Next usability targets (not implemented)

1. Recipe availability filters: guild knows / I know / missing recipe, with a
   clear distinction between missing sync data and a genuinely unknown recipe.
2. Surface scan/sync freshness and offline last-seen details beside crafters.
3. A shared multi-recipe shopping list that combines reagents and separates
   bag stock, deliveries and crafter-provided materials.
4. Optional item-tooltip guild-crafter lookup, with online/favorite priority.
5. Clearer next-action guidance through crafter selection, materials and delivery;
   keep native profession terminology and user-confirmed trade/mail actions.

Comparison references: author descriptions of
[GuildWorkshop](https://www.curseforge.com/wow/addons/guildworkshop),
[GuildCrafts](https://www.curseforge.com/wow/addons/guildcrafts) and
[Profession Master](https://www.curseforge.com/wow/addons/profession-master).
These are usability references, not claims that every addon supports Forever.

## Included in beta 11

- Added compact Cancel request control beneath Whisper/Mail: cancels this character’s selected recipe/crafter requests, stops further material loading, and closes matching work orders on connected crafters. Cancellation cannot recall sent mail or delivered materials; unavailable guild sync is reported explicitly.

- Recipe and finished-item links now use native item names/icons instead of generic Recipe/Craft button chrome, retaining hover, inspect, chat insertion and copy. Shopping materials open native item tooltips with quantity/contribution progress below; left-click still fills the Auction House search.

- Selected-craft pane now keeps the finished item at the top, native recipe tooltip text below, and material icons/counts beside the recipe. The main pane tracks bag, quantity, contribution and delivery changes while the shopping window is closed. Compact windows scroll the selected-craft pane, including request controls and crafters. Search results retain native item hover tooltips.

- Movable whisper composer with editable/copyable text, clickable item links, known-crafter selection, duplicate-send prevention and explicit next-message controls for long requests.
- Guild-visible self-authored member notes and private account notes on the Players tab.
- On-demand, bounded material-list exchange from a known crafter's local profession scan; older recipe-sync clients remain compatible. Local scans take precedence over peer data.
- Acquisition sources show true totals, capped examples, unnamed-source fallbacks, profession-learned recipes, skill requirements and provenance, including alongside client source text.
