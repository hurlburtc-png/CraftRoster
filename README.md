# Wow Forever Addons

A starter World of Warcraft addon project.

## Installation

1. Download or clone this repository.
2. Copy the `WowForeverAddons` folder into your WoW `Interface/AddOns` directory.
3. Restart WoW or use `/reload`.
4. Enable **Wow Forever Addons** in the AddOns menu.

## Commands

- `/wfa` — show available commands
- `/wfa toggle` — enable or disable the addon

## Development

- `WowForeverAddons.toc` defines addon metadata and file load order.
- `Core.lua` contains initialization and slash-command handling.
- Settings persist through `WowForeverAddonsDB` saved variables.
