--!strict
-- PlayerFleet: the player's three ships, assembled in the hangar from any hull
-- in the tree with any legal fitting. Mouse-commanded: sublight move, or align
-- and warp. Ships auto-fire their hull's weapon at NPC ships in range (never
-- while in warp). When all three die the client reopens the hangar.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShipClasses = require(ReplicatedStorage:WaitForChild("ShipClasses"))
local Fittings = require(ReplicatedStorage:WaitForChild("Fittings"))
local Combat = require(ServerScriptService:WaitForChild("CombatSystem"))
local ShipMotion = require(ServerScriptService:WaitForChild("ShipMotion"))

local CONFIG = {
	FleetAltitude = 30,
	FleetSize = 3,

	-- Sublight (cruise speed comes from the slowest hull in the fleet)
	SublightAccel = 12,
	SublightTurnRate = 2.0,
	SublightDecelRate = 1.4,
	ArriveDistance = 3,

	-- Warp (all warp figures come from the slowest hull, after fittings)
	MinWarpDistance = 200,
	WarpDropDistance = 60, -- default; hitboxes override via DropRadius
	AlignAccel = 7,
	AlignDotThreshold = 0.999,
	WarpEntrySpeed = 25,
	WarpDecelRate = 3.0,
	WarpExitSpeed = 30,

	BuildCooldown = 2,
}

----------------------------------------------------------------
-- Remotes
----------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "FleetCommand"
local moveToRemote = Instance.new("RemoteEvent")
moveToRemote.Name = "MoveTo"
moveToRemote.Parent = remotes
local warpToRemote = Instance.new("RemoteEvent")
warpToRemote.Name = "WarpTo"
warpToRemote.Parent = remotes
local buildRemote = Instance.new("RemoteEvent")
buildRemote.Name = "BuildFleet"
buildRemote.Parent = remotes
local destroyedRemote = Instance.new("RemoteEvent")
destroyedRemote.Name = "FleetDestroyed"
destroyedRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

----------------------------------------------------------------
-- Templates (one green placeholder per hull size)
----------------------------------------------------------------

local templates: { [string]: BasePart } = {}
local centroid = Vector3.zero
local templateCount = 0
for size, index in ShipClasses.SizeModels do
	local part = workspace:FindFirstChild("playerdummy" .. index)
	if part and part:IsA("BasePart") then
		local clone = part:Clone()
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false -- own ships shouldn't block command clicks
		templates[size] = clone
		centroid += part.Position
		templateCount += 1
		part.Parent = nil
	end
end
assert(templateCount > 0, "PlayerFleet: no playerdummy parts found in Workspace")
centroid /= templateCount

local function templateFor(size: string): BasePart
	return templates[size] or templates.Medium or templates.Small or templates.Large
end

-- The fleet flies out of the trade hub, holding station just off its ring.
-- Falls back to where the placeholder ships were parked if the hub is missing.
local function findHome(): Vector3
	local locations = workspace:FindFirstChild("Locations")
	local hub = locations and locations:FindFirstChild("TradeHub")
	local hitbox = hub and hub:FindFirstChild("WarpHitbox")
	if hitbox and hitbox:IsA("BasePart") then
		return hitbox.Position + Vector3.new(0, -40, 210)
	end
	return Vector3.new(centroid.X, CONFIG.FleetAltitude, centroid.Z)
end

local homeCenter = findHome()

local fleetFolder = Instance.new("Folder")
fleetFolder.Name = "PlayerFleet"
fleetFolder.Parent = workspace

local function addWarpTrail(ship: BasePart): Trail
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
	trail.Color = ColorSequence.new(Color3.fromRGB(140, 255, 170))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.35
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = ship
	return trail
end

----------------------------------------------------------------
-- Fleet state
----------------------------------------------------------------

type Ship = {
	part: BasePart,
	trail: Trail,
	offset: Vector3,
	warpStart: Vector3,
	nextFire: number,
	hullId: string,
	stats: { [string]: any },
	baseCF: CFrame,
	bankRoll: number,
}

local ships: { Ship } = {}
local fleetStats: { [string]: number } = {}
local center = homeCenter
local state: string = "Idle" -- Idle | Moving | Aligning | Warping
local destination = center
local direction = Vector3.zAxis
local speed = 0
local travelDist = 0
local progress = 0
local warpSpeed = 0
local maxWarpSpeed = 0
local buildReadyAt = 0

-- the fleet moves at the pace of its slowest hull, fittings included
local function refreshFleetStats()
	table.clear(fleetStats)
	for _, ship in ships do
		for _, key in Fittings.MoveKeys do
			local value = ship.stats[key]
			fleetStats[key] = if fleetStats[key] then math.min(fleetStats[key], value) else value
		end
	end
end

local function buildFleet(loadout: { any })
	for _, ship in ships do
		if ship.part.Parent then
			ship.part:Destroy()
		end
	end
	table.clear(ships)

	homeCenter = findHome() -- the hub may have been built after this script ran
	center = homeCenter
	state = "Idle"
	speed = 0

	local offsets = { Vector3.new(-22, 0, 0), Vector3.new(0, 3, -11), Vector3.new(22, 0, 0) }
	local summary: { string } = {}
	for i, entry in loadout do
		local hullId = entry.hull
		local hull = ShipClasses.Hulls[hullId]
		local stats = Fittings.computeStats(hullId, entry.modules)
		local template = templateFor(hull.Size)

		local part = template:Clone()
		part.Name = "PlayerShip" .. i
		part.Size = template.Size * hull.Scale
		part:SetAttribute("ShipClass", hullId)
		part.CFrame = CFrame.new(center + offsets[i])
		part.Parent = fleetFolder
		Combat.registerShip(part, stats.Health)

		table.insert(ships, {
			part = part,
			trail = addWarpTrail(part),
			offset = offsets[i],
			warpStart = part.Position,
			nextFire = 0,
			hullId = hullId,
			stats = stats,
			baseCF = part.CFrame,
			bankRoll = 0,
		})
		table.insert(summary, string.format("%s (%d fitted)", hull.Name, #entry.modules))
	end
	refreshFleetStats()
	print("[PlayerFleet] deployed: " .. table.concat(summary, ", "))
end

buildRemote.OnServerEvent:Connect(function(_player, loadout)
	if os.clock() < buildReadyAt then return end
	if typeof(loadout) ~= "table" or #loadout ~= CONFIG.FleetSize then return end
	for _, entry in loadout do
		if typeof(entry) ~= "table" or not Fittings.validate(entry.hull, entry.modules) then
			return
		end
	end
	buildReadyAt = os.clock() + CONFIG.BuildCooldown
	buildFleet(loadout)
end)

----------------------------------------------------------------
-- Orders
----------------------------------------------------------------

local function orderMove(pos: Vector3)
	local y = if pos.Y < 15 then center.Y else math.min(pos.Y, 120)
	destination = Vector3.new(pos.X, y, pos.Z)
	state = "Moving"
end

local function orderWarp(targetPos: Vector3, dropDist: number)
	local toTarget = targetPos - center
	if toTarget.Magnitude < CONFIG.MinWarpDistance then
		orderMove(targetPos - toTarget.Unit * dropDist)
		return
	end
	destination = targetPos - toTarget.Unit * dropDist
	direction = (destination - center).Unit
	speed = 0
	state = "Aligning"
	print(string.format("[PlayerFleet] aligning for warp, distance %.0f studs", (destination - center).Magnitude))
end

moveToRemote.OnServerEvent:Connect(function(_player, pos)
	if #ships == 0 or state == "Warping" then return end
	if typeof(pos) ~= "Vector3" or pos.Magnitude > 5000 then return end
	orderMove(pos)
end)

warpToRemote.OnServerEvent:Connect(function(_player, target)
	if #ships == 0 or state == "Warping" then return end
	if typeof(target) ~= "Instance" or not target:IsA("BasePart") then return end
	local fleets = workspace:FindFirstChild("Fleets")
	local isWarpable = target:GetAttribute("WarpTarget") ~= nil
		or (fleets ~= nil and target:IsDescendantOf(fleets))
	if not isWarpable then return end
	local dropDist = tonumber(target:GetAttribute("DropRadius")) or CONFIG.WarpDropDistance
	orderWarp(target.Position, dropDist)
end)

----------------------------------------------------------------
-- Death handling
----------------------------------------------------------------

Combat.ShipDied.Event:Connect(function(part: BasePart)
	for i, ship in ships do
		if ship.part == part then
			table.remove(ships, i)
			if #ships == 0 then
				state = "Idle"
				print("[PlayerFleet] fleet destroyed!")
				destroyedRemote:FireAllClients()
			else
				refreshFleetStats()
			end
			return
		end
	end
end)

----------------------------------------------------------------
-- Movement
----------------------------------------------------------------

local function moveShips(turnAlpha: number, dt: number)
	for _, ship in ships do
		local pos = center + ship.offset
		local targetCF = CFrame.lookAt(pos, pos + direction)
		ShipMotion.apply(ship, ship.baseCF.Rotation:Lerp(targetCF.Rotation, turnAlpha) + pos, dt)
	end
end

local function updateMoving(dt: number)
	local toDest = destination - center
	local remaining = toDest.Magnitude
	if remaining <= CONFIG.ArriveDistance then
		speed = 0
		state = "Idle"
		return
	end
	direction = toDest.Unit
	speed = math.min(
		speed + CONFIG.SublightAccel * dt,
		fleetStats.SublightSpeed,
		remaining * CONFIG.SublightDecelRate + 2
	)
	center += direction * math.min(speed * dt, remaining)
	moveShips(1 - math.exp(-CONFIG.SublightTurnRate * dt), dt)
end

local function updateAligning(dt: number)
	speed = math.min(speed + CONFIG.AlignAccel * dt, fleetStats.AlignSpeed)
	center += direction * speed * dt
	moveShips(1 - math.exp(-fleetStats.AlignTurnRate * dt), dt)

	local allAligned = true
	for _, ship in ships do
		if ship.baseCF.LookVector:Dot(direction) < CONFIG.AlignDotThreshold then
			allAligned = false
			break
		end
	end
	if allAligned and speed >= fleetStats.AlignSpeed * 0.95 then
		direction = (destination - center).Unit
		travelDist = (destination - center).Magnitude
		progress = 0
		warpSpeed = CONFIG.WarpEntrySpeed
		maxWarpSpeed = math.clamp(travelDist * 0.8, 150, fleetStats.WarpMaxSpeed)
		state = "Warping"
		for _, ship in ships do
			ship.warpStart = ship.part.Position
			ship.trail.Enabled = true
		end
		print(string.format("[PlayerFleet] warping (top speed %.0f studs/s)", maxWarpSpeed))
	end
end

local function updateWarping(dt: number)
	local remaining = travelDist - progress
	local accelerated = warpSpeed * math.exp(fleetStats.WarpAccelK * dt)
	local decelLimit = remaining * CONFIG.WarpDecelRate + CONFIG.WarpExitSpeed
	warpSpeed = math.min(accelerated, maxWarpSpeed, decelLimit)

	progress += warpSpeed * dt
	if progress >= travelDist - 1 then
		local delta = direction * travelDist
		for _, ship in ships do
			local finalPos = ship.warpStart + delta
			ShipMotion.apply(ship, CFrame.lookAt(finalPos, finalPos + direction), dt)
			ship.trail.Enabled = false
		end
		center += delta
		speed = 0
		state = "Idle"
		print("[PlayerFleet] dropped out of warp")
		return
	end

	local delta = direction * progress
	for _, ship in ships do
		local pos = ship.warpStart + delta
		ShipMotion.apply(ship, CFrame.lookAt(pos, pos + direction), dt)
	end
end

----------------------------------------------------------------
-- Weapons
----------------------------------------------------------------

local function getNpcShips(): { BasePart }
	local folder = workspace:FindFirstChild("Fleets")
	local list: { BasePart } = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("ShipClass")
				and ((child:GetAttribute("Health") :: number?) or 0) > 0 then
				table.insert(list, child)
			end
		end
	end
	return list
end

----------------------------------------------------------------
-- Main loop
----------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	if #ships == 0 then return end
	if state == "Moving" then
		updateMoving(dt)
	elseif state == "Aligning" then
		updateAligning(dt)
	elseif state == "Warping" then
		updateWarping(dt)
	end

	-- weapons free unless committed to the warp tunnel
	if state ~= "Warping" then
		local now = os.clock()
		local npcShips: { BasePart }? = nil
		for _, ship in ships do
			if now >= ship.nextFire then
				if not npcShips then
					npcShips = getNpcShips()
				end
				local best: BasePart? = nil
				local bestDist = ship.stats.WeaponRange
				for _, npc in npcShips :: { BasePart } do
					local d = (npc.Position - ship.part.Position).Magnitude
					if d <= bestDist then
						best, bestDist = npc, d
					end
				end
				if best then
					Combat.fire(ship.stats.Weapon, ship.part, best, ship.stats)
					ship.nextFire = now + ship.stats.Cooldown
				end
			end
		end
	end
end)

print("[PlayerFleet] ready - waiting for a hangar deployment")