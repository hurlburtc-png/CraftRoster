# Remaining development

These are gaps identified against the requests discussed so far, not implemented
features. In-game testing remains required for the current candidate.

- Expand the four-entry starter source/rate set, prioritizing Forever-confirmed
  data with provenance and update dates. Bundled LibProfessionDB currently
  enriches mapped recipe items and source names, not percentages or the entire catalogue.
- Add incoming request Accept/Decline UI. Existing request/status commands do not
  provide a complete popup workflow or decline state.
- Add member notes. The Players tab now expands each member's synced recipe list;
  selecting a recipe opens its crafting details and clears conflicting filters.
- Share complete material schematics between guild clients. Current sync shares
  recipe IDs, names and professions; material details depend on a local scan.
- Review request transport privacy: addon messages currently use the guild
  channel with target filtering; user-sent whisper drafts are private whispers.
- Validate actual Forever tooltips, layout, cache events and protected inventory,
  trade and mail APIs with two guild clients. Automated checks use mocked APIs.

Roster updates are event-driven plus manual Refresh; periodic polling is not
implemented. Trades, mail sending and crafting completion remain user-confirmed.
