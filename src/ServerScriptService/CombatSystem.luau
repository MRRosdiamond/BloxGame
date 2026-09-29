--!strict
-- CombatSystem: ship health/death and the three projectile types.
--   Rockets: ejected from the hull in a random direction, slow down, then snap
--            toward the target and accelerate. Can't miss - but burns fuel, so
--            a faster target can outrun it.
--   Bullets: fast straight shot aimed at where the target is right now; a
--            moving target can dodge it. Leaves a warp-style trail.
--   Laser:   long-range beam that glows and flickers before vanishing.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShipClasses = require(ReplicatedStorage:WaitForChild("ShipClasses"))

local CombatSystem = {}

CombatSystem.ShipDied = Instance.new("BindableEvent")
CombatSystem.Weapons = require(ReplicatedStorage:WaitForChild("WeaponSpecs"))

local rng = Random.new()

local projectileFolder = Instance.new("Folder")
projectileFolder.Name = "Projectiles"
projectileFolder.Parent = workspace

----------------------------------------------------------------
-- Health
----------------------------------------------------------------

-- health comes from the ship's fitted stats; falls back to the bare hull
function CombatSystem.registerShip(part: BasePart, health: number?)
	local hp = health
	if not hp then
		local hull = ShipClasses.Hulls[part:GetAttribute("ShipClass")]
		hp = if hull then hull.Stats.Health else 100
	end
	part:SetAttribute("MaxHealth", hp)
	part:SetAttribute("Health", hp)
end

function CombatSystem.isAlive(part: BasePart?): boolean
	return part ~= nil and part.Parent ~= nil and ((part:GetAttribute("Health") :: number?) or 0) > 0
end

function CombatSystem.applyDamage(part: BasePart, damage: number)
	if not CombatSystem.isAlive(part) then return end
	local hp = (part:GetAttribute("Health") :: number) - damage
	part:SetAttribute("Health", hp)
	if hp <= 0 then
		local boom = Instance.new("Explosion")
		boom.Position = part.Position
		boom.BlastRadius = 0 -- purely visual
		boom.BlastPressure = 0
		boom.Parent = workspace
		CombatSystem.ShipDied:Fire(part)
		part:Destroy()
	end
end

----------------------------------------------------------------
-- Projectiles
----------------------------------------------------------------

local function makeProjectilePart(size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = projectileFolder
	return part
end

local function addTrail(part: BasePart, color: Color3, lifetime: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, part.Size.Y / 2, part.Size.Z / 2)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -part.Size.Y / 2, part.Size.Z / 2)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Lifetime = lifetime
	trail.FaceCamera = true
	trail.Parent = part
end

local function hitRadius(target: BasePart): number
	return math.max(target.Size.X, target.Size.Y, target.Size.Z) / 2 + 4
end

type Bullet = { part: BasePart, dir: Vector3, speed: number, traveled: number, maxDist: number, target: BasePart, damage: number }
type Rocket = { part: BasePart, vel: Vector3, phase: string, t: number, speed: number, fuel: number, target: BasePart, damage: number, topSpeed: number }
type Laser = { beam: BasePart, source: BasePart, target: BasePart, t: number, duration: number, damage: number, applied: boolean }

local bullets: { Bullet } = {}
local rockets: { Rocket } = {}
local lasers: { Laser } = {}

-- `stats` (optional) carries the shooter's fitted Damage / WeaponRange
function CombatSystem.fire(weaponName: string, source: BasePart, target: BasePart, stats: { [string]: any }?)
	if not CombatSystem.isAlive(source) or not CombatSystem.isAlive(target) then return end
	local spec = CombatSystem.Weapons[weaponName]
	if not spec then return end
	local fromPlayer = source.Parent ~= nil and (source.Parent :: Instance).Name == "PlayerFleet"
	local damage = (stats and stats.Damage) or spec.Damage
	local range = (stats and stats.WeaponRange) or spec.Range

	if weaponName == "Bullets" then
		local part = makeProjectilePart(Vector3.new(0.5, 0.5, 3), Color3.fromRGB(255, 225, 130))
		addTrail(part, Color3.fromRGB(255, 225, 130), 0.4)
		local dir = (target.Position - source.Position).Unit
		part.CFrame = CFrame.lookAt(source.Position + dir * 4, source.Position + dir * 20)
		table.insert(bullets, {
			part = part, dir = dir, speed = spec.Speed, traveled = 0,
			maxDist = range * 1.5, target = target, damage = damage,
		})
	elseif weaponName == "Rockets" then
		local part = makeProjectilePart(Vector3.new(0.6, 0.6, 2.4), Color3.fromRGB(255, 150, 70))
		addTrail(part, Color3.fromRGB(255, 150, 70), 0.5)
		local ejectDir = rng:NextUnitVector()
		part.CFrame = CFrame.lookAt(source.Position + ejectDir * 2, source.Position + ejectDir * 20)
		table.insert(rockets, {
			part = part, vel = ejectDir * 45, phase = "eject", t = 0, speed = 10,
			fuel = math.max(spec.Fuel, range * 2.2), target = target,
			damage = damage, topSpeed = spec.TopSpeed,
		})
	elseif weaponName == "Laser" then
		local color = if fromPlayer then Color3.fromRGB(120, 255, 160) else Color3.fromRGB(255, 90, 90)
		local beam = makeProjectilePart(Vector3.new(0.6, 0.6, 1), color)
		local a, b = source.Position, target.Position
		beam.Size = Vector3.new(0.6, 0.6, (b - a).Magnitude)
		beam.CFrame = CFrame.lookAt((a + b) / 2, b)
		table.insert(lasers, {
			beam = beam, source = source, target = target, t = 0,
			duration = spec.Duration, damage = damage, applied = false,
		})
	end
end

RunService.Heartbeat:Connect(function(dt)
	for i = #bullets, 1, -1 do
		local b = bullets[i]
		local step = b.speed * dt
		b.part.CFrame += b.dir * step
		b.traveled += step
		local done = b.traveled >= b.maxDist
		if CombatSystem.isAlive(b.target)
			and (b.part.Position - b.target.Position).Magnitude <= hitRadius(b.target) then
			CombatSystem.applyDamage(b.target, b.damage)
			done = true
		end
		if done then
			b.part:Destroy()
			table.remove(bullets, i)
		end
	end

	for i = #rockets, 1, -1 do
		local r = rockets[i]
		r.t += dt
		if r.phase == "eject" then
			r.vel *= math.exp(-2.5 * dt) -- coast and bleed off the launch kick
			if r.t >= 0.7 then
				r.phase = "homing"
				r.speed = math.max(r.vel.Magnitude, 10)
			end
		elseif CombatSystem.isAlive(r.target) then
			-- hard turn onto the target, then burn
			local toTarget = r.target.Position - r.part.Position
			if toTarget.Magnitude > 0.1 then
				r.speed = math.min(r.speed + 100 * dt, r.topSpeed)
				r.vel = toTarget.Unit * r.speed
			end
		end
		local step = r.vel * dt
		local newPos = r.part.Position + step
		if r.vel.Magnitude > 0.05 then
			r.part.CFrame = CFrame.lookAt(newPos, newPos + r.vel)
		else
			r.part.CFrame += step
		end
		r.fuel -= step.Magnitude
		local done = r.fuel <= 0
		if CombatSystem.isAlive(r.target) then
			if (r.part.Position - r.target.Position).Magnitude <= hitRadius(r.target) then
				CombatSystem.applyDamage(r.target, r.damage)
				done = true
			end
		elseif r.phase == "homing" and r.t > 3 then
			done = true -- target already died; fizzle
		end
		if done then
			r.part:Destroy()
			table.remove(rockets, i)
		end
	end

	for i = #lasers, 1, -1 do
		local l = lasers[i]
		l.t += dt
		if l.t >= l.duration or not CombatSystem.isAlive(l.source) then
			l.beam:Destroy()
			table.remove(lasers, i)
		else
			if CombatSystem.isAlive(l.target) then
				local a, b = l.source.Position, l.target.Position
				l.beam.Size = Vector3.new(0.6, 0.6, (b - a).Magnitude)
				l.beam.CFrame = CFrame.lookAt((a + b) / 2, b)
				if not l.applied and l.t >= 0.15 then
					l.applied = true
					CombatSystem.applyDamage(l.target, l.damage)
				end
			end
			l.beam.Transparency = 0.1 + 0.4 * math.abs(math.sin(l.t * 45)) -- flicker
		end
	end
end)

return CombatSystem