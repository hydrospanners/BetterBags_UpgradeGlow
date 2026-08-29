# Changelog

All notable changes to BetterBags - Upgrade Glow are listed here.

## [1.5.0]

- New badges for the special gear from The Venomous Abyss: Venomcursed cantrip
  armor (last two bosses) shows an acid-green "Venom", and the raid's Corrosive
  effect items show a teal "Corr". Like every other track, both can be renamed,
  recoloured, or hidden in settings.
- Season 2 crafted gear ("Tidal Crafted") already gets the "Craft" badge.

## [1.4.1]

- Marked compatible with patch 12.1. No behavior changes.

## [1.4.0]

- Added a settings panel under BetterBags options ("Upgrade Glow" in the
  Plugins section). Nothing is forced on any more:
  - Glow and track badges can each be turned off on their own.
  - The glow colour and opacity can be changed.
  - The badge can be moved to any corner of the item, so it stops covering
    icons drawn by other BetterBags plugins and themes.
  - Every track's badge text and colour can be edited. Clearing a track's text
    hides that track, so you can show only the ranks you care about.
- Settings are saved account-wide.

## [1.3.2]

- Marked compatible with 12.1 alongside 12.0.7. Support for 12.0.5 is dropped.

## [1.3.1]

- Unique-equipped duplicates no longer glow: when a copy of a unique ring or
  trinket is already worn, a second copy only glows if it beats the equipped
  copy itself (the only slot it can legally go), not the other slot. Getting
  the same trinket twice as loot no longer lights up a fake upgrade.
- Off-hand weapon comparisons now require dual wield: on characters that
  can't dual-wield, a one-hander no longer glows just because it out-levels a
  shield, an off-hand frill, or an empty off-hand slot. Re-evaluated on spec
  change.
- Guns and crossbows in the main hand now block off-hand weapon glows, like
  bows and two-handers already did. Wands still allow off-hand comparisons.
- Shields only glow for classes that can use them (Warrior, Paladin, Shaman).
- Items above your character's level no longer glow until you can equip them.
- Items BetterBags can't map to an equipment slot (e.g. profession tools) no
  longer glow unconditionally.

## [1.3.0]

- New badges for gear without an upgrade track: Sporefused items show a dark
  green "Spore" and season-crafted items (e.g. "Radiance Crafted") show a
  gold "Craft". These previously showed no badge at all.

## [1.2.4]

- Only glow weapons you can actually equip: weapon types your class can't use
  (e.g. a two-handed axe for a mage, a dagger for a paladin) no longer light up
  as upgrades. Proficiencies are taken per class across all specs.
- Never glow tabards or shirts: these are cosmetic and can carry a stray item
  level, but they never matter for gear, so they no longer light up or badge.

## [1.2.3]

- Only glow armor you can actually wear: items of an armor type your class
  can't main (e.g. a mail piece for a plate wearer) no longer light up as
  upgrades. Cloaks, rings, necks, and trinkets are unaffected.

## [1.2.2]

- Packaging and metadata update for the CurseForge release. No gameplay changes.

## [1.2.1]

- Glow highlight on bag items that out-level your equipped gear.
- Dual-slot aware for rings, trinkets, and weapons (handles main-hand
  two-handers when evaluating the off-hand).
- Upgrade-track badges: Adventurer, Champion, Hero, Myth, Void.
- Highlights refresh on equipment changes and after load.
