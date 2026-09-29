--!nonstrict
-- ShipSmoothing: client-side re-rendering of every ship.
--
-- The fleets are anchored parts moved by the server each Heartbeat. Roblox
-- replicates those as plain property updates - roughly 20 a second, with no
-- interpolation - so however smooth the server's maths is, the client sees the
-- hull teleport between a handful of positions per second. Against a camera
-- that renders at full framerate that reads as constant jitter, worst of all
-- when the camera is locked to a ship.
--
-- So: treat each replicated CFrame as a *target* rather than the truth. Measure
-- the velocity between targets, extrapolate along it between updates, and ease
-- the part toward that goal every frame. The server stays authoritative (it
-- still owns collisions, damage and click targeting); only what the local
-- player sees is smoothed.

local ShipSmoothing = {}

local EXTRAPOLATE_CAP = 0.2 -- never guess further ahead than this
local SNAP_DISTANCE = 400 -- teleports (respawns, warp entry) jump instead of flying
local POSITION_STIFFNESS = 20
local ROTATION_STIFFNESS = 14
local STALE_AFTER = 0.25 -- no update for this long: the ship has stopped
local VELOCITY_DECAY = 10

local tracked = {}
local pruneTimer = 0

local function isServerUpdate(current: CFrame, lastWrite: CFrame?): boolean
	if not lastWrite then
		return true
	end
	-- our own write lands bit-exact, so anything that moved is from the server
	return (current.Position - lastWrite.Position).Magnitude > 1e-4
		or current.LookVector:Dot(lastWrite.LookVector) < 0.9999999
end

local function smoothPart(part: BasePart, dt: number, now: number)
	local record = tracked[part]
	if not record then
		tracked[part] = {
			target = part.CFrame,
			targetTime = now,
			velocity = Vector3.zero,
			render = part.CFrame,
			lastWrite = part.CFrame,
		}
		return
	end

	local current = part.CFrame
	if isServerUpdate(current, record.lastWrite) then
		local elapsed = now - record.targetTime
		if elapsed > 1e-3 then
			local measured = (current.Position - record.target.Position) / elapsed
			-- half-and-half keeps the estimate steady when updates arrive unevenly
			record.velocity = record.velocity:Lerp(measured, 0.5)
		end
		record.target = current
		record.targetTime = now
	end

	local age = now - record.targetTime
	if age > STALE_AFTER then
		record.velocity = record.velocity:Lerp(Vector3.zero, 1 - math.exp(-VELOCITY_DECAY * dt))
	end

	-- Lead by the easing's own steady-state lag (v/k) as well as the time since
	-- the last update, otherwise a ship at 2000 studs/s renders ~100 studs
	-- behind where it really is. Both terms vanish as the ship slows.
	local lead = math.min(age, EXTRAPOLATE_CAP) + 1 / POSITION_STIFFNESS
	local goal = record.target.Position + record.velocity * lead
	if (goal - record.render.Position).Magnitude > SNAP_DISTANCE then
		record.render = record.target
		record.velocity = Vector3.zero
	else
		local position = record.render.Position:Lerp(goal, 1 - math.exp(-POSITION_STIFFNESS * dt))
		local rotation = record.render.Rotation:Lerp(record.target.Rotation, 1 - math.exp(-ROTATION_STIFFNESS * dt))
		record.render = rotation + position
	end

	part.CFrame = record.render
	record.lastWrite = record.render
end

-- Call once per rendered frame, before anything reads ship positions.
function ShipSmoothing.update(dt: number)
	local now = os.clock()
	for _, folderName in { "Fleets", "PlayerFleet" } do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("BasePart") then
					smoothPart(child, dt, now)
				end
			end
		end
	end

	pruneTimer += dt
	if pruneTimer >= 2 then
		pruneTimer = 0
		for part in tracked do
			if not part.Parent then
				tracked[part] = nil
			end
		end
	end
end

return ShipSmoothing