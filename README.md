# DzakSharedCDs

A small WoW retail addon that lets a 5-man dungeon group **see each other's major cooldowns** — defensives, offensives, healer CDs — on each party member's frame, without using any restricted API.

How it works in one line: each client broadcasts when it casts a tracked spell over a hidden addon-message channel; receivers render that as an icon with a cooldown swipe on the sender's party frame.

Status: **v0.6.0** — untested in a live group as of this commit. Code complete; awaiting in-game verification.

---

## Why this exists

Blizzard locks down most cross-player cooldown inspection. Every "see your party's cooldowns" addon (OmniCD, MiniCC's `FriendlyCooldowns`, etc.) either uses 1000+ LOC of spec/talent inspection plumbing, or pays the same data-staleness cost. This addon takes a different tradeoff: each client just **tells** the others what it did, over the standard addon-message channel. Tiny code surface, very accurate timing for the sender, slightly approximate for everyone else.

The flip side: it only works for **other party members who also run DzakSharedCDs**. Party members without the addon are invisible to it.

---

## Installation

1. Drop the `DzakSharedCDs` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. `/reload` in-game.
3. The addon seeds its tracked-spell list from `ClassDefaults.lua` for your current spec on first run. Open `/dscd` to edit it (per spec).

---

## Building a release zip (for CurseForge / sharing with testers)

CurseForge rejects zips whose files sit at the top level — everything must live inside a single root folder named after the addon. Run the bundled build script to produce a correctly-shaped zip:

```powershell
pwsh ./build.ps1
```

Output: `dist/DzakSharedCDs-<version>.zip`. The script:

- Reads the version from `DzakSharedCDs.toc`
- Stages only the addon files (`*.lua`, `*.toc`, `README.md`, `Libs/`) into `dist/staging/DzakSharedCDs/`
- Skips reference projects (`MiniCC/`, `LuraMemorySync*/`, `TerribleLuraHelper/`), `.claude/`, `.git/`
- Zips the staging folder so `DzakSharedCDs/` is the top entry

To verify before uploading:

```powershell
Expand-Archive -Path dist/DzakSharedCDs-<version>.zip -DestinationPath dist/_verify -Force
ls dist/_verify
# should print: DzakSharedCDs
```

---

## How it works

### The wire protocol

All inter-client communication goes through one Blizzard `CHAT_MSG_ADDON` prefix: **`DSCD`**. The channel is invisible to chat windows. Four message verbs:

| Wire format                      | Meaning                                                                                            |
| -------------------------------- | -------------------------------------------------------------------------------------------------- |
| `INIT:<id1>,<id2>,...`           | "Here's the subset of tracked spells I actually have talented." Sent on ready check + other moments. |
| `USED:<spellID>`                 | "I just cast spell `<spellID>`." Triggers a cooldown swipe on the receiver's display.              |
| `READY:<spellID>`                | "My cooldown for `<spellID>` finished." Triggers the receiver to clear the swipe.                  |
| `PING:<timestamp>`               | Transport-layer delivery test from `/dscd ping`. Receivers print a visible chat line.              |

**Distribution**: PARTY for parties, RAID for raids — never INSTANCE_CHAT, even inside dungeons. This mirrors `LuraMemorySync` (a known-working production addon bundled alongside this one for reference); some wiki guidance says addon messages "should" use INSTANCE_CHAT in instances but real-world deployment doesn't.

Throttling: Blizzard caps `SendAddonMessage` at 10-burst + 1/sec recovery per prefix. `Tracker.lua` additionally debounces INIT broadcasts (2.5s coalescing + 3s minimum interval) so a roster cascade or a flurry of talent updates can't spam the channel.

**Verifying delivery**: if you suspect messages aren't getting through, run `/dscd ping` while in a group with another addon user. The recipient sees `received PING from <you>` printed to their chat. As a sanity check that the prefix is registered:

```
/dump C_ChatInfo.IsAddonMessagePrefixRegistered("DSCD")
```

### Sender identification

`CHAT_MSG_ADDON` provides the sender's player name (`"Bob"` same-realm, `"Bob-Realm"` cross-realm). Names are unique per realm and Blizzard adds the realm suffix for cross-realm groups, so two players of the same class — even the same spec — are always distinguishable. `Tracker.lua` resolves sender → unit token by comparing `UnitName(unit)` for every party slot.

As a second line of defense against state pollution, `PruneRoster` records each unit slot's GUID and clears its state if the GUID changes (e.g., `party1` left and a new player took the slot before the next `GROUP_ROSTER_UPDATE` fired).

### The INIT handshake

On a ready check (and a few other natural moments), every client broadcasts an `INIT` message listing the spells in their tracked set that they **actually have talented** (filtered by `IsPlayerSpell`). Receivers cache this per-sender; the display only renders spells in that cached set, so abilities a sender doesn't actually have don't sit on their row showing "ready" forever.

Until INIT is received from a sender, their row is **hidden entirely** — no guessing. The local player's row is always shown (their advertised set is computed on demand).

INIT triggers:

- `READY_CHECK` — primary trigger. Also invalidates every other player's cached set, so all rows briefly blank then repopulate as their INITs flow in. Visible refresh cue.
- `PLAYER_ENTERING_WORLD` — login / reload / zone change.
- `GROUP_ROSTER_UPDATE` — someone joined; they need our list, we may want theirs.
- `PLAYER_SPECIALIZATION_CHANGED` — spec swap.
- `TRAIT_CONFIG_UPDATED` / `ACTIVE_COMBAT_CONFIG_CHANGED` — talent change.

### Spec discovery

Done via **LibSpecialization** (bundled, copied from MiniCC). It uses its own coordination channel and is loaded by most major addons (WeakAuras, BigWigs, OmniCD, …). When a callback fires with `(specId, role, position, playerName)`, `SpecCache.lua` caches `name → specId`.

If a party member runs none of those addons, their spec is unknown and their row stays hidden until they cast something AND we learn their spec.

### Display

One icon row per group unit, attached to the unit's Blizzard frame. Supports:

- **Party frames** — `CompactPartyFrameMemberN`, `PartyFrame.MemberFrameN`
- **Raid frames** — `CompactRaidFrameN` (also picked up when "Raid-style frames for parties" is enabled)

When no matching frame is visible (typical for ElvUI / Grid2 / Vuhdo / Cell users), rows fall back to a `LibEditMode`-managed anchor and stagger vertically. A 1s ticker re-resolves the frame so toggling layouts (solo → party → raid) doesn't strand rows on a hidden anchor target.

Icons: bright when ready, desaturated + clockwise swipe + countdown text when on cooldown. Spell tooltip on hover.

**Sizing & positioning** are tunable in the Settings panel's "Display" column:

| Setting          | Default  | Range    | Effect                                                              |
| ---------------- | -------- | -------- | ------------------------------------------------------------------- |
| Icon size        | 24 px    | 12–64    | Width and height of every icon.                                     |
| Icon spacing     | 2 px     | 0–16     | Gap between icons.                                                  |
| Grow direction   | Right    | Left/Right | Which way the row extends from the unit's frame.                  |
| Offset X         | 6 px     | -100–100 | Horizontal nudge between the frame edge and the row.                |
| Offset Y         | 0 px     | -100–100 | Vertical nudge.                                                     |

All changes apply immediately — sliders trigger `Display:UpdateAll` on every step. Persisted to `DzakSharedCDsDB.display`.

---

## File layout

```
DzakSharedCDs/
  DzakSharedCDs.toc       ← TOC: interfaces 120005, 120007 (Midnight); SavedVariables DzakSharedCDsDB
  README.md               ← this file
  Debug.lua               ← /dscddebug + ns.Debug:print(label, ...) (no-op when disabled)
  Anchor.lua              ← ns.anchorFrame (LibEditMode-managed fallback)
  ClassDefaults.lua       ← DEFAULT_SPELLS_BY_SPEC + ALL_SPECS + GetSpecInfo/FormatSpecLabel
  SpecCache.lua           ← LibSpecialization wrapper: name → specId
  Chat.lua                ← CHAT_MSG_ADDON wire layer (send + receive on prefix "DSCD")
  PartyFrames.lua         ← unit token → Blizzard CompactPartyFrame or PartyFrame member frame
  Tracker.lua             ← cooldown state, INIT handshake, local + remote flows
  Display.lua             ← per-unit icon row attached to party frame
  Main.lua                ← DB seeding, ns.* helpers, event hookup, /dscd slash command
  Settings.lua            ← Blizzard Settings canvas: spec dropdown + per-spec spell list
  Libs/
    LibStub/
    LibEditMode/
    LibSpecialization/
```

Load order matters (declared in the TOC, top → bottom):

```
Libs ............................. third-party
Debug ............................ ns.Debug (no deps)
Anchor ........................... ns.anchorFrame (uses ns.Debug, LibEditMode)
ClassDefaults .................... ns.DEFAULT_SPELLS_BY_SPEC, ns.ALL_SPECS
SpecCache ........................ ns.SpecCache (uses LibSpecialization)
Chat ............................. ns.Chat (no other ns deps)
PartyFrames ...................... ns.PartyFrames (no other ns deps)
Tracker .......................... ns.Tracker (uses Chat, SpecCache, ClassDefaults)
Display .......................... ns.Display (uses Tracker, SpecCache, PartyFrames, Anchor)
Main ............................. seeds DB, wires events, registers /dscd
Settings ......................... uses ns.* helpers from Main + ClassDefaults
```

---

## Slash commands

| Command            | Description                                                                 |
| ------------------ | --------------------------------------------------------------------------- |
| `/dscd`            | Open the Settings canvas panel.                                             |
| `/dscd status`     | Print a one-screen state summary (enabled, local spec, specs configured, group/instance). |
| `/dscd init`       | Print the spell list your next INIT broadcast would announce (tracked ∩ `IsPlayerSpell`). |
| `/dscd broadcast`  | Force an immediate INIT broadcast (bypasses the debounce).                  |
| `/dscd ping`       | Transport delivery test. Sends a ping; receivers print a visible confirmation. |
| `/dscddebug`       | Toggle debug tracing (on/off/toggle). When on, every wire send + receive logs. |

---

## SavedVariables shape

```lua
DzakSharedCDsDB = {
    enabled = true,
    debug = false,
    anchor = { point = "CENTER", x = 0, y = 0, enabled = true },
    display = {
        iconSize      = 24,
        iconGap       = 2,
        growDirection = "RIGHT",
        offsetX       = 6,
        offsetY       = 0,
    },
    trackedSpellsBySpec = {
        [65]  = { [642] = true, [498] = true, ... },     -- Holy Paladin
        [256] = { [33206] = true, [62618] = true, ... }, -- Disc Priest
        ...
    },
    cooldownOverrides = {
        [642]   = 300,   -- Divine Shield: force 5 min, ignore API
        [33206] = 360,   -- Pain Suppression: force 6 min
        -- absent entries fall through to GetSpellBaseCooldown
    },
}
```

Per-spec lists are seeded **lazily** from `ns.DEFAULT_SPELLS_BY_SPEC[specId]` the first time a spec is observed (locally or via a party member's LibSpecialization broadcast). After that, edits persist; explicitly emptying a spec's list will not re-seed.

Migration: v0.2.0+ dropped the old flat `trackedSpells` set from v0.1.0 unconditionally (the migration target was ambiguous).

---

## Module quick reference

### `Debug.lua`
- `ns.Debug:print(label, ...)` — no-op when `DzakSharedCDsDB.debug` is false.
- Slash: `/dscddebug [on|off]`.

### `Anchor.lua`
- `ns.anchorFrame` — `FRAME` registered with LibEditMode, draggable in Edit Mode, position persisted to `DzakSharedCDsDB.anchor`. Used as the fallback when a unit's Blizzard party frame can't be resolved.

### `ClassDefaults.lua`
- `ns.DEFAULT_SPELLS_BY_SPEC[specId] = { [spellId] = true, ... }` — ~265 spell IDs across all 39 retail specs, defensives / offensives / healer CDs only (≥45s cooldowns). Verified against Wowhead / Warcraft Wiki for Midnight 12.0.x.
- `ns.ALL_SPECS` — ordered list of `{ specId, classToken, className, specName, role }`.
- `ns.GetSpecInfo(specId)` / `ns.FormatSpecLabel(specId)` — display helpers.

### `SpecCache.lua`
- `ns.SpecCache:GetLocalSpec()` → specId or nil.
- `ns.SpecCache:GetSpecForUnit(unit)` → specId or nil.
- `ns.SpecCache:SetChangeHandler(fn)` — fires `fn(playerShortName, specId)` when someone's spec is first learned or changes.

Internally wraps `LibSpecialization.RegisterGroup`.

### `Chat.lua`
- `ns.Chat:Send(verb, payload)` — wraps `C_ChatInfo.SendAddonMessage`. Distribution is `RAID` in raids, `PARTY` otherwise. Never `INSTANCE_CHAT` (LuraMemorySync precedent).
- `ns.Chat:SendPing()` — transport delivery test. Prints sender-side status and visible chat lines on every recipient.
- `ns.Chat:SetReceiveHandler(fn)` — `fn(senderShortName, verb, payload)` fires on `CHAT_MSG_ADDON` with prefix `DSCD`. PING is handled internally and never reaches this handler.
- Constant: `ns.Chat.PREFIX = "DSCD"`.

### `PartyFrames.lua`
- `ns.PartyFrames:Resolve(unit)` → the Blizzard frame for `unit`, or nil if none is visible. Supports `CompactRaidFrameN` (preferred in raids), `CompactPartyFrameMemberN`, and `PartyFrame.MemberFrameN`. Falls back to a CompactRaid scan to catch the "Raid-style frames for parties" mode.

### `Tracker.lua`
- `ns.Tracker:GetUnitState(unit)` → `{ [spellId] = { startTime, duration, readyAt } }`.
- `ns.Tracker:GetAdvertisedForUnit(unit)` → `{ [spellId] = true }` or nil (no INIT received). For "player", computed on demand from `IsPlayerSpell`.
- `ns.Tracker:BuildLocalAdvertisedSet()` → the intersection of current spec's tracked list ∩ `IsPlayerSpell`.
- `ns.Tracker:ScheduleInitBroadcast(delaySeconds?)` — debounced INIT send.
- `ns.Tracker:OnLocalCast(spellId)` — entry point used by `UNIT_SPELLCAST_SUCCEEDED`.
- `ns.Tracker:OnRemoteMessage(sender, verb, payload)` — entry point used by `Chat`.
- `ns.Tracker:PruneRoster()` — drops state for departed units; clears state for unit slots whose GUID changed.

### `Display.lua`
- `ns.Display:UpdateUnit(unit)` — re-render one unit's row.
- `ns.Display:UpdateAll()` — re-render every group unit's row.
- `ns.Display:StartTicker()` — kicks off the 1s re-anchor ticker.

### `Main.lua`
- `ns.IsEnabled()` / `ns.SetEnabled(value)`.
- `ns.EnsureSpecSeeded(specId)` — lazy default-seeding.
- `ns.GetTrackedForSpec(specId)` → that spec's tracked set (or nil).
- `ns.ResetSpecToDefaults(specId)` / `ns.AddTracked(specId, spellId)` / `ns.RemoveTracked(specId, spellId)`.
- `ns.GetDisplaySetting(key)` / `ns.SetDisplaySetting(key, value)` / `ns.ResetDisplayDefaults()` — display config, persisted to `DzakSharedCDsDB.display`; setter triggers `Display:UpdateAll`.
- Constant: `ns.DEFAULT_DISPLAY` — single source of truth for the display defaults table.
- `ns.GetCooldownOverride(spellId)` / `ns.SetCooldownOverride(spellId, seconds)` — manual per-spell duration override. Returns nil / passes nil-or-≤0 to clear. Consulted by Tracker on both local cast and remote receive paths.
- Slash: `/dscd`, `/dscd status`, `/dscd init`, `/dscd broadcast`, `/dscd ping`.

### `Settings.lua`
- Blizzard Settings canvas. Left column: master Enable checkbox + spec dropdown (grouped by class) + per-spec spell list. Each row has the icon, ID + name, a small **CD override** EditBox (blank = use API, number = force seconds), and an X to remove. Right column: Display settings (icon size, spacing, grow direction, X/Y offset, Reset display defaults). Bottom: slash command reference.
- `ns.OpenSettings()` opens the panel programmatically.

---

## Known limitations / caveats

1. **Cooldown durations are base values, not runtime-modified.** For the local player we cache `C_Spell.GetSpellBaseCooldown(spellId)` at the moment we build the advertised set (using `GetSpellCooldown` at `UNIT_SPELLCAST_SUCCEEDED` time races the engine — it returns 0 or just the GCD). For remote players we look up the same base cooldown on the *receiver's* client. Either way, talent-based CDR (Glimmer-style reductions, etc.) is not reflected. **Workaround**: each row in the Settings spell list has a small "CD override" field — type the correct duration in seconds and it'll win over the API on both the send and receive paths. Leave it blank to use the API value. Stored globally per spell ID in `DzakSharedCDsDB.cooldownOverrides`.

2. **No third-party UI support yet.** Rows attach to default Blizzard frames only (`CompactPartyFrameMemberN`, `PartyFrame.MemberFrameN`, `CompactRaidFrameN`). ElvUI / Grid2 / Vuhdo / Cell / NDui users fall back to the LibEditMode anchor. Adding more is straightforward — mirror the patterns in MiniCC's `Core/Frames.lua`.

3. **Spec discovery requires LibSpecialization on the party member's side.** Standalone but most addons ship it. Without it, their row stays hidden because we don't know their spec.

4. **INIT must fit in 255 chars.** Each spell ID is at most 7 digits + comma = 8 chars, so the practical ceiling is ~30 IDs per INIT. None of the bundled defaults come close (longest is Disc/Holy Pal at ~11 spells). A user with a heavily-customized spec list could theoretically truncate; we'd then need to split into `INIT/1of2:...` chunks. Not worth implementing yet.

5. **Default-seeding is one-shot per spec.** If a future version adds new defaults to a spec, existing users won't get them automatically (avoids clobbering edits). They can use the "Reset This Spec" button in Settings to opt in.

6. **Sender-side cooldown reset detection is best-effort.** If you cast a tracked spell and a talent / proc later resets its cooldown, the addon will still broadcast `READY` at the originally-scheduled time, leading to a brief misrepresentation on receivers' screens.

---

## Reference projects

- `C:\Repos\WoW\DzakTools\` — the skeleton template this addon was built from (Debug / Anchor / Settings / Main pattern + LibStub + LibEditMode).
- `C:\Repos\WoW\MiniCC\` — visual + structural reference (icon row, cooldown swipe, third-party party-frame discovery in `Core/Frames.lua`, LibSpecialization integration).
