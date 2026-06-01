-- Per-spec default tracked-spell lists. Scope: defensive, offensive, and
-- healer cooldowns only. Excluded: interrupts, CC, combat-res, trinkets,
-- racials, sub-45s utility (except three tracked-everywhere exceptions
-- documented at the relevant entries).
--
-- v0.11.0: STRICT reference-only rebuild. Every entry traces back to
-- either PetesDefensiveHistory's `AbilityDb` (flagged IMPORTANT / BIG /
-- EXTERNAL / RAID) or Blizzi_Interrupts's `SPELL_DEFS`. Anything we'd
-- previously added on our own without source backing has been dropped.
--
-- Some specs end up thin (Warlocks at 1 entry, Aug Evoker at 1) because
-- neither reference DB flags many cooldowns for them. The Settings panel
-- lets users add their own per spec; the defaults are a conservative
-- starting point, not an attempt at completeness.

local addonName, ns = ...

ns.DEFAULT_SPELLS_BY_SPEC = {
	-- ============ DEATH KNIGHT ============
	[250] = { -- Blood
		[48707] = true, -- Anti-Magic Shell
		[48792] = true, -- Icebound Fortitude
		[55233] = true, -- Vampiric Blood (talent)
	},
	[251] = { -- Frost
		[48707] = true, -- Anti-Magic Shell
		[48792] = true, -- Icebound Fortitude
		[51271] = true, -- Pillar of Frost
	},
	[252] = { -- Unholy
		[48707] = true, -- Anti-Magic Shell
		[48792] = true, -- Icebound Fortitude
	},

	-- ============ DEMON HUNTER ============
	[577] = { -- Havoc
		[198589] = true, -- Blur
		[191427] = true, -- Metamorphosis
	},
	[581] = { -- Vengeance
		[187827] = true, -- Metamorphosis
		[204021] = true, -- Fiery Brand
		[198589] = true, -- Blur (talent)
		[209258] = true, -- Last Resort (talent)
	},

	-- ============ DRUID ============
	[102] = { -- Balance
		[22812]  = true, -- Barkskin
		[194223] = true, -- Celestial Alignment
		[102560] = true, -- Incarnation: Chosen of Elune (talent)
	},
	[103] = { -- Feral
		[22812]  = true, -- Barkskin
		[106951] = true, -- Berserk
		[102543] = true, -- Incarnation: Avatar of Ashamane (talent)
	},
	[104] = { -- Guardian
		[22812]  = true, -- Barkskin
		[50334]  = true, -- Berserk
		[102558] = true, -- Incarnation: Guardian of Ursoc (talent)
	},
	[105] = { -- Restoration
		[22812]  = true, -- Barkskin
		[102342] = true, -- Ironbark
	},

	-- ============ EVOKER ============
	[1467] = { -- Devastation
		[363916] = true, -- Obsidian Scales
		[375087] = true, -- Dragonrage
	},
	[1468] = { -- Preservation
		[363916] = true, -- Obsidian Scales
		[357170] = true, -- Time Dilation (talent)
	},
	[1473] = { -- Augmentation
		[363916] = true, -- Obsidian Scales
	},

	-- ============ HUNTER ============
	[253] = { -- Beast Mastery
		[186265] = true, -- Aspect of the Turtle
		[264735] = true, -- Survival of the Fittest
		[109304] = true, -- Exhilaration
	},
	[254] = { -- Marksmanship
		[186265] = true, -- Aspect of the Turtle
		[264735] = true, -- Survival of the Fittest
		[109304] = true, -- Exhilaration
		[288613] = true, -- Trueshot
	},
	[255] = { -- Survival
		[186265]  = true, -- Aspect of the Turtle
		[264735]  = true, -- Survival of the Fittest
		[109304]  = true, -- Exhilaration
		[1250646] = true, -- Takedown
	},

	-- ============ MAGE ============
	[62] = { -- Arcane
		[45438]  = true, -- Ice Block
		[55342]  = true, -- Mirror Image (talent)
		[342245] = true, -- Alter Time
		[365350] = true, -- Arcane Surge
		[414659] = true, -- Ice Cold (talent)
	},
	[63] = { -- Fire
		[45438]  = true, -- Ice Block
		[55342]  = true, -- Mirror Image (talent)
		[190319] = true, -- Combustion
		[342245] = true, -- Alter Time
		[414659] = true, -- Ice Cold (talent)
	},
	[64] = { -- Frost
		[45438]  = true, -- Ice Block
		[55342]  = true, -- Mirror Image (talent)
		[110959] = true, -- Greater Invisibility (talent)
		[342245] = true, -- Alter Time
		[414659] = true, -- Ice Cold (talent)
	},

	-- ============ MONK ============
	[268] = { -- Brewmaster
		[115203] = true, -- Fortifying Brew
		[132578] = true, -- Invoke Niuzao, the Black Ox
	},
	[270] = { -- Mistweaver
		[115203] = true, -- Fortifying Brew
		[116849] = true, -- Life Cocoon
	},
	[269] = { -- Windwalker
		[115203]  = true, -- Fortifying Brew
		[122470]  = true, -- Touch of Karma (talent)
		[1249625] = true, -- Zenith
	},

	-- ============ PALADIN ============
	[65] = { -- Holy
		[498]    = true, -- Divine Protection
		[642]    = true, -- Divine Shield
		[1022]   = true, -- Blessing of Protection
		[6940]   = true, -- Blessing of Sacrifice
		[31884]  = true, -- Avenging Wrath
		[216331] = true, -- Avenging Crusader (talent)
	},
	[66] = { -- Protection
		[498]    = true, -- Divine Protection
		[642]    = true, -- Divine Shield
		[1022]   = true, -- Blessing of Protection
		[6940]   = true, -- Blessing of Sacrifice
		[204018] = true, -- Blessing of Spellwarding (talent)
		[31850]  = true, -- Ardent Defender
		[31884]  = true, -- Avenging Wrath
		[86659]  = true, -- Guardian of Ancient Kings
		[389539] = true, -- Sentinel (talent)
	},
	[70] = { -- Retribution
		[642]    = true, -- Divine Shield
		[1022]   = true, -- Blessing of Protection
		[6940]   = true, -- Blessing of Sacrifice
		[31884]  = true, -- Avenging Wrath
		[255937] = true, -- Wake of Ashes (30s, kept as a tracked-everywhere exception)
		[403876] = true, -- Divine Protection (Ret variant, talent)
	},

	-- ============ PRIEST ============
	[256] = { -- Discipline
		[19236] = true, -- Desperate Prayer
		[33206] = true, -- Pain Suppression
	},
	[257] = { -- Holy
		[19236] = true, -- Desperate Prayer
		[47788] = true, -- Guardian Spirit
		[64843] = true, -- Divine Hymn
	},
	[258] = { -- Shadow
		[19236]  = true, -- Desperate Prayer
		[47585]  = true, -- Dispersion
		[228260] = true, -- Voidform
	},

	-- ============ ROGUE ============
	[259] = { -- Assassination
		[5277]  = true, -- Evasion
		[31224] = true, -- Cloak of Shadows
	},
	[260] = { -- Outlaw
		[5277]  = true, -- Evasion
		[13750] = true, -- Adrenaline Rush
		[31224] = true, -- Cloak of Shadows
	},
	[261] = { -- Subtlety
		[5277]   = true, -- Evasion
		[31224]  = true, -- Cloak of Shadows
		[121471] = true, -- Shadow Blades (talent)
	},

	-- ============ SHAMAN ============
	[262] = { -- Elemental
		[108271] = true, -- Astral Shift
		[114050] = true, -- Ascendance (talent)
	},
	[263] = { -- Enhancement
		[108271] = true, -- Astral Shift
		[114051] = true, -- Ascendance (talent)
		[384352] = true, -- Doom Winds (talent)
	},
	[264] = { -- Restoration
		[108271] = true, -- Astral Shift
		[114052] = true, -- Ascendance (talent)
	},

	-- ============ WARLOCK ============
	[265] = { -- Affliction
		[104773] = true, -- Unending Resolve
	},
	[266] = { -- Demonology
		[104773] = true, -- Unending Resolve
	},
	[267] = { -- Destruction
		[104773] = true, -- Unending Resolve
	},

	-- ============ WARRIOR ============
	[71] = { -- Arms
		[23920]  = true, -- Spell Reflection (25s, kept as a tracked-everywhere exception)
		[107574] = true, -- Avatar
		[118038] = true, -- Die by the Sword
	},
	[72] = { -- Fury
		[23920]  = true, -- Spell Reflection (25s exception)
		[107574] = true, -- Avatar
		[184364] = true, -- Enraged Regeneration (talent)
	},
	[73] = { -- Protection
		[871]    = true, -- Shield Wall
		[23920]  = true, -- Spell Reflection (25s exception)
		[107574] = true, -- Avatar
	},
}

-- Ordered list for the Settings spec dropdown. Grouped by class so the
-- dropdown reads top-to-bottom as: DK (Blood/Frost/Unholy), DH (...), ...
-- Each entry: { specId = N, classToken = "STRING", className = "Display",
--               specName = "Display", role = "TANK|HEALER|DAMAGER" }
ns.ALL_SPECS = {
	{ specId = 250,  classToken = "DEATHKNIGHT", className = "Death Knight", specName = "Blood",        role = "TANK"    },
	{ specId = 251,  classToken = "DEATHKNIGHT", className = "Death Knight", specName = "Frost",        role = "DAMAGER" },
	{ specId = 252,  classToken = "DEATHKNIGHT", className = "Death Knight", specName = "Unholy",       role = "DAMAGER" },

	{ specId = 577,  classToken = "DEMONHUNTER", className = "Demon Hunter", specName = "Havoc",        role = "DAMAGER" },
	{ specId = 581,  classToken = "DEMONHUNTER", className = "Demon Hunter", specName = "Vengeance",    role = "TANK"    },

	{ specId = 102,  classToken = "DRUID",       className = "Druid",        specName = "Balance",      role = "DAMAGER" },
	{ specId = 103,  classToken = "DRUID",       className = "Druid",        specName = "Feral",        role = "DAMAGER" },
	{ specId = 104,  classToken = "DRUID",       className = "Druid",        specName = "Guardian",     role = "TANK"    },
	{ specId = 105,  classToken = "DRUID",       className = "Druid",        specName = "Restoration",  role = "HEALER"  },

	{ specId = 1467, classToken = "EVOKER",      className = "Evoker",       specName = "Devastation",  role = "DAMAGER" },
	{ specId = 1468, classToken = "EVOKER",      className = "Evoker",       specName = "Preservation", role = "HEALER"  },
	{ specId = 1473, classToken = "EVOKER",      className = "Evoker",       specName = "Augmentation", role = "DAMAGER" },

	{ specId = 253,  classToken = "HUNTER",      className = "Hunter",       specName = "Beast Mastery",role = "DAMAGER" },
	{ specId = 254,  classToken = "HUNTER",      className = "Hunter",       specName = "Marksmanship", role = "DAMAGER" },
	{ specId = 255,  classToken = "HUNTER",      className = "Hunter",       specName = "Survival",     role = "DAMAGER" },

	{ specId = 62,   classToken = "MAGE",        className = "Mage",         specName = "Arcane",       role = "DAMAGER" },
	{ specId = 63,   classToken = "MAGE",        className = "Mage",         specName = "Fire",         role = "DAMAGER" },
	{ specId = 64,   classToken = "MAGE",        className = "Mage",         specName = "Frost",        role = "DAMAGER" },

	{ specId = 268,  classToken = "MONK",        className = "Monk",         specName = "Brewmaster",   role = "TANK"    },
	{ specId = 270,  classToken = "MONK",        className = "Monk",         specName = "Mistweaver",   role = "HEALER"  },
	{ specId = 269,  classToken = "MONK",        className = "Monk",         specName = "Windwalker",   role = "DAMAGER" },

	{ specId = 65,   classToken = "PALADIN",     className = "Paladin",      specName = "Holy",         role = "HEALER"  },
	{ specId = 66,   classToken = "PALADIN",     className = "Paladin",      specName = "Protection",   role = "TANK"    },
	{ specId = 70,   classToken = "PALADIN",     className = "Paladin",      specName = "Retribution",  role = "DAMAGER" },

	{ specId = 256,  classToken = "PRIEST",      className = "Priest",       specName = "Discipline",   role = "HEALER"  },
	{ specId = 257,  classToken = "PRIEST",      className = "Priest",       specName = "Holy",         role = "HEALER"  },
	{ specId = 258,  classToken = "PRIEST",      className = "Priest",       specName = "Shadow",       role = "DAMAGER" },

	{ specId = 259,  classToken = "ROGUE",       className = "Rogue",        specName = "Assassination",role = "DAMAGER" },
	{ specId = 260,  classToken = "ROGUE",       className = "Rogue",        specName = "Outlaw",       role = "DAMAGER" },
	{ specId = 261,  classToken = "ROGUE",       className = "Rogue",        specName = "Subtlety",     role = "DAMAGER" },

	{ specId = 262,  classToken = "SHAMAN",      className = "Shaman",       specName = "Elemental",    role = "DAMAGER" },
	{ specId = 263,  classToken = "SHAMAN",      className = "Shaman",       specName = "Enhancement",  role = "DAMAGER" },
	{ specId = 264,  classToken = "SHAMAN",      className = "Shaman",       specName = "Restoration",  role = "HEALER"  },

	{ specId = 265,  classToken = "WARLOCK",     className = "Warlock",      specName = "Affliction",   role = "DAMAGER" },
	{ specId = 266,  classToken = "WARLOCK",     className = "Warlock",      specName = "Demonology",   role = "DAMAGER" },
	{ specId = 267,  classToken = "WARLOCK",     className = "Warlock",      specName = "Destruction",  role = "DAMAGER" },

	{ specId = 71,   classToken = "WARRIOR",     className = "Warrior",      specName = "Arms",         role = "DAMAGER" },
	{ specId = 72,   classToken = "WARRIOR",     className = "Warrior",      specName = "Fury",         role = "DAMAGER" },
	{ specId = 73,   classToken = "WARRIOR",     className = "Warrior",      specName = "Protection",   role = "TANK"    },
}

local specInfoById = {}
for _, info in ipairs(ns.ALL_SPECS) do
	specInfoById[info.specId] = info
end

function ns.GetSpecInfo(specId)
	return specInfoById[specId]
end

function ns.FormatSpecLabel(specId)
	local info = specInfoById[specId]
	if not info then return ("Spec %d"):format(specId) end
	return info.specName .. " " .. info.className
end
