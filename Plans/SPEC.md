# v1 build spec

Status: implemented in v1.0.0, not yet tested in game.

Spell durations and cooldowns in the table below are still unverified against
12.0 — they ship as defaults but correct them with `/dscd add` once checked.

## Goal

Party members broadcast a cooldown usage via a generated macro. Everyone
running the addon sees a timer bar. Spells are configured manually by ID,
duration and cooldown — nothing is auto-detected.

Initial spells (values must be verified in game before hardcoding as defaults;
they predate 12.0):

| Spell | ID | Duration | CD | Notes |
|---|---|---|---|---|
| Anti-Magic Zone | 51052 | 8s | 120s | |
| Darkness | 196718 | 8s | 300s | reticle — needs `@cursor` |
| Zephyr | 374227 | 8s | 120s | |

## Message format

```
DSCD1:51052:8:120 AMZ down
```

Parse with `^DSCD1:(%d+):([%d%.]+):(%d+)` — anchored at string start so human
chat cannot trigger it accidentally.

- `DSCD1` — format version. Bump to `DSCD2` if the layout ever changes, so
  old clients ignore rather than misparse.
- Fields: spellID, duration (seconds, may be fractional), cooldown (seconds).
- Everything after the tag is free text, ignored by the parser. It exists so
  party members without the addon see something meaningful in chat.
- Icon and localized spell name are looked up locally from the ID. They do not
  travel in the message.

## Config

SavedVariables only. No options panel in v1.

```
/dscd add <spellID> <duration> <cooldown> [castModifier]
/dscd remove <spellID>
/dscd list
/dscd macro                  -- (re)generate all macros
/dscd unlock | lock          -- move the anchor
/dscd test <spellID>         -- fake an inbound message locally
```

`castModifier` is optional, e.g. `@cursor` for Darkness. Passed by the user
rather than hardcoded per spell, so patch changes don't require a code change.

## Macro generation

One macro per configured spell, named `DSCD_<spellID>`, icon from
`C_Spell.GetSpellTexture(id)`, created with `CreateMacro` or updated with
`EditMacro` if it already exists. Body:

```
#showtooltip <spellName>
/p DSCD1:51052:8:120 AMZ down
/cast <spellName>
```

Refuse to run in combat (`InCombatLockdown()`), with a message telling the user
to retry. 120 global macro slots available, no realistic ceiling at this scale.

## Display

This is the hard part and where the effort goes.

- **One anchor frame.** Movable only while unlocked. Position persisted in
  SavedVariables. All bars parent to it.
- **One `OnUpdate` on the anchor**, throttled to ~0.05s, iterating active bars.
  Not one `OnUpdate` per bar.
- **Bar pool.** Acquire and release, never destroy. Prevents frame leaks over
  a long session.
- **Two states, one bar.** Bright while the effect is up, counting the duration.
  On expiry the same bar dims and counts down the remaining cooldown, then
  releases. One code path, one sort key, no second list.
- **Sort by remaining time ascending**, so the next expiry is always at the same
  edge. Growth direction (up/down) configurable.
- **Row contents:** spell icon, class-colored caster name (realm suffix
  stripped), spell name, remaining seconds.
- **Class color** from `UnitClassFromGUID(senderGUID)` using chat event arg12.
- **Dedupe** on `guid..spellID` within 1s so a double macro press doesn't stack
  two bars.

## Events

`CHAT_MSG_PARTY` and `CHAT_MSG_PARTY_LEADER` only. No CLEU. No raid channel in
v1.

## Files

```
DzakSharedCDs/
  DzakSharedCDs.toc      ## SavedVariables: DzakSharedCDsDB
  DzakSharedCDs.lua
```

## Explicitly out of scope for v1

Cancel/early-expiry messages, talent-aware durations, options panel, raid
channel support, sound or TTS, spec detection, automation of any kind.
