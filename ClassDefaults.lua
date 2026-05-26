-- Per-spec default tracked-spell lists. Scope: defensive, offensive, and
-- healer cooldowns only (>= ~45s CDs). Excluded: interrupts, CC, utility
-- (combat res, MD), trinkets, GCD-bound abilities, movement.
--
-- Some entries are talent-locked but commonly taken; users can prune via
-- the Settings panel per spec. Spell IDs verified against Wowhead /
-- Warcraft Wiki for Midnight (patch 12.0.x, May 2026).

local addonName, ns = ...

ns.DEFAULT_SPELLS_BY_SPEC = {
	-- ============ DEATH KNIGHT ============
	[250] = { -- Blood
		[48707]  = true, -- Anti-Magic Shell
		[48792]  = true, -- Icebound Fortitude
		[55233]  = true, -- Vampiric Blood
		[49028]  = true, -- Dancing Rune Weapon
		[49039]  = true, -- Lichborne
		[51052]  = true, -- Anti-Magic Zone
		[194679] = true, -- Rune Tap (talent)
	},
	[251] = { -- Frost
		[48707]  = true, -- Anti-Magic Shell
		[48792]  = true, -- Icebound Fortitude
		[49039]  = true, -- Lichborne
		[51271]  = true, -- Pillar of Frost
		[152279] = true, -- Breath of Sindragosa (talent)
		[47568]  = true, -- Empower Rune Weapon
		[51052]  = true, -- Anti-Magic Zone (talent)
	},
	[252] = { -- Unholy
		[48707]  = true, -- Anti-Magic Shell
		[48792]  = true, -- Icebound Fortitude
		[49039]  = true, -- Lichborne
		[42650]  = true, -- Army of the Dead
		[275699] = true, -- Apocalypse
		[63560]  = true, -- Dark Transformation
		[51052]  = true, -- Anti-Magic Zone (talent)
	},

	-- ============ DEMON HUNTER ============
	[577] = { -- Havoc
		[198589] = true, -- Blur
		[196555] = true, -- Netherwalk (talent)
		[191427] = true, -- Metamorphosis
		[198013] = true, -- Eye Beam
		[370965] = true, -- The Hunt
	},
	[581] = { -- Vengeance
		[187827] = true, -- Metamorphosis
		[204021] = true, -- Fiery Brand
		[263648] = true, -- Soul Barrier (talent)
		[196555] = true, -- Netherwalk (talent)
		[198589] = true, -- Blur (talent)
		[370965] = true, -- The Hunt
	},

	-- ============ DRUID ============
	[102] = { -- Balance
		[22812]  = true, -- Barkskin
		[61336]  = true, -- Survival Instincts
		[194223] = true, -- Celestial Alignment
		[102560] = true, -- Incarnation: Chosen of Elune (talent)
		[391528] = true, -- Convoke the Spirits (talent)
		[205636] = true, -- Force of Nature (talent)
		[124974] = true, -- Nature's Vigil (talent)
	},
	[103] = { -- Feral
		[22812]  = true, -- Barkskin
		[61336]  = true, -- Survival Instincts
		[106951] = true, -- Berserk
		[102543] = true, -- Incarnation: Avatar of Ashamane (talent)
		[391528] = true, -- Convoke the Spirits (talent)
	},
	[104] = { -- Guardian
		[22812]  = true, -- Barkskin
		[61336]  = true, -- Survival Instincts
		[200851] = true, -- Rage of the Sleeper
		[102558] = true, -- Incarnation: Guardian of Ursoc (talent)
		[80313]  = true, -- Pulverize (talent)
	},
	[105] = { -- Restoration
		[22812]  = true, -- Barkskin
		[61336]  = true, -- Survival Instincts
		[740]    = true, -- Tranquility
		[33891]  = true, -- Incarnation: Tree of Life (talent)
		[102342] = true, -- Ironbark
		[29166]  = true, -- Innervate
		[391528] = true, -- Convoke the Spirits (talent)
		[124974] = true, -- Nature's Vigil (talent)
	},

	-- ============ EVOKER ============
	[1467] = { -- Devastation
		[363916] = true, -- Obsidian Scales
		[374348] = true, -- Renewing Blaze
		[375087] = true, -- Dragonrage
		[370553] = true, -- Tip the Scales
		[357210] = true, -- Deep Breath
	},
	[1468] = { -- Preservation
		[363916] = true, -- Obsidian Scales
		[374348] = true, -- Renewing Blaze
		[363534] = true, -- Rewind
		[359816] = true, -- Dream Flight (talent)
		[357170] = true, -- Time Dilation
		[370553] = true, -- Tip the Scales
		[370960] = true, -- Emerald Communion (talent)
		[378441] = true, -- Time Stop (talent)
	},
	[1473] = { -- Augmentation
		[363916] = true, -- Obsidian Scales
		[374348] = true, -- Renewing Blaze
		[395152] = true, -- Ebon Might
		[403631] = true, -- Breath of Eons
		[370553] = true, -- Tip the Scales
		[357170] = true, -- Time Dilation
	},

	-- ============ HUNTER ============
	[253] = { -- Beast Mastery
		[186265] = true, -- Aspect of the Turtle
		[109304] = true, -- Exhilaration
		[19574]  = true, -- Bestial Wrath
		[193530] = true, -- Aspect of the Wild (talent)
		[359844] = true, -- Call of the Wild (talent)
	},
	[254] = { -- Marksmanship
		[186265] = true, -- Aspect of the Turtle
		[109304] = true, -- Exhilaration
		[288613] = true, -- Trueshot
		[359844] = true, -- Call of the Wild (talent)
	},
	[255] = { -- Survival
		[186265] = true, -- Aspect of the Turtle
		[109304] = true, -- Exhilaration
		[266779] = true, -- Coordinated Assault
		[359844] = true, -- Call of the Wild (talent)
	},

	-- ============ MAGE ============
	[62] = { -- Arcane
		[45438]  = true, -- Ice Block
		[110959] = true, -- Greater Invisibility
		[235450] = true, -- Prismatic Barrier
		[365350] = true, -- Arcane Surge
		[55342]  = true, -- Mirror Image
		[414660] = true, -- Mass Barrier (Sunfury hero talent)
	},
	[63] = { -- Fire
		[45438]  = true, -- Ice Block
		[110959] = true, -- Greater Invisibility (talent)
		[235313] = true, -- Blazing Barrier
		[190319] = true, -- Combustion
		[55342]  = true, -- Mirror Image
	},
	[64] = { -- Frost
		[45438]  = true, -- Ice Block
		[110959] = true, -- Greater Invisibility (talent)
		[11426]  = true, -- Ice Barrier
		[12472]  = true, -- Icy Veins
		[235219] = true, -- Cold Snap
		[55342]  = true, -- Mirror Image
		[414658] = true, -- Ice Cold (Frostfire hero talent)
	},

	-- ============ MONK ============
	[268] = { -- Brewmaster
		[115203] = true, -- Fortifying Brew
		[115176] = true, -- Zen Meditation
		[122278] = true, -- Dampen Harm (talent)
		[122783] = true, -- Diffuse Magic (talent)
		[322507] = true, -- Celestial Brew
		[132578] = true, -- Invoke Niuzao, the Black Ox
		[325153] = true, -- Exploding Keg
		[386276] = true, -- Bonedust Brew (talent)
		[387184] = true, -- Weapons of Order (talent)
	},
	[270] = { -- Mistweaver
		[115203] = true, -- Fortifying Brew
		[122278] = true, -- Dampen Harm (talent)
		[122783] = true, -- Diffuse Magic (talent)
		[116849] = true, -- Life Cocoon
		[115310] = true, -- Revival
		[388615] = true, -- Restoral (talent - alt to Revival)
		[322118] = true, -- Invoke Yu'lon, the Jade Serpent
		[386276] = true, -- Bonedust Brew (talent)
	},
	[269] = { -- Windwalker
		[115203] = true, -- Fortifying Brew
		[122470] = true, -- Touch of Karma
		[122278] = true, -- Dampen Harm (talent)
		[122783] = true, -- Diffuse Magic (talent)
		[123904] = true, -- Invoke Xuen, the White Tiger
		[137639] = true, -- Storm, Earth, and Fire
		[386276] = true, -- Bonedust Brew (talent)
		[387184] = true, -- Weapons of Order (talent)
	},

	-- ============ PALADIN ============
	[65] = { -- Holy
		[642]    = true, -- Divine Shield
		[498]    = true, -- Divine Protection
		[1022]   = true, -- Blessing of Protection
		[6940]   = true, -- Blessing of Sacrifice
		[633]    = true, -- Lay on Hands
		[31884]  = true, -- Avenging Wrath
		[216331] = true, -- Avenging Crusader (talent - alt to AW)
		[31821]  = true, -- Aura Mastery
		[375576] = true, -- Divine Toll
		[105809] = true, -- Holy Avenger (talent)
		[200025] = true, -- Beacon of Virtue (talent)
	},
	[66] = { -- Protection
		[642]    = true, -- Divine Shield
		[1022]   = true, -- Blessing of Protection
		[204018] = true, -- Blessing of Spellwarding
		[6940]   = true, -- Blessing of Sacrifice
		[633]    = true, -- Lay on Hands
		[31850]  = true, -- Ardent Defender
		[86659]  = true, -- Guardian of Ancient Kings
		[31884]  = true, -- Avenging Wrath (talent)
		[389539] = true, -- Sentinel (talent - alt to AW)
		[375576] = true, -- Divine Toll
		[204150] = true, -- Aegis of Light (talent)
		[378974] = true, -- Bastion of Light (talent)
		[387174] = true, -- Eye of Tyr
	},
	[70] = { -- Retribution
		[642]    = true, -- Divine Shield
		[498]    = true, -- Divine Protection
		[1022]   = true, -- Blessing of Protection
		[6940]   = true, -- Blessing of Sacrifice
		[633]    = true, -- Lay on Hands
		[205191] = true, -- Eye for an Eye (talent)
		[31884]  = true, -- Avenging Wrath
		[231895] = true, -- Crusade (talent - alt to AW)
		[255937] = true, -- Wake of Ashes
		[343527] = true, -- Execution Sentence (talent)
		[375576] = true, -- Divine Toll
	},

	-- ============ PRIEST ============
	[256] = { -- Discipline
		[19236]  = true, -- Desperate Prayer
		[33206]  = true, -- Pain Suppression
		[47788]  = true, -- Guardian Spirit
		[62618]  = true, -- Power Word: Barrier
		[47536]  = true, -- Rapture
		[109964] = true, -- Spirit Shell (talent)
		[64901]  = true, -- Symbol of Hope
		[421453] = true, -- Ultimate Penitence (Oracle hero talent)
	},
	[257] = { -- Holy
		[19236]  = true, -- Desperate Prayer
		[47788]  = true, -- Guardian Spirit
		[64843]  = true, -- Divine Hymn
		[265202] = true, -- Holy Word: Salvation (talent)
		[200183] = true, -- Apotheosis (talent)
		[64901]  = true, -- Symbol of Hope
		[62618]  = true, -- Power Word: Barrier (talent)
	},
	[258] = { -- Shadow
		[19236]  = true, -- Desperate Prayer
		[15286]  = true, -- Vampiric Embrace
		[228260] = true, -- Void Eruption / Voidform
		[391109] = true, -- Dark Ascension (talent - alt to Voidform)
		[64901]  = true, -- Symbol of Hope
	},

	-- ============ ROGUE ============
	[259] = { -- Assassination
		[31224]  = true, -- Cloak of Shadows
		[5277]   = true, -- Evasion
		[185311] = true, -- Crimson Vial
		[1966]   = true, -- Feint
		[360194] = true, -- Deathmark
		[385408] = true, -- Sepsis (talent)
	},
	[260] = { -- Outlaw
		[31224]  = true, -- Cloak of Shadows
		[5277]   = true, -- Evasion
		[185311] = true, -- Crimson Vial
		[1966]   = true, -- Feint
		[13750]  = true, -- Adrenaline Rush
		[51690]  = true, -- Killing Spree (talent)
		[343142] = true, -- Dreadblades (talent)
	},
	[261] = { -- Subtlety
		[31224]  = true, -- Cloak of Shadows
		[5277]   = true, -- Evasion
		[185311] = true, -- Crimson Vial
		[1966]   = true, -- Feint
		[121471] = true, -- Shadow Blades
		[277925] = true, -- Shuriken Tornado (talent)
		[384631] = true, -- Flagellation (talent)
	},

	-- ============ SHAMAN ============
	[262] = { -- Elemental
		[108271] = true, -- Astral Shift
		[114050] = true, -- Ascendance (talent)
		[191634] = true, -- Stormkeeper
		[198067] = true, -- Fire Elemental
		[192249] = true, -- Storm Elemental (talent - alt to Fire)
		[108281] = true, -- Ancestral Guidance (talent)
		[16191]  = true, -- Mana Tide Totem
		[192077] = true, -- Wind Rush Totem (talent)
		[98008]  = true, -- Spirit Link Totem (talent)
	},
	[263] = { -- Enhancement
		[108271] = true, -- Astral Shift
		[114051] = true, -- Ascendance (talent)
		[51533]  = true, -- Feral Spirit
		[384352] = true, -- Doom Winds (talent)
		[108281] = true, -- Ancestral Guidance (talent)
		[192077] = true, -- Wind Rush Totem (talent)
		[98008]  = true, -- Spirit Link Totem (talent)
	},
	[264] = { -- Restoration
		[108271] = true, -- Astral Shift
		[114052] = true, -- Ascendance (talent)
		[108280] = true, -- Healing Tide Totem
		[98008]  = true, -- Spirit Link Totem
		[16191]  = true, -- Mana Tide Totem
		[207399] = true, -- Ancestral Protection Totem (talent)
		[108281] = true, -- Ancestral Guidance (talent)
		[198838] = true, -- Earthen Wall Totem (talent)
		[192077] = true, -- Wind Rush Totem (talent)
	},

	-- ============ WARLOCK ============
	[265] = { -- Affliction
		[104773] = true, -- Unending Resolve
		[108416] = true, -- Dark Pact (talent)
		[205180] = true, -- Summon Darkglare
		[113860] = true, -- Dark Soul: Misery (talent)
		[386997] = true, -- Soul Rot (talent)
		[1122]   = true, -- Summon Infernal (talent)
	},
	[266] = { -- Demonology
		[104773] = true, -- Unending Resolve
		[108416] = true, -- Dark Pact (talent)
		[265187] = true, -- Summon Demonic Tyrant
		[267171] = true, -- Demonic Strength (talent)
		[111898] = true, -- Grimoire: Felguard (talent)
		[1122]   = true, -- Summon Infernal (talent)
	},
	[267] = { -- Destruction
		[104773] = true, -- Unending Resolve
		[108416] = true, -- Dark Pact (talent)
		[1122]   = true, -- Summon Infernal
		[113858] = true, -- Dark Soul: Instability (talent)
		[152108] = true, -- Cataclysm (talent)
		[386997] = true, -- Soul Rot (talent)
	},

	-- ============ WARRIOR ============
	[71] = { -- Arms
		[184364] = true, -- Enraged Regeneration
		[118038] = true, -- Die by the Sword
		[23920]  = true, -- Spell Reflection
		[97462]  = true, -- Rallying Cry
		[1719]   = true, -- Recklessness
		[107574] = true, -- Avatar (talent)
		[46924]  = true, -- Bladestorm
		[228920] = true, -- Ravager (talent)
		[376079] = true, -- Champion's Spear (talent)
		[384318] = true, -- Thunderous Roar (talent)
	},
	[72] = { -- Fury
		[184364] = true, -- Enraged Regeneration
		[118038] = true, -- Die by the Sword
		[23920]  = true, -- Spell Reflection
		[97462]  = true, -- Rallying Cry
		[1719]   = true, -- Recklessness
		[107574] = true, -- Avatar
		[46924]  = true, -- Bladestorm (talent)
		[385059] = true, -- Odyn's Fury
		[384318] = true, -- Thunderous Roar (talent)
		[376079] = true, -- Champion's Spear (talent)
	},
	[73] = { -- Protection
		[871]    = true, -- Shield Wall
		[12975]  = true, -- Last Stand
		[23920]  = true, -- Spell Reflection
		[97462]  = true, -- Rallying Cry
		[1160]   = true, -- Demoralizing Shout
		[184364] = true, -- Enraged Regeneration
		[107574] = true, -- Avatar
		[385952] = true, -- Shield Charge (talent)
		[228920] = true, -- Ravager (talent)
		[376079] = true, -- Champion's Spear (talent)
		[46924]  = true, -- Bladestorm (talent)
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
