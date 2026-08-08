# DzakSharedCDs — WoW party cooldown display

Retail WoW addon (12.0 / Midnight). Shows party cooldown timers on screen.
Broadcast is plain `/p` chat with a parseable tag. Reusing an existing
CurseForge project entry, so identifiers below are fixed by that entry.

## Identifiers (do not change without saying so)

| Thing | Value |
|---|---|
| Addon folder / TOC filename | `DzakSharedCDs` |
| SavedVariables | `DzakSharedCDsDB` |
| Message tag | `DSCD1` |
| Generated macro names | `DSCD_<spellID>` |
| Slash command | `/dscd` |

Folder name must match what the CurseForge project packages, and
`DzakSharedCDs.toc` must match the folder name exactly or the addon won't load.

## Hard constraints

- **Do not use `COMBAT_LOG_EVENT_UNFILTERED` for anything.** Combat log
  reliability regressed in 12.0. This is a deliberate design decision, not an
  oversight. Do not "improve" the addon by adding CLEU detection.
- **Keep the transport dumb.** Visible `/p` chat, one line, string match. No
  addon comms, no serialization libs, no LibStub, no Ace3. Zero dependencies.
- **The sender may not have the addon.** The macro is just text, so anyone can
  broadcast. Receivers must never assume sender-side state.
- **Duration and cooldown travel in the message**, not in receiver config. A
  receiver displays whatever it is told, with no local setup for that spell.
- Timers can be wrong — a macro fires its chat line even when the cast failed.
  Accepted tradeoff. Do not add complexity to work around it.

## Working rules

- State a plan and wait for approval before writing or changing code.
- Minimal diff. No unsolicited refactors, no premature abstraction.
- Push back on over-engineering rather than implementing it.

## WoW API pitfalls

- 12.0 "secret values": `UnitClassFromGUID` accepts them, `UnitClass` and
  `UnitClassBase` do not. Use the GUID variant for class colors.
- `CreateMacro` / `EditMacro` are protected in combat. Guard with
  `InCombatLockdown()` and tell the user to retry out of combat.
- Chat event arg12 is the sender GUID. That is the only reliable identity
  source here.
- Build spell names via `C_Spell.GetSpellInfo(id).name` so macros work on
  non-English clients. Never hardcode English spell names.
- Macro names are capped at 16 characters; `DSCD_` + a 7-digit ID still fits.
- TOC `## Interface:` value comes from `/dump select(4, GetBuildInfo())`.

## Files

```
DzakSharedCDs.toc
Debug.lua           -- /dscddebug toggle, ns.Debug:print(label, ...)
DzakSharedCDs.lua   -- everything else: parse, display, macros, slash
```

`DzakSharedCDs.lua` is ~520 lines, over the spec's original ~400 single-file
guidance — largely comment volume, and the sections (pool / display / macros /
slash) are already cleanly separated. Split it at the section boundaries when a
real feature needs the room, not as housekeeping.

## Testing

No unit tests. The loop is: edit files in the live AddOns folder, `/reload`
in game, use `/dscd test <spellID>` to fake an inbound message so the display
can be iterated solo without a party. `/dscddebug on` for trace output.

## History

v1.0.0 is a from-scratch rewrite. Everything before it — hidden
`CHAT_MSG_ADDON` transport, NoobTaco-Config options panel, LibSpecialization
spec detection, per-spec class defaults — is tagged `v0.11.0-legacy` and was
abandoned, not evolved. Don't mine it for patterns; it contradicts the
constraints above.

## Current work

See @Plans/SPEC.md for the v1 build spec.
