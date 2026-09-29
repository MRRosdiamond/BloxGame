--!strict
-- FleetWarp: NPC fleets. Each fleet belongs to a faction, claims a free
-- location (max one fleet per location), warps there once, then perches until
-- killed. When the player fleet comes close they break formation and engage:
-- small hulls dive in and orbit fast, big hulls crawl to long range.
-- Dead fleets free their location and a replacement stages later.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShipClasses = require(ReplicatedStorage:WaitForChild("ShipClasses"))
local Fittings = require(ReplicatedStorage:WaitForChild("Fittings"))
local Combat = require(ServerScriptService:WaitForChild("CombatSystem"))
local ShipMotion = require(ServerScriptService:WaitForChild("ShipMotion"))

local CONFIG = {
	FleetCount = 4,
	ShipsPerFleetMin = 4,
	ShipsPerFleetMax = 6,
	FormationRadius = 16,
	MapRadius = 1700,
	AltitudeMin = 25,
	AltitudeMax = 65,
	HitboxSize = 70, -- invisible click target around the fleet

	StageTimeMin = 2,
	StageTimeMax = 6,

	AlignAccel = 7,
	AlignDotThreshold = 0.999,
	WarpEntrySpeed = 25,
	WarpDecelRate = 3.0,
	WarpExitSpeed = 30,

	AggroRange = 280,
	DeaggroRange = 600,
	OrbitBand = 12,
	CombatAccel = 14,
	CombatTurnRate = 2.5,
	MinCombatAltitude = 15, -- ships never dip below this while maneuvering
	RespawnDelay = 25,
}

-- how often each tier shows up in an NPC fleet
local TIER_WEIGHTS = { 55, 28, 13, 4 }

local rng = Random.new()

----------------------------------------------------------------
-- Templates
----------------------------------------------------------------

local templates: { [string]: BasePart } = {}
for size, index in ShipClasses.SizeModels do
	local part = workspace:FindFirstChild("dummy" .. index)
	if part and part:IsA("BasePart") then
		local clone = part:Clone()
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = true -- must stay clickable for warp targeting
		templates[size] = clone
		part.Parent = nil -- hide the placeholder during play
	end
end
assert(next(templates) ~= nil, "FleetWarp: no dummy ship templates found in Workspace")

local function templateFor(size: string): BasePart
	return templates[size] or templates.Medium or templates.Small or templates.Large
end

local fleetsFolder = Instance.new("Folder")
fleetsFolder.Name = "Fleets"
fleetsFolder.Parent = workspace

local function addWarpTrail(ship: BasePart, color: Color3): Trail
	local halfZ = ship.Size.Z / 2
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, ship.Size.Y / 2, halfZ)
	a0.Parent = ship
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -ship.Size.Y / 2, halfZ)
	a1.Parent = ship
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.35
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = ship
	return trail
end

----------------------------------------------------------------
-- World helpers
----------------------------------------------------------------

local function randomFleetCenter(): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = math.sqrt(rng:NextNumber()) * CONFIG.MapRadius
	return Vector3.new(
		math.cos(angle) * dist,
		rng:NextNumber(CONFIG.AltitudeMin, CONFIG.AltitudeMax),
		math.sin(angle) * dist
	)
end

local occupied: { [Instance]: boolean } = {}

local function claimLocation(): (Instance?, Vector3?)
	local folder = workspace:FindFirstChild("Locations")
	if not folder then return nil, nil end
	local candidates: { Instance } = {}
	for _, loc in folder:GetChildren() do
		local hitbox = loc:FindFirstChild("WarpHitbox")
		-- a hitbox flagged Safe (the trade hub) is never claimed by hostiles
		if not occupied[loc] and hitbox and not hitbox:GetAttribute("Safe") then
			table.insert(candidates, loc)
		end
	end
	if #candidates == 0 then return nil, nil end
	local loc = candidates[rng:NextInteger(1, #candidates)]
	occupied[loc] = true
	local hitbox = loc:FindFirstChild("WarpHitbox") :: BasePart
	local dropRadius = tonumber(hitbox:GetAttribute("DropRadius")) or 60
	local angle = rng:NextNumber(0, math.pi * 2)
	local perch = Vector3.new(
		hitbox.Position.X + math.cos(angle) * dropRadius * 0.5,
		rng:NextNumber(CONFIG.AltitudeMin, CONFIG.AltitudeMax),
		hitbox.Position.Z + math.sin(angle) * dropRadius * 0.5
	)
	return loc, perch
end

local function getPlayerShips(): ({ BasePart }, Vector3?)
	local folder = workspace:FindFirstChild("PlayerFleet")
	if not folder then return {}, nil end
	local list: { BasePart } = {}
	local sum = Vector3.zero
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and ((child:GetAttribute("Health") :: number?) or 0) > 0 then
			table.insert(list, child)
			sum += child.Position
		end
	end
	if #list == 0 then return {}, nil end
	return list, sum / #list
end

-- a fleet aligns and warps at the pace of its slowest member
local function slowestStats(ships: { any }): { [string]: number }
	local fleetStats: { [string]: number } = {}
	for _, ship in ships do
		for _, key in Fittings.MoveKeys do
			local value = ship.stats[key]
			fleetStats[key] = if fleetStats[key] then math.min(fleetStats[key], value) else value
		end
	end
	return fleetStats
end

-- pick a hull from this faction's own tree, weighted toward light hulls
local function pickHull(faction: string): string
	local roll = rng:NextNumber() * 100
	local acc = 0
	local tier = 1
	for t, weight in TIER_WEIGHTS do
		acc += weight
		if roll <= acc then
			tier = t
			break
		end
	end
	local options = ShipClasses.Trees[faction][tier]
	return options[rng:NextInteger(1, #options)]
end

----------------------------------------------------------------
-- Fleet spawning
----------------------------------------------------------------

local CORE_FACTIONS = { "Vex", "Korr", "Auran" }

type Ship = {
	part: BasePart,
	trail: Trail,
	offset: Vector3,
	warpStart: Vector3,
	speed: number,
	orbitSign: number,
	nextFire: number,
	hullId: string,
	stats: { [string]: any },
	baseCF: CFrame,
	bankRoll: number,
}

type Fleet = {
	name: string,
	ships: { Ship },
	center: Vector3,
	state: string, -- Staging | Aligning | Warping | Perched | Engaging | Returning
	timer: number,
	destination: Vector3,
	direction: Vector3,
	alignSpeed: number,
	travelDist: number,
	progress: number,
	speed: number,
	maxSpeed: number,
	stats: { [string]: number },
	hitbox: BasePart,
	location: Instance?,
	perch: Vector3,
}

local fleets: { Fleet } = {}
local fleetCounter = 0

local function spawnFleet()
	fleetCounter += 1
	local f = fleetCounter
	local faction = CORE_FACTIONS[rng:NextInteger(1, #CORE_FACTIONS)]
	local factionColor = ShipClasses.Factions[faction].Color
	local center = randomFleetCenter()
	local shipCount = rng:NextInteger(CONFIG.ShipsPerFleetMin, CONFIG.ShipsPerFleetMax)
	local ships: { Ship } = {}

	for s = 1, shipCount do
		local hullId = pickHull(faction)
		local hull = ShipClasses.Hulls[hullId]
		local stats = Fittings.computeStats(hullId, {})

		local part = templateFor(hull.Size):Clone()
		part.Name = string.format("Fleet%d_%s%d", f, hull.Name, s)
		part.Size = templateFor(hull.Size).Size * hull.Scale
		part.Color = ShipClasses.factionColor(hullId)
		part:SetAttribute("ShipClass", hullId)
		part:SetAttribute("Faction", hull.Faction)

		local offset = Vector3.new(
			rng:NextNumber(-1, 1) * CONFIG.FormationRadius,
			rng:NextNumber(-0.3, 0.3) * CONFIG.FormationRadius,
			rng:NextNumber(-1, 1) * CONFIG.FormationRadius
		)
		part.CFrame = CFrame.new(center + offset)
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		part.Parent = fleetsFolder
		Combat.registerShip(part, stats.Health)

		table.insert(ships, {
			part = part,
			trail = addWarpTrail(part, factionColor),
			offset = offset,
			warpStart = part.Position,
			speed = 0,
			orbitSign = if rng:NextNumber() < 0.5 then 1 else -1,
			nextFire = 0,
			hullId = hullId,
			stats = stats,
			baseCF = part.CFrame,
			bankRoll = 0,
		})
	end

	local label = string.format("%s Fleet %d", faction, f)
	local hitbox = Instance.new("Part")
	hitbox.Name = string.format("Fleet%d_Hitbox", f)
	hitbox.Size = Vector3.one * CONFIG.HitboxSize
	hitbox.CFrame = CFrame.new(center)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox:SetAttribute("WarpTarget", label)
	hitbox:SetAttribute("DropRadius", CONFIG.HitboxSize)
	hitbox.Parent = fleetsFolder

	table.insert(fleets, {
		name = label,
		ships = ships,
		center = center,
		state = "Staging",
		timer = rng:NextNumber(CONFIG.StageTimeMin, CONFIG.StageTimeMax),
		destination = center,
		direction = Vector3.zAxis,
		alignSpeed = 0,
		travelDist = 0,
		progress = 0,
		speed = 0,
		maxSpeed = 0,
		stats = slowestStats(ships),
		hitbox = hitbox,
		location = nil,
		perch = center,
	})
	print(string.format("[FleetWarp] %s staged with %d ships", label, shipCount))
end

----------------------------------------------------------------
-- State machine
----------------------------------------------------------------

local function updateStaging(fleet: Fleet, dt: number)
	fleet.timer -= dt
	if fleet.timer > 0 then return end
	local location, perch = claimLocation()
	if not location or not perch then
		fleet.timer = 5 -- everything occupied; try again later
		return
	end
	fleet.location = location
	fleet.perch = perch
	fleet.destination = perch
	fleet.direction = (perch - fleet.center).Unit
	fleet.alignSpeed = 0
	fleet.state = "Aligning"
	print(string.format("[FleetWarp] %s aligning for warp to %s", fleet.name, location.Name))
end

local function updateAligning(fleet: Fleet, dt: number)
	fleet.alignSpeed = math.min(fleet.alignSpeed + CONFIG.AlignAccel * dt, fleet.stats.AlignSpeed)
	local turnAlpha = 1 - math.exp(-fleet.stats.AlignTurnRate * dt)

	local allAligned = true
	for _, ship in fleet.ships do
		local pos = ship.baseCF.Position + ship.baseCF.LookVector * fleet.alignSpeed * dt
		local targetCF = CFrame.lookAt(pos, pos + fleet.direction)
		local newCF = ship.baseCF.Rotation:Lerp(targetCF.Rotation, turnAlpha) + pos
		ShipMotion.apply(ship, newCF, dt)
		if newCF.LookVector:Dot(fleet.direction) < CONFIG.AlignDotThreshold then
			allAligned = false
		end
	end
	fleet.center += fleet.direction * fleet.alignSpeed * dt * 0.5

	if allAligned and fleet.alignSpeed >= fleet.stats.AlignSpeed * 0.95 then
		local sum = Vector3.zero
		for _, ship in fleet.ships do
			sum += ship.part.Position
		end
		fleet.center = sum / #fleet.ships
		for _, ship in fleet.ships do
			ship.offset = ship.part.Position - fleet.center
			ship.warpStart = ship.part.Position
			ship.trail.Enabled = true
		end
		fleet.direction = (fleet.destination - fleet.center).Unit
		fleet.travelDist = (fleet.destination - fleet.center).Magnitude
		fleet.progress = 0
		fleet.speed = CONFIG.WarpEntrySpeed
		fleet.maxSpeed = math.clamp(fleet.travelDist * 0.8, 150, fleet.stats.WarpMaxSpeed)
		fleet.state = "Warping"
		print(string.format("[FleetWarp] %s warping (top speed %.0f studs/s)", fleet.name, fleet.maxSpeed))
	end
end

local function updateWarping(fleet: Fleet, dt: number)
	local remaining = fleet.travelDist - fleet.progress
	local accelerated = fleet.speed * math.exp(fleet.stats.WarpAccelK * dt)
	local decelLimit = remaining * CONFIG.WarpDecelRate + CONFIG.WarpExitSpeed
	fleet.speed = math.min(accelerated, fleet.maxSpeed, decelLimit)

	fleet.progress += fleet.speed * dt
	if fleet.progress >= fleet.travelDist - 1 then
		local delta = fleet.direction * fleet.travelDist
		for _, ship in fleet.ships do
			local finalPos = ship.warpStart + delta
			ShipMotion.apply(ship, CFrame.lookAt(finalPos, finalPos + fleet.direction), dt)
			ship.trail.Enabled = false
			ship.speed = 0
		end
		fleet.center += delta
		fleet.state = "Perched"
		local locName = if fleet.location then fleet.location.Name else "?"
		print(string.format("[FleetWarp] %s perched at %s", fleet.name, locName))
		return
	end

	local delta = fleet.direction * fleet.progress
	for _, ship in fleet.ships do
		local pos = ship.warpStart + delta
		ShipMotion.apply(ship, CFrame.lookAt(pos, pos + fleet.direction), dt)
	end
end

local function updatePerched(fleet: Fleet)
	local _, playerCenter = getPlayerShips()
	if playerCenter and (playerCenter - fleet.center).Magnitude <= CONFIG.AggroRange then
		fleet.state = "Engaging"
		print(string.format("[FleetWarp] %s engaging the player fleet!", fleet.name))
	end
end

local function updateEngaging(fleet: Fleet, dt: number, now: number)
	local playerShips, playerCenter = getPlayerShips()
	if not playerCenter or (playerCenter - fleet.center).Magnitude > CONFIG.DeaggroRange then
		fleet.state = "Returning"
		print(string.format("[FleetWarp] %s disengaging, returning to perch", fleet.name))
		return
	end

	local sum = Vector3.zero
	for _, ship in fleet.ships do
		local pos = ship.baseCF.Position
		local toCenter = playerCenter - pos
		local dist = toCenter.Magnitude
		local moveDir = Vector3.zero
		if dist > 0.5 then
			-- continuous blend of orbit tangent and radial correction: no hard
			-- state switching at the band edges, so no direction jitter
			local radial = toCenter / dist
			local orbit = ship.stats.OrbitRange
			local tangent = radial:Cross(Vector3.yAxis)
			tangent = if tangent.Magnitude < 0.05 then Vector3.xAxis else tangent.Unit
			local radialWeight = math.clamp((dist - orbit) / (CONFIG.OrbitBand * 2), -1, 1)
			moveDir = (tangent * ship.orbitSign * (1 - math.abs(radialWeight) * 0.5)
				+ radial * radialWeight).Unit
		end

		ship.speed = math.min(ship.speed + CONFIG.CombatAccel * dt, ship.stats.SublightSpeed)
		local newPos = pos + moveDir * ship.speed * dt
		if newPos.Y < CONFIG.MinCombatAltitude then
			newPos = Vector3.new(newPos.X, CONFIG.MinCombatAltitude, newPos.Z)
		end
		local alpha = 1 - math.exp(-CONFIG.CombatTurnRate * dt)
		if moveDir.Magnitude > 0.05 then
			local targetCF = CFrame.lookAt(newPos, newPos + moveDir)
			ShipMotion.apply(ship, ship.baseCF.Rotation:Lerp(targetCF.Rotation, alpha) + newPos, dt)
		else
			ShipMotion.apply(ship, ship.baseCF.Rotation + newPos, dt)
		end
		sum += newPos

		-- fire at the nearest player ship in weapon range
		if now >= ship.nextFire then
			local best: BasePart? = nil
			local bestDist = ship.stats.WeaponRange
			for _, playerShip in playerShips do
				local d = (playerShip.Position - newPos).Magnitude
				if d <= bestDist then
					best, bestDist = playerShip, d
				end
			end
			if best then
				Combat.fire(ship.stats.Weapon, ship.part, best, ship.stats)
				ship.nextFire = now + ship.stats.Cooldown
			end
		end
	end
	fleet.center = sum / math.max(#fleet.ships, 1)
end

local function updateReturning(fleet: Fleet, dt: number)
	local _, playerCenter = getPlayerShips()
	if playerCenter and (playerCenter - fleet.center).Magnitude <= CONFIG.AggroRange then
		fleet.state = "Engaging"
		return
	end
	local allHome = true
	local sum = Vector3.zero
	for _, ship in fleet.ships do
		local dest = fleet.perch + ship.offset
		local toDest = dest - ship.baseCF.Position
		local dist = toDest.Magnitude
		if dist > 4 then
			allHome = false
			local dir = toDest / dist
			ship.speed = math.min(
				ship.speed + CONFIG.CombatAccel * dt,
				ship.stats.SublightSpeed,
				dist * 1.5 + 3
			)
			local newPos = ship.baseCF.Position + dir * math.min(ship.speed * dt, dist)
			local alpha = 1 - math.exp(-CONFIG.CombatTurnRate * dt)
			local targetCF = CFrame.lookAt(newPos, newPos + dir)
			ShipMotion.apply(ship, ship.baseCF.Rotation:Lerp(targetCF.Rotation, alpha) + newPos, dt)
			sum += newPos
		else
			ship.speed = 0
			sum += ship.part.Position
		end
	end
	fleet.center = sum / math.max(#fleet.ships, 1)
	if allHome then
		fleet.state = "Perched"
	end
end

----------------------------------------------------------------
-- Death handling
----------------------------------------------------------------

Combat.ShipDied.Event:Connect(function(part: BasePart)
	for fi, fleet in fleets do
		for si, ship in fleet.ships do
			if ship.part == part then
				table.remove(fleet.ships, si)
				if #fleet.ships == 0 then
					print(string.format("[FleetWarp] %s destroyed!", fleet.name))
					fleet.hitbox:Destroy()
					if fleet.location then
						occupied[fleet.location] = nil
					end
					table.remove(fleets, fi)
					task.delay(CONFIG.RespawnDelay, spawnFleet)
				else
					fleet.stats = slowestStats(fleet.ships)
				end
				return
			end
		end
	end
end)

----------------------------------------------------------------
-- Main loop
----------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for _, fleet in fleets do
		if fleet.state == "Staging" then
			updateStaging(fleet, dt)
		elseif fleet.state == "Aligning" then
			updateAligning(fleet, dt)
		elseif fleet.state == "Warping" then
			updateWarping(fleet, dt)
		elseif fleet.state == "Perched" then
			updatePerched(fleet)
		elseif fleet.state == "Engaging" then
			updateEngaging(fleet, dt, now)
		elseif fleet.state == "Returning" then
			updateReturning(fleet, dt)
		end
		fleet.hitbox.CFrame = CFrame.new(fleet.center)
	end
end)

for _ = 1, CONFIG.FleetCount do
	spawnFleet()
end
print(string.format("[FleetWarp] %d fleets spawned", #fleets))