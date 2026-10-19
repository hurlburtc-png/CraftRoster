# CraftRoster

Find a guild crafter, gather your materials, and arrange the craft from one lightweight WoW addon.

[**Download CraftRoster.zip**](https://github.com/hurlburtc-png/CraftRoster/raw/refs/heads/main/CraftRoster.zip)

## Install

1. Download and extract **CraftRoster.zip**.
2. Copy the **CraftRoster** folder into your WoW `Interface/AddOns` folder.
3. Restart WoW and type **`/cr`**.

`CraftRoster.toc` should sit directly inside `Interface/AddOns/CraftRoster`. Use the download above for the addon-only package. If using GitHub's **Code → Download ZIP**, rename the extracted folder to **CraftRoster** first.

**Target:** WoW Forever 1.60.1, build 70450 (interface 16001). Development build; in-game compatibility checks are still required.

## What it does

- Search recipes and professions, find saved guild crafters, and see online status.
- Keep favorites and a pinned shopping list showing bag quantities and missing materials.
- Prepare crafting whispers and mail; offer available material quantities when you open a trade.
- Browse locally discovered unlearned recipes. If no synced crafter knows one, view its recipe link and **Where to get it** details when the client supplies them.

Open each profession to collect its available recipe data, then use **Refresh** to sync with guildmates running CraftRoster. No synced crafter is not proof nobody in the guild knows a recipe. Recipe/source coverage depends on the client; missing sources say **Source unknown**. A complete recipe/source database is not bundled.

Whispers remain drafts. You confirm trades and send mail yourself.

## Handy commands

| Command | Action |
| --- | --- |
| `/cr` | Open the directory |
| `/cr settings` | Settings and manual recipe scan |
| `/cr shopping` | Toggle the pinned shopping list |
| `/cr reset` | Restore window size and position |
| `/cr bug` | Copy a Lua error report |

[Full usage and commands](docs/USAGE.md) · [Testing and known limits](TESTING.md) · [Report a bug](https://github.com/hurlburtc-png/CraftRoster/issues)

## Development

Addon files live at the repository root. Run simulated API checks and rebuild the install ZIP after changes:

```sh
python -m pip install -r tests/requirements.txt
python scripts/package_addon.py CraftRoster.zip
python -m unittest discover -s tests -v
```

Made by Triggles · [MIT license](LICENSE)

