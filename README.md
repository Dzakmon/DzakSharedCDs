# DzakSharedCDs

Party cooldown display for retail WoW (12.0 / Midnight). Shows timer bars for
party cooldowns like Anti-Magic Zone, Darkness and Zephyr.

## How it works

A generated macro casts your spell and types a tagged line into party chat:

```
DSCD1:51052:8:120 AMZ down
```

Everyone running the addon matches that line and draws a bar. Everyone *not*
running it just sees a readable "AMZ down" in chat.

The transport is deliberately plain visible chat rather than a hidden addon
channel. That has one large payoff: **the sender does not need this addon.**
The macro is only text, so anyone in the group can broadcast, and the duration
and cooldown travel inside the message — a receiver can display a spell it has
no local configuration for.

Zero dependencies. Two Lua files. No LibStub, no Ace3.

## Commands

```
/dscd add <spellID> <duration> <cooldown> [castModifier]
/dscd remove <spellID>
/dscd list
/dscd macro                  (re)generate all macros
/dscd unlock | lock          move the anchor
/dscd grow                   flip growth direction
/dscd test <spellID>         fake an inbound message locally
/dscddebug                   toggle debug output
```

`castModifier` is optional and passed through to `/cast` — use `@cursor` for
reticle spells like Darkness.

## Setup

1. Install, `/reload`.
2. `/dscd macro` — creates one macro per configured spell, out of combat.
3. Drag the macros to your bars.
4. `/dscd unlock`, position the anchor, `/dscd lock`.

Three spells ship configured by default. Add more with `/dscd add`.

## Known limitations

- A macro types its chat line even if the cast failed (out of range, silenced,
  interrupted), so a timer can be wrong. Accepted tradeoff — detecting this
  reliably would mean the combat log, which is not used here.
- Party only. No raid channel.
- Durations are static. Talent and tier effects that change them are not
  accounted for; correct the values yourself with `/dscd add`.
