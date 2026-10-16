# Wow Forever Addons

A World of Warcraft addon for tracking professions and recipes, with a foundation for a guild-wide recipe directory.

## Installation

1. Download or clone this repository.
2. Copy the addon folder into `Interface/AddOns`.
3. Restart WoW or run `/reload`.
4. Enable **Wow Forever Addons** in the AddOns menu.

## Commands

- `/wfa` — open or close the addon panel
- `/wfa toggle` — enable or disable the addon

## Recipe tracking

- Click **Update My Recipes** to manually refresh your locally saved recipe list.
- Newly learned recipes are captured automatically when WoW reports `NEW_RECIPE_LEARNED`.
- Use the **Auto-update new recipes** checkbox to enable or disable automatic capture.
- Recipe data is stored locally in `WowForeverAddonsDB` for now.

## Development

- `Core.lua` — initialization, saved variables, and slash commands
- `Recipes.lua` — recipe capture and automatic new-recipe tracking
- `Panel.lua` — small movable settings/status panel
- `WowForeverAddons.toc` — addon metadata and load order
