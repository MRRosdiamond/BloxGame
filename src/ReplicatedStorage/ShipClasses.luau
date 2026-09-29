--!nonstrict
-- Hull catalogue and the three faction trees.
--
-- Each faction builds a complete line of its own and specialises in one weapon:
--   Vex   - Autocannons. Fast brawlers that fight at knife range.
--   Korr  - Rocket pods. Mid-range pressure, tough hulls.
--   Auran - Beam batteries. Slow, heavily armoured, kills at distance.
--
-- Every tree runs left to right, three abreast until the capitals:
--   3 frigates -> 3 cruisers -> 3 battlecruisers -> 2 battleships
--
-- Each tier offers the same three roles:
--   Line    - plain stats, the most fitting slots. The versatile choice.
--   Assault - offence and speed bonuses, few slots.
--   Guard   - hull and staying power, few slots.
-- That is the trade the whole tree is built on: the sharper a hull's own
-- bonuses, the less room it leaves you to fit modules.

local ShipClasses = {}

ShipClasses.TierNames = { "Frigate", "Cruiser", "Battlecruiser", "Battleship" }
ShipClasses.FactionOrder = { "Vex", "Korr", "Auran" }

-- Which placeholder model each hull size is built from (dummy1/2/3).
ShipClasses.SizeModels = { Small = 3, Medium = 1, Large = 2 }

ShipClasses.Factions = {
	Vex = {
		Name = "Vex",
		Weapon = "Bullets",
		Color = Color3.fromRGB(255, 110, 80),
		Blurb = "Get close, stay close, put rounds on the hull.",
		HealthMult = 0.95, SpeedMult = 1.08, WarpMult = 1.0,
		OrbitByTier = { 40, 55, 70, 110 },
	},
	Korr = {
		Name = "Korr",
		Weapon = "Rockets",
		Color = Color3.fromRGB(255, 190, 70),
		Blurb = "Hold the middle distance and never stop firing.",
		HealthMult = 1.05, SpeedMult = 1.0, WarpMult = 0.95,
		OrbitByTier = { 90, 110, 130, 170 },
	},
	Auran = {
		Name = "Auran",
		Weapon = "Laser",
		Color = Color3.fromRGB(90, 200, 255),
		Blurb = "Open fire before anything else can reach you.",
		HealthMult = 1.10, SpeedMult = 0.88, WarpMult = 1.12,
		OrbitByTier = { 150, 200, 220, 250 },
	},
}

-- Shared skeleton for a tier, before faction character is applied.
local TIER_BASE = {
	{ Health = 70, SublightSpeed = 55, AlignTurnRate = 2.4, AlignSpeed = 22,
	  WarpAccelK = 3.6, WarpMaxSpeed = 2200, Size = "Small", Scale = 0.8 },
	{ Health = 140, SublightSpeed = 40, AlignTurnRate = 1.8, AlignSpeed = 18,
	  WarpAccelK = 3.0, WarpMaxSpeed = 1800, Size = "Medium", Scale = 1.0 },
	{ Health = 260, SublightSpeed = 30, AlignTurnRate = 1.2, AlignSpeed = 15,
	  WarpAccelK = 2.2, WarpMaxSpeed = 1200, Size = "Large", Scale = 1.6 },
	{ Health = 480, SublightSpeed = 23, AlignTurnRate = 0.8, AlignSpeed = 12,
	  WarpAccelK = 1.6, WarpMaxSpeed = 850, Size = "Large", Scale = 2.2 },
}

local TIER_COST = { 0, 250, 800, 2000 }

-- The rosters. Order matters: within a tier the entries are Line, Assault,
-- Guard, and that position decides what a hull unlocks in the next column.
local ROSTER = {
	Vex = {
		{ tier = 1, name = "Dart", role = "Line", slots = 3,
		  blurb = "Cheap, quick, and made to be replaced.",
		  bonuses = { SublightSpeed = 0.05 } },
		{ tier = 1, name = "Fang", role = "Assault", slots = 2,
		  blurb = "All engine and guns. Blink and it is already on you.",
		  bonuses = { SublightSpeed = 0.14, Damage = 0.10 } },
		{ tier = 1, name = "Scarab", role = "Guard", slots = 2,
		  blurb = "Overplated for its size. Survives the first exchange.",
		  bonuses = { Health = 0.18, OrbitRange = 0.08 } },

		{ tier = 2, name = "Lancer", role = "Line", slots = 4,
		  blurb = "The workhorse. Nothing special, room for everything.",
		  bonuses = { Health = 0.05 } },
		{ tier = 2, name = "Reaver", role = "Assault", slots = 2,
		  blurb = "Built to close the gap and open hulls.",
		  bonuses = { SublightSpeed = 0.12, Damage = 0.12 } },
		{ tier = 2, name = "Palisade", role = "Guard", slots = 3,
		  blurb = "Takes the beating so the rest of the fleet does not.",
		  bonuses = { Health = 0.15, AlignTurnRate = 0.08 } },

		{ tier = 3, name = "Ravager", role = "Line", slots = 4,
		  blurb = "A cruiser's aggression carried on a heavy hull.",
		  bonuses = { Health = 0.08 } },
		{ tier = 3, name = "Warhound", role = "Assault", slots = 3,
		  blurb = "Refuses to be kited. Catches things it should not.",
		  bonuses = { SublightSpeed = 0.10, Damage = 0.12 } },
		{ tier = 3, name = "Redoubt", role = "Guard", slots = 3,
		  blurb = "Anchors the line and dares the enemy to come closer.",
		  bonuses = { Health = 0.16, AlignTurnRate = 0.08 } },

		{ tier = 4, name = "Dominion", role = "Line", slots = 5,
		  blurb = "A slab of a ship with slots to spare. Slow to turn, slow to die.",
		  bonuses = { Health = 0.06 } },
		{ tier = 4, name = "Warlord", role = "Assault", slots = 4,
		  blurb = "Every spare ton spent on guns.",
		  bonuses = { Damage = 0.12, SublightSpeed = 0.08 } },
	},

	Korr = {
		{ tier = 1, name = "Sting", role = "Line", slots = 3,
		  blurb = "A rocket rack with engines bolted on.",
		  bonuses = { SublightSpeed = 0.05 } },
		{ tier = 1, name = "Hornet", role = "Assault", slots = 2,
		  blurb = "Small, loud, and carrying far too many warheads.",
		  bonuses = { SublightSpeed = 0.12, Damage = 0.10 } },
		{ tier = 1, name = "Carapace", role = "Guard", slots = 2,
		  blurb = "Slow for a frigate, but it does not fold.",
		  bonuses = { Health = 0.18 } },

		{ tier = 2, name = "Harrier", role = "Line", slots = 4,
		  blurb = "Circles at rocket range and refuses to be pinned.",
		  bonuses = { Health = 0.05 } },
		{ tier = 2, name = "Falcon", role = "Assault", slots = 2,
		  blurb = "Fast enough to pick its range and hold it.",
		  bonuses = { SublightSpeed = 0.12, OrbitRange = 0.10 } },
		{ tier = 2, name = "Rampart", role = "Guard", slots = 3,
		  blurb = "A moving wall with launchers on the roof.",
		  bonuses = { Health = 0.15, AlignTurnRate = 0.08 } },

		{ tier = 3, name = "Bulwark", role = "Line", slots = 4,
		  blurb = "Built to sit still and be shot at while its rockets work.",
		  bonuses = { Health = 0.08 } },
		{ tier = 3, name = "Kestrel", role = "Assault", slots = 3,
		  blurb = "A battlecruiser that still thinks it is a frigate.",
		  bonuses = { SublightSpeed = 0.10, Damage = 0.12 } },
		{ tier = 3, name = "Citadel", role = "Guard", slots = 3,
		  blurb = "Parks on a site and makes taking it expensive.",
		  bonuses = { Health = 0.16, OrbitRange = 0.10 } },

		{ tier = 4, name = "Sovereign", role = "Line", slots = 5,
		  blurb = "The fleet's centre of gravity, in every sense.",
		  bonuses = { Health = 0.06 } },
		{ tier = 4, name = "Aegis", role = "Guard", slots = 4,
		  blurb = "Nothing about it is quick, and nothing about it breaks.",
		  bonuses = { Health = 0.12, OrbitRange = 0.08 } },
	},

	Auran = {
		{ tier = 1, name = "Spark", role = "Line", slots = 3,
		  blurb = "A beam mount that runs the moment anything closes.",
		  bonuses = { WarpMaxSpeed = 0.08 } },
		{ tier = 1, name = "Ember", role = "Assault", slots = 2,
		  blurb = "Oversized optics on a hull that cannot take a hit.",
		  bonuses = { Damage = 0.12, WeaponRange = 0.10 } },
		{ tier = 1, name = "Glimmer", role = "Guard", slots = 2,
		  blurb = "Armoured enough to finish the shot it started.",
		  bonuses = { Health = 0.15, WarpMaxSpeed = 0.10 } },

		{ tier = 2, name = "Vigil", role = "Line", slots = 4,
		  blurb = "Patient, well-armoured, and always the first to fire.",
		  bonuses = { Health = 0.05 } },
		{ tier = 2, name = "Oracle", role = "Assault", slots = 2,
		  blurb = "Superb in every respect except room to fit anything.",
		  bonuses = { WarpMaxSpeed = 0.15, Health = 0.12, OrbitRange = 0.10 } },
		{ tier = 2, name = "Sentinel", role = "Guard", slots = 3,
		  blurb = "Reaches further than anything else in its class.",
		  bonuses = { WeaponRange = 0.12, Damage = 0.08 } },

		{ tier = 3, name = "Lumen", role = "Line", slots = 4,
		  blurb = "A steady gun platform with room for a real fit.",
		  bonuses = { Health = 0.08 } },
		{ tier = 3, name = "Prism", role = "Assault", slots = 3,
		  blurb = "Splits the horizon open at ranges nothing answers.",
		  bonuses = { WeaponRange = 0.14, Damage = 0.10 } },
		{ tier = 3, name = "Sanctum", role = "Guard", slots = 3,
		  blurb = "Holds ground by simply refusing to die on it.",
		  bonuses = { Health = 0.16, WarpMaxSpeed = 0.08 } },

		{ tier = 4, name = "Cathedral", role = "Line", slots = 5,
		  blurb = "Opens fire before anything else on the field can reach it.",
		  bonuses = { Health = 0.06 } },
		{ tier = 4, name = "Apotheosis", role = "Assault", slots = 4,
		  blurb = "The last word in an Auran argument.",
		  bonuses = { Health = 0.12, WeaponRange = 0.10, Damage = 0.08 } },
	},
}

----------------------------------------------------------------
-- Expansion: roster entries -> full hull definitions + trees
----------------------------------------------------------------

ShipClasses.Hulls = {}
ShipClasses.Trees = {} -- Trees[factionId][tier] = { hullId, ... }

local function roundTo(value: number, step: number): number
	return math.round(value / step) * step
end

for factionId, entries in ROSTER do
	local faction = ShipClasses.Factions[factionId]
	local tree = { {}, {}, {}, {} }
	ShipClasses.Trees[factionId] = tree

	for _, spec in entries do
		local base = TIER_BASE[spec.tier]
		local hullId = factionId .. spec.name
		ShipClasses.Hulls[hullId] = {
			Name = spec.name,
			Faction = factionId,
			Role = spec.role,
			Weapon = faction.Weapon,
			Tier = spec.tier,
			Size = base.Size,
			Scale = base.Scale,
			Slots = spec.slots,
			Cost = TIER_COST[spec.tier],
			Requires = {},
			Blurb = spec.blurb,
			Bonuses = spec.bonuses,
			Stats = {
				Health = roundTo(base.Health * faction.HealthMult, 5),
				SublightSpeed = roundTo(base.SublightSpeed * faction.SpeedMult, 1),
				AlignTurnRate = base.AlignTurnRate,
				AlignSpeed = base.AlignSpeed,
				WarpAccelK = base.WarpAccelK,
				WarpMaxSpeed = roundTo(base.WarpMaxSpeed * faction.WarpMult, 50),
				OrbitRange = faction.OrbitByTier[spec.tier],
			},
		}
		table.insert(tree[spec.tier], hullId)
	end
end

-- Prerequisites follow position in the column: a hull unlocks from the hull
-- above it in the previous tier. The two battleships each sit under a pair of
-- battlecruisers, so the three lines converge at the top.
for _, tree in ShipClasses.Trees do
	for tier = 2, 4 do
		local previous = tree[tier - 1]
		for index, hullId in tree[tier] do
			local requires = if tier < 4
				then { previous[index] }
				else { previous[index], previous[index + 1] }
			ShipClasses.Hulls[hullId].Requires = requires
		end
	end
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

function ShipClasses.factionColor(hullId: string): Color3
	local hull = ShipClasses.Hulls[hullId]
	local faction = hull and ShipClasses.Factions[hull.Faction]
	return if faction then faction.Color else Color3.fromRGB(200, 200, 200)
end

-- every hull a faction fields, flattened
function ShipClasses.hullsOf(factionId: string): { string }
	local list = {}
	for tier = 1, 4 do
		for _, hullId in ShipClasses.Trees[factionId][tier] do
			table.insert(list, hullId)
		end
	end
	return list
end

return ShipClasses