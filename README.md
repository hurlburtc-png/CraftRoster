# CraftRoster

Find a guild crafter, gather your materials, and arrange the craft from one lightweight WoW addon.

[**Download CraftRoster.zip**](https://github.com/hurlburtc-png/CraftRoster/raw/refs/heads/main/CraftRoster.zip)

## Install

1. Download **CraftRoster.zip** using the direct download above.
2. Extract it directly into your WoW `Interface/AddOns` folder. It creates the **CraftRoster** folder automatically.
3. Restart WoW and type **`/cr`**.

`CraftRoster.toc` should sit directly inside `Interface/AddOns/CraftRoster`. Use the download above for the addon-only package. GitHub’s **Code → Download ZIP** downloads the source repository with an extra wrapper folder; use **Download CraftRoster.zip** above for installation.

**Current test candidate:** 0.8.0-beta.11.

**Target:** WoW Forever 1.60.1, build 70450 (interface 16001). Development build; in-game compatibility checks are still required.

## What it does

- Search recipes and professions, find saved guild crafters, and see online status.
- Keep favorites and a pinned shopping list showing bag quantities and missing materials.
- View recipe details and material icons with live bag counts in the main window, including while the shopping list is closed.
- Set craft quantities, prepare linked whispers and detailed mail, and track material deliveries across trades.
- Cancel selected requests and update connected crafters’ outstanding orders.
- Manage persistent work orders, choose individual crafts or batches, and import recognized crafting mail when read.
- Add a public note about your crafting availability and private notes about other members.
- Fetch a selected crafter's scanned material list when local details are missing, without broadcasting every schematic.
- Browse locally discovered unlearned recipes. If no synced crafter knows one, view the teaching-item tooltip, binding, and **Where to get it** details. Four starter references include clearly labeled Classic drop estimates; bundled LibProfessionDB adds mappings and source names, with no separate install.

Open each profession to collect its available recipe data, then use **Refresh** to sync with guildmates running CraftRoster. No synced crafter is not proof nobody in the guild knows a recipe. Recipe/source coverage depends on the client; missing sources say **Source unknown**. The Forever database is bundled for lookups; the directory imports its full bundled recipe catalogue for offline searching, even without synced crafters. [Source coverage and accuracy](docs/RECIPE_SOURCES.md).

The Whisper button opens an editable composer. Clicking a known crafter or Send sends the prepared whisper; long requests require Send next for each remaining line. Copy the text for crafters outside the guild. If direct chat sending is unavailable, a native draft opens for Enter to send. You confirm trades and send mail yourself.

## Handy commands

| Command | Action |
| --- | --- |
| `/cr` | Open the directory |
| `/cr settings` | Settings and manual recipe scan |
| `/cr shopping` | Toggle the pinned shopping list |
| `/cr orders` | Open persistent crafter work orders |
| `/crtrade` | Review confirmed and outstanding material transfers |
| `/cr reset` | Restore window size and position |
| `/cr bug` | Copy a Lua error report |

[Full usage and commands](docs/USAGE.md) · [Testing and known limits](TESTING.md) · [Remaining plans](docs/ROADMAP.md) · [Report a bug](https://github.com/hurlburtc-png/CraftRoster/issues)

## Development

Addon files live at the repository root. Run simulated API checks and rebuild the install ZIP after changes:

```sh
python -m pip install -r tests/requirements.txt
python scripts/package_addon.py CraftRoster.zip
python -m unittest discover -s tests -v
```

Made by Triggles · [MIT license](LICENSE)

