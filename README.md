# DzakSharedCDs

A small WoW retail addon that lets a 5-man dungeon group **see each other's major cooldowns** — defensives, offensives, healer CDs — on each party member's frame, without using any restricted API.

How it works in one line: each client broadcasts when it casts a tracked spell over a hidden addon-message channel; receivers render that as an icon with a cooldown swipe on the sender's party frame.

Status: **v0.8.0** — BliZzi_Interrupts-inspired polish: multi-provider unit-frame resolver (ElvUI / Cell / Grid2 / SUF / Danders / EnhanceQoL / Mich's / Blizzard), outward-border icon style with outlined countdown text, versioned wire format `D1;VERB;arg1;...` with multi-channel send fallback (INSTANCE_CHAT → PARTY → WHISPER) for Timed M+ resilience.

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

All inter-client communication goes through one Blizzard `CHAT_MSG_ADDON` prefix: **`DSCD`**. The channel is invisible to chat windows. Four message verbs, all wrapped in a versioned header:

| Wire format                          | Meaning                                                                                            |
| ------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `D1;INIT;<id1>,<id2>,...`            | "Here's the subset of tracked spells I actually have talented." Sent on ready check + other moments. |
| `D1;USED;<spellID>`                  | "I just cast spell `<spellID>`." Triggers a cooldown swipe on the receiver's display.              |
| `D1;READY;<spellID>`                 | "My cooldown for `<spellID>` finished." Triggers the receiver to clear the swipe.                  |
| `D1;PING;<timestamp>`                | Transport-layer delivery test from `/dscd ping`. Receivers print a visible chat line.              |

The `D1` header is a protocol version + sentinel; a future `D2` could be parsed alongside without breaking v1 clients. Multi-arg via semicolons is reserved for future verbs (sender metadata, scheduled-ready timestamps, etc.) without requiring a format change.

The receiver also accepts the legacy `VERB:payload` format (pre-v0.8) so a mixed-version group during rollout stays functional in one direction.

**Distribution strategy** (adopted from BliZzi_Interrupts's BIT.Net):
1. `INSTANCE_CHAT` first when in an instance group (M+, LFG, scenarios) — survives cross-realm shards better than PARTY.
2. `RAID` if in raid, else `PARTY` for normal home groups.
3. Whisper-each-member fallback — rescues Timed M+ scenarios where Blizzard's `ret == 11` blocks the group channels. The block flag is exposed at `ns.AddonMessagesBlocked` for diagnostics.

Throttling: Blizzard caps `SendAddonMessage` at 10-burst + 1/sec recovery per prefix. `Tracker.lua` additionally debounces INIT broadcasts (2.5s coalescing + 3s minimum interval) so a roster cascade or a flurry of talent updates can't spam the channel.

**Verifying delivery**: if you suspect messages aren't getting through, run `/dscd ping` while in a group with another addon user. The recipient sees `received PING from <you>` printed to their chat. As a sanity check that the prefix is registered:

```
/dump C_ChatInfo.IsAddonMessagePrefixRegistered("DSCD")
```

### Sender identification

`CHAT_MSG_ADDON` provides the sender's player name (`"Bob"` same-realm, `"Bob-Realm"` cross-realm). Names are unique per realm and Blizzard adds the realm suffix for cross-realm groups, so two players of the same class — even the same spec — are always distinguishable. `Tracker.lua` resolves sender → unit token by comparing `UnitName(unit)` for every party slot.

As a second line of defense against state pollution, `PruneRoster` records each unit slot's GUID and clears its state if the GUID changes (e.g., `party1` left and a new player took the slot before the next `GROUP_ROSTER_UPDATE` fired).

### The INIT handshake

On a ready check (and a few other natural moments), every client broadcasts an `INIT` message listing the spells in their tracked set that they **actually have talented** (filtered by `C_SpellBook.IsSpellKnown`). Receivers cache this per-sender; the display narrows to spells in that cached set, so abilities a sender doesn't actually have don't sit on their row showing "ready" forever.

Until INIT is received from a sender (but their spec is known), their row shows the **full tracked-for-spec list** as a best guess — better UX than a blank row during the handshake window. When INIT lands, the list shrinks to the advertised intersection.

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

One icon row per group unit, attached to the unit's on-screen frame. The multi-provider resolver in [PartyFrames.lua](PartyFrames.lua) auto-detects (in priority order):

- **ElvUI** (`ElvUF_PartyGroup1`, `ElvUF_Player`)
- **D4 / DandersFrames** (`DandersPartyHeader`)
- **Cell** (`CellPartyFrameHeader`, `CellSoloFramePlayer`)
- **Grid2** (`Grid2LayoutHeader<N>UnitButton`, scans 1..8 sub-headers)
- **EnhanceQoL** (`EQOLUFPartyHeader`)
- **ShadowedUnitFrames** (`SUFHeaderparty`)
- **Mich's RaidFrames** (`MRF_PartyHeader`, `MRF_RaidHeader1..8`)
- **Blizzard** — `CompactPartyFrameMember`, `CompactRaidFrame`, `PartyFrame.MemberFrame`, `PlayerFrame`

Each provider's visibility is checked at resolve time (the addon may be loaded but currently hiding its party header — ElvUI's party + raid headers coexist), and the frame's bound unit is read via `:GetAttribute("unit")` first because the attribute survives child recycling on roster changes. Direct string comparison is used instead of `UnitIsUnit()` to side-step 12.0.5's tainted-bool issue on secret values.

When no provider matches, rows fall back to the FerrozEditModeLib-managed anchor and stagger vertically. A 1s ticker re-resolves the frame so toggling layouts (solo → party → raid) doesn't strand rows on a hidden anchor target.

**Icon style** (BliZzi_Interrupts-inspired):

- **Spell texture** with standard 0.08–0.92 texcoord crop.
- **Cooldown swipe** via Blizzard `CooldownFrameTemplate`. Hidden countdown numbers; we draw our own.
- **Outward border** (sibling Frame anchored slightly larger than the icon, so the backdrop edgeFile sits *outside* the icon area instead of eating into the texture). Size + color configurable via `borderSize` / `borderColor[RGBA]` — set `borderSize = 0` to disable.
- **Outlined countdown text** in `STANDARD_TEXT_FONT` so the look is consistent regardless of whether the user has OmniCC. Format: integer seconds, or `"5m"` once remaining ≥ 60s and `cdShowMinutes` is on.
- **Gray-out on cooldown** (toggle: `cdGrayout`, default ON) — `SetDesaturated(true)` while ticking, restored on `OnCooldownDone`.
- **Tooltip on hover** via `GameTooltip:SetSpellByID`.

**Sizing & positioning** live in **Edit Mode** — press Esc → Edit Mode and click the DzakSharedCDs anchor. The same 5 controls are exposed as a plugin panel via `FerrozEditModeLib`'s `GetOrCreateFrameSpecificControls` hook:

| Setting          | Default  | Range    | Effect                                                              |
| ---------------- | -------- | -------- | ------------------------------------------------------------------- |
| Icon size        | 24 px    | 12–64    | Width and height of every icon.                                     |
| Icon spacing     | 2 px     | 0–16     | Gap between icons.                                                  |
| Grow direction   | Right    | Left/Right | Which way the row extends from the unit's frame.                  |
| Offset X         | 6 px     | -100–100 | Horizontal nudge between the frame edge and the row.                |
| Offset Y         | 0 px     | -100–100 | Vertical nudge.                                                     |

Edit Mode also gives free scale and opacity controls for the anchor itself (via Ferroz's built-in standard controls). All settings persist to `DzakSharedCDsDB.display` / `DzakSharedCDsDB.anchor.layouts.<layoutName>`.

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
  build.ps1               ← packaging script (CurseForge-shaped zip)
  Libs/
    LibStub/
    LibSpecialization/
    FerrozEditModeLib/    ← native Edit Mode integration (replaces LibEditMode)
    NoobTaco-Config/      ← schema-driven Settings UI engine
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
| `/dscd init`       | Print the spell list your next INIT broadcast would announce (tracked ∩ `C_SpellBook.IsSpellKnown`). |
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
        iconSize       = 24,
        iconGap        = 2,
        growDirection  = "RIGHT",
        offsetX        = 6,
        offsetY        = 0,
        borderSize     = 1,       -- outward border thickness (0 disables)
        borderColorR   = 0,
        borderColorG   = 0,
        borderColorB   = 0,
        borderColorA   = 1,
        cdGrayout      = true,    -- desaturate icon while on cooldown
        cdShowMinutes  = true,    -- "5m" instead of "300" when rem >= 60
        cdTextFontSize = 14,
    },
    anchor = {
        layouts = {
            Modern = { point = "CENTER", relativeFrame = UIParent,
                       relativePoint = "CENTER", xOfs = 0, yOfs = 0,
                       scale = 1.0, opacity = 1.0,
                       height = 28, width = 200 },
            -- (one entry per Edit Mode layout the user has touched)
        },
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

Migration:
- v0.2.0+ dropped the old flat `trackedSpells` set from v0.1.0 unconditionally (the migration target was ambiguous).
- v0.7.0 ports `DzakSharedCDsDB.anchor = { point, x, y, enabled }` to FerrozEditModeLib's `{ layouts = { Modern = {...} } }` shape on first load. Legacy keys are cleared after porting.

---

## Module quick reference

### `Debug.lua`
- `ns.Debug:print(label, ...)` — no-op when `DzakSharedCDsDB.debug` is false.
- Slash: `/dscddebug [on|off]`.

### `Anchor.lua`
- `ns.anchorFrame` — `FRAME` registered with **FerrozEditModeLib** (mixes in `EditModeSystemMixin` so the anchor appears alongside native Edit Mode systems). Position / scale / opacity persisted per Edit Mode layout in `DzakSharedCDsDB.anchor.layouts`. Used as the fallback when a unit's Blizzard party frame can't be resolved.
- `anchor:GetOrCreateFrameSpecificControls(socket)` — Ferroz calls this when the user opens its config popup for our frame; we return a plugin panel hosting the 5 display sliders (icon size / spacing / grow / offsetX / offsetY) and a "Reset display defaults" button.

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
- `ns.Chat:Send(verb, ...)` — wraps `C_ChatInfo.SendAddonMessage`. Args are joined into the versioned `D1;VERB;arg1;arg2` wire format. Transport tries `INSTANCE_CHAT` → group channel (`RAID`/`PARTY`) → WHISPER-each-member in order.
- `ns.Chat:SendPing()` — transport delivery test. Prints sender-side status (with `[M+ block detected]` marker when `ret == 11`) and visible chat lines on every recipient.
- `ns.Chat:SetReceiveHandler(fn)` — `fn(senderShortName, verb, payload)` fires on `CHAT_MSG_ADDON` with prefix `DSCD`. PING is handled internally and never reaches this handler. Both `D1;VERB;...` and legacy `VERB:payload` formats are accepted.
- Constants: `ns.Chat.PREFIX = "DSCD"`, `ns.Chat.PROTOCOL_VERSION = "D1"`.
- Diagnostic: `ns.AddonMessagesBlocked` — true after the most recent send returned `ret == 11` (Timed M+ block); cleared on the next successful send.

### `PartyFrames.lua`
- `ns.PartyFrames:Resolve(unit)` → the on-screen frame for `unit`, or nil if no provider matched. Provider precedence (first match wins): ElvUI → Danders → Cell → Grid2 → EnhanceQoL → SUF → Mich's → Blizzard. Adapted from BliZzi_Interrupts/Core/UnitFrames.lua.
- `ns.PartyFrames:GetActiveProviders()` → list of detected provider names (for diagnostics / a possible future "which UI do you use?" prompt).

### `Tracker.lua`
- `ns.Tracker:GetUnitState(unit)` → `{ [spellId] = { startTime, duration, readyAt } }`.
- `ns.Tracker:GetAdvertisedForUnit(unit)` → `{ [spellId] = true }` or nil (no INIT received). For "player", computed on demand from `C_SpellBook.IsSpellKnown`.
- `ns.Tracker:BuildLocalAdvertisedSet()` → the intersection of current spec's tracked list ∩ `C_SpellBook.IsSpellKnown`.
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
- Blizzard Settings canvas hosting a **NoobTaco-Config** two-column layout. Sidebar buttons: **General** (master Enable + slash commands), **Spells** (spec dropdown + per-spec list with override editbox + remove), **About** (version + credits). General / About sections use NoobTaco-Config's schema renderer; the Spells section is built imperatively because the schema doesn't model dynamic per-row composite widgets.
- `ns.OpenSettings()` opens the panel programmatically.

---

## Known limitations / caveats

1. **Cooldown durations are base values, not runtime-modified.** For the local player we cache `C_Spell.GetSpellBaseCooldown(spellId)` at the moment we build the advertised set (using `GetSpellCooldown` at `UNIT_SPELLCAST_SUCCEEDED` time races the engine — it returns 0 or just the GCD). For remote players we look up the same base cooldown on the *receiver's* client. Either way, talent-based CDR (Glimmer-style reductions, etc.) is not reflected. **Workaround**: each row in the Settings spell list has a small "CD override" field — type the correct duration in seconds and it'll win over the API on both the send and receive paths. Leave it blank to use the API value. Stored globally per spell ID in `DzakSharedCDsDB.cooldownOverrides`.

2. **No third-party UI support yet.** Rows attach to default Blizzard frames only (`CompactPartyFrameMemberN`, `PartyFrame.MemberFrameN`, `CompactRaidFrameN`). ElvUI / Grid2 / Vuhdo / Cell / NDui users fall back to the FerrozEditModeLib-managed anchor. Adding more is straightforward — mirror the patterns in MiniCC's `Core/Frames.lua`.

3. **Spec discovery requires LibSpecialization on the party member's side.** Standalone but most addons ship it. Without it, their row stays hidden because we don't know their spec.

4. **INIT must fit in 255 chars.** Each spell ID is at most 7 digits + comma = 8 chars, so the practical ceiling is ~30 IDs per INIT. None of the bundled defaults come close (longest is Disc/Holy Pal at ~11 spells). A user with a heavily-customized spec list could theoretically truncate; we'd then need to split into `INIT/1of2:...` chunks. Not worth implementing yet.

5. **Default-seeding is one-shot per spec.** If a future version adds new defaults to a spec, existing users won't get them automatically (avoids clobbering edits). They can use the "Reset This Spec" button in Settings to opt in.

6. **Sender-side cooldown reset detection is best-effort.** If you cast a tracked spell and a talent / proc later resets its cooldown, the addon will still broadcast `READY` at the originally-scheduled time, leading to a brief misrepresentation on receivers' screens.

---

## Reference projects

- `C:\Repos\WoW\DzakTools\` — the skeleton template this addon was built from (Debug / Anchor / Settings / Main pattern + LibStub + LibEditMode).
- `C:\Repos\WoW\MiniCC\` — visual + structural reference (icon row, cooldown swipe, third-party party-frame discovery in `Core/Frames.lua`, LibSpecialization integration).
