--!strict
-- Equipment modules and the stat maths that resolves a hull + its fitting into
-- the numbers the game actually runs on. Shared by the hangar UI (to preview a
-- fit) and the server (to fly and fight it).
--
-- Effects are fractions of the base stat: 0.25 = +25%, -0.08 = -8%. A hull's
-- own Bonuses are applied the same way, so both stack additively before being
-- multiplied in once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShipClasses = require(ReplicatedStorage:WaitForChild("ShipClasses"))
local WeaponSpecs = require(ReplicatedStorage:WaitForChild("WeaponSpecs"))

local Fittings = {}

Fittings.Modules = {
	Afterburner = {
		Name = "Afterburner", Icon = "\u{1F525}",
		Desc = "+25% sublight speed",
		Effects = { SublightSpeed = 0.25 },
	},
	InertialStabilizer = {
		Name = "Inertial Stabilizer", Icon = "\u{1F3AF}",
		Desc = "+30% agility, +15% align speed",
		Effects = { AlignTurnRate = 0.30, AlignSpeed = 0.15 },
	},
	WarpAccelerator = {
		Name = "Warp Accelerator", Icon = "\u{1F300}",
		Desc = "+20% warp speed, +15% warp acceleration",
		Effects = { WarpMaxSpeed = 0.20, WarpAccelK = 0.15 },
	},
	ArmorPlate = {
		Name = "Armor Plate", Icon = "\u{1F6E1}",
		Desc = "+30% hull, -8% sublight speed",
		Effects = { Health = 0.30, SublightSpeed = -0.08 },
	},
	DamageAmp = {
		Name = "Damage Amplifier", Icon = "\u{1F4A5}",
		Desc = "+25% weapon damage",
		Effects = { Damage = 0.25 },
	},
	RangeExtender = {
		Name = "Range Extender", Icon = "\u{1F4E1}",
		Desc = "+30% weapon range, +10% engagement range",
		Effects = { WeaponRange = 0.30, OrbitRange = 0.10 },
	},
	RapidLoader = {
		Name = "Rapid Loader", Icon = "\u{1F501}",
		Desc = "-25% weapon cooldown",
		Effects = { Cooldown = -0.25 },
	},
}

Fittings.Order = {
	"Afterburner", "InertialStabilizer", "WarpAccelerator", "ArmorPlate",
	"DamageAmp", "RangeExtender", "RapidLoader",
}

-- Stats a fleet moves at: always the slowest member's value (EVE fleet rule).
Fittings.MoveKeys = { "AlignTurnRate", "AlignSpeed", "WarpAccelK", "WarpMaxSpeed", "SublightSpeed" }

-- Resolve hull + fitted modules into final numbers.
function Fittings.computeStats(hullId: string, moduleIds: { string }?): { [string]: any }
	local hull = ShipClasses.Hulls[hullId] or ShipClasses.Hulls.VexDart
	local weapon = WeaponSpecs[hull.Weapon]

	local stats: { [string]: any } = {}
	for key, value in hull.Stats do
		stats[key] = value
	end
	stats.Damage = weapon.Damage
	stats.WeaponRange = weapon.Range
	stats.Cooldown = weapon.Cooldown

	local totals: { [string]: number } = {}
	local function accumulate(effects: { [string]: number })
		for key, amount in effects do
			totals[key] = (totals[key] or 0) + amount
		end
	end
	accumulate(hull.Bonuses)
	for _, moduleId in moduleIds or {} do
		local fitting = Fittings.Modules[moduleId]
		if fitting then
			accumulate(fitting.Effects)
		end
	end

	for key, amount in totals do
		if typeof(stats[key]) == "number" then
			stats[key] = math.max(stats[key] * (1 + amount), 0.05)
		end
	end

	stats.Weapon = hull.Weapon -- string: keep clear of the numeric maths above
	return stats
end

-- Base numbers with no modules fitted, for "before" columns in the UI.
function Fittings.baseStats(hullId: string): { [string]: any }
	return Fittings.computeStats(hullId, {})
end

-- Highest value each stat reaches across the whole catalogue, so the UI can
-- draw comparable bars.
function Fittings.statCeilings(): { [string]: number }
	local ceilings: { [string]: number } = {}
	for hullId in ShipClasses.Hulls do
		for key, value in Fittings.baseStats(hullId) do
			if typeof(value) == "number" then
				ceilings[key] = math.max(ceilings[key] or 0, value)
			end
		end
	end
	for key, value in ceilings do
		ceilings[key] = value * 1.45 -- headroom so a fitted hull can still grow
	end
	return ceilings
end

-- Server-side guard: is this loadout entry legal?
function Fittings.validate(hullId: any, moduleIds: any): boolean
	if typeof(hullId) ~= "string" or not ShipClasses.Hulls[hullId] then return false end
	if typeof(moduleIds) ~= "table" then return false end
	if #moduleIds > ShipClasses.Hulls[hullId].Slots then return false end
	for _, moduleId in moduleIds do
		if typeof(moduleId) ~= "string" or not Fittings.Modules[moduleId] then return false end
	end
	return true
end

return Fittings