--!strict
-- ShipMotion: ships roll into turns like aircraft. The roll angle follows the
-- yaw rate and eases back out on straightaways.
-- Movement code keeps a per-ship UN-banked CFrame in ship.baseCF and calls
-- apply() with the new base CFrame instead of writing part.CFrame directly;
-- apply() layers the bank roll on top.

local ShipMotion = {}

local BANK_FACTOR = 0.5 -- roll radians per radian/s of yaw rate
local MAX_BANK = math.rad(35)
local SMOOTHING = 5 -- how quickly the roll eases toward its target

function ShipMotion.apply(ship: any, newBaseCF: CFrame, dt: number)
	local target = 0
	if dt > 0 then
		local a = (ship.baseCF :: CFrame).LookVector
		local b = newBaseCF.LookVector
		local a2 = Vector3.new(a.X, 0, a.Z)
		local b2 = Vector3.new(b.X, 0, b.Z)
		if a2.Magnitude > 0.01 and b2.Magnitude > 0.01 then
			local crossY = a2.Unit:Cross(b2.Unit).Y -- +Y cross = turning left
			local yawRate = math.asin(math.clamp(crossY, -1, 1)) / dt
			target = math.clamp(yawRate * BANK_FACTOR, -MAX_BANK, MAX_BANK)
		end
	end
	local alpha = 1 - math.exp(-SMOOTHING * dt)
	ship.bankRoll += (target - ship.bankRoll) * alpha
	ship.baseCF = newBaseCF
	ship.part.CFrame = newBaseCF * CFrame.Angles(0, 0, ship.bankRoll)
end

return ShipMotion