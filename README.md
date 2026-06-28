# BetterBags - Upgrade Glow

A [BetterBags](https://www.curseforge.com/wow/addons/better-bags) module that
makes bag items **glow when they're an item-level upgrade** over what you have
equipped, and tags each upgrade with its **upgrade track** (Adventurer,
Champion, Hero, Myth, Void).

## Features

- Glow highlight on any bag item whose item level beats the slot it would
  replace.
- Dual-slot aware: rings, trinkets, and weapons are checked against both slots,
  and main-hand two-handers are handled correctly for the off-hand.
- Armor-type aware: only glows armor your class can actually wear, so a plate
  wearer won't see mail light up (cloaks, rings, necks, and trinkets always count).
- Weapon-proficiency aware: only glows weapons your class can equip, so a mage
  won't see a two-handed axe (or a paladin a dagger) light up as an upgrade.
- Ignores cosmetics: tabards and shirts never glow, even when they roll an item
  level — they don't affect your gear.
- Small colored track badge (Adv / Champ / Hero / Myth / Void) in the item
  corner, read from the item's upgrade tooltip line.
- Updates live as you equip gear; persists through the bag "clear recent" action.

## Requirements

- World of Warcraft Retail (Midnight / 12.x)
- [BetterBags](https://www.curseforge.com/wow/addons/better-bags) (required)

## Installation

Install via the CurseForge app, or manually:

1. Download the latest release `.zip`.
2. Extract the **BetterBags_UpgradeGlow** folder into:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
3. Log in to WoW or type `/reload`.

## Usage

There's nothing to configure — once BetterBags and this module are enabled, open
your bags and upgrades light up automatically.

## License

Released under the MIT License. See [LICENSE](LICENSE).
