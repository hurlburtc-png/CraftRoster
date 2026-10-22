# CraftRoster

[**Download CraftRoster.zip — latest install version**](https://github.com/hurlburtc-png/CraftRoster/raw/refs/heads/main/CraftRoster.zip)

Your guild has someone who can craft that. Unfortunately, “someone” is usually an alt with an unpronounceable name. CraftRoster helps you find the right crafter, check which materials you’re missing, and prepare a whisper or mail request without asking guild chat the same question for the fourth time. Less detective work. More shiny things.

**Preferred install download.** Extracts to one **CraftRoster** folder, ready for `Interface/AddOns`. This link stays the same as the addon is updated.

**Target:** Forever 1.60.1, build 70450 · Interface 16001

**Status:** Beta. Automated checks pass; in-game verification is still required.

## Install

1. Download **CraftRoster.zip** above, rather than GitHub’s **Code → Download ZIP**.
2. Extract into `Interface/AddOns`, so the file sits at `Interface/AddOns/CraftRoster/CraftRoster.toc`.
   If your extractor adds an outer folder, move the inner **CraftRoster** folder directly into **AddOns**. The folder containing **CraftRoster.toc** is the addon.
3. Restart WoW and type `/cr`.

## Get started

Open your professions and scan them, then click **Refresh** to share recipes with guildmates running CraftRoster. Search for a craft, set its quantity and select a crafter.

- **Whisper:** edit the request, then click a known crafter or **Send**. Copy the text for someone outside the guild. Long requests use **Send next**.
- **Mail:** prepare the recipient, subject, materials and attachments; review and send the mail yourself.
- **Materials:** see icons and live bag counts in the main window or shopping list. Click to insert its item link into an open whisper draft or active chat; otherwise, with the Auction House open, fill its search box. Shift-click links into chat.
- **Work Orders:** track requests, choose single crafts or batches, and import recognized crafting mail when read. Orders survive normal logout/reload.

## Other features

- Bundled recipe catalogue, online/offline guild crafters, item tooltips and favorites.
- Partial delivery tracking, an **Auto-load items** toggle, and **Cancel request** to update connected crafters.
- Public crafting notes, private member notes and missing material details fetched from a crafter’s scan.
- Movable, resizable windows with scrolling for longer recipe details.
- Dark-and-gold styling, a wider craft detail pane and highlighted recipe/crafter selections.
- **Settings → Appearance:** live 75–150% addon scaling and Classic Gold, Frost Blue,
  Emerald, Arcane Violet or High Contrast colours. Preferences save automatically;
  **Reset appearance** restores the defaults. Large windows fit the available screen.

You confirm trades, mail and completed orders yourself. Missing guild data does not mean nobody knows a recipe. Acquisition sources and drop estimates are labeled with their provenance.

## Commands

| Command | Opens |
| --- | --- |
| `/cr` | Crafting directory |
| `/cr orders` | Crafter work orders |
| `/cr shopping` | Shopping list |
| `/cr settings` | Settings and recipe scan |
| `/crtrade` | Material delivery review |
| `/cr bug` | Lua error report |

[Full guide](docs/USAGE.md) · [Testing and limitations](TESTING.md) · [Roadmap](docs/ROADMAP.md) · [Report an issue](https://github.com/hurlburtc-png/CraftRoster/issues)

Made by Triggles · [MIT license](LICENSE)
