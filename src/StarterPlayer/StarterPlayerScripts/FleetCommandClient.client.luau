--!nonstrict
-- FleetCommandClient: mouse commands, the follow camera, and the hangar.
--   left-click empty space        -> sublight move order
--   left-click a warp hitbox/ship -> "WARP TO <name>" button pinned to it
--   F / button                    -> follow camera (RMB drag rotates, wheel zooms)
--   H / button                    -> fleet hangar (ship tree + fitting)
--   LeftShift                     -> sprint

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local FleetHangarUI = require(script.Parent:WaitForChild("FleetHangarUI"))
local ShipSmoothing = require(script.Parent:WaitForChild("ShipSmoothing"))

local remotes = ReplicatedStorage:WaitForChild("FleetCommand")
local moveToRemote = remotes:WaitForChild("MoveTo")
local warpToRemote = remotes:WaitForChild("WarpTo")
local buildRemote = remotes:WaitForChild("BuildFleet")
local destroyedRemote = remotes:WaitForChild("FleetDestroyed")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ACCENT = Color3.fromRGB(120, 200, 255)
local PANEL_BG = Color3.fromRGB(12, 18, 30)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FleetCommandUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- Character speed / sprint
----------------------------------------------------------------

local WALK_SPEED = 60
local SPRINT_SPEED = 240

local function getHumanoid(): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.WalkSpeed = WALK_SPEED
end)
if player.Character then
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.WalkSpeed = WALK_SPEED
	end
end

----------------------------------------------------------------
-- Warp button (pinned above its target in the world)
----------------------------------------------------------------

local warpButton = Instance.new("TextButton")
warpButton.Name = "WarpButton"
warpButton.AutomaticSize = Enum.AutomaticSize.X
warpButton.Size = UDim2.fromOffset(0, 36)
warpButton.AnchorPoint = Vector2.new(0.5, 1)
warpButton.BackgroundColor3 = PANEL_BG
warpButton.BackgroundTransparency = 0.15
warpButton.Text = "\u{26A1} WARP TO"
warpButton.TextColor3 = ACCENT
warpButton.Font = Enum.Font.GothamBold
warpButton.TextSize = 16
warpButton.Visible = false
warpButton.Parent = screenGui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = warpButton
local stroke = Instance.new("UIStroke")
stroke.Color = ACCENT
stroke.Transparency = 0.4
stroke.Parent = warpButton
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.Parent = warpButton

local targetHighlight = Instance.new("Highlight")
targetHighlight.FillColor = ACCENT
targetHighlight.FillTransparency = 0.9
targetHighlight.OutlineColor = ACCENT
targetHighlight.OutlineTransparency = 0.3
targetHighlight.Enabled = false
targetHighlight.Parent = screenGui

local currentTarget: BasePart? = nil

local function hideWarpMenu()
	warpButton.Visible = false
	targetHighlight.Enabled = false
	targetHighlight.Adornee = nil
	currentTarget = nil
end

local function showWarpMenu(target: BasePart, name: string)
	currentTarget = target
	warpButton.Text = "\u{26A1} WARP TO " .. name:upper()
	local adornee = if target.Parent and target.Parent:IsA("Model") then target.Parent else target
	targetHighlight.Adornee = adornee
	targetHighlight.Enabled = true
end

warpButton.Activated:Connect(function()
	if currentTarget then
		warpToRemote:FireServer(currentTarget)
	end
	hideWarpMenu()
end)

----------------------------------------------------------------
-- Follow camera
----------------------------------------------------------------

local followEnabled = false
local followYaw = 0
local followPitch = -0.35 -- negative = camera above the ship
local followZoom = 70
local rotatingCamera = false
local followButton: TextButton? = nil

local function followOffset(): Vector3
	local cy, sy = math.cos(followYaw), math.sin(followYaw)
	local cp, sp = math.cos(followPitch), math.sin(followPitch)
	return Vector3.new(sy * cp, -sp, cy * cp)
end

-- the flagship is the biggest hull currently flying
local function getFlagship(): BasePart?
	local folder = workspace:FindFirstChild("PlayerFleet")
	if not folder then return nil end
	local best, bestVolume = nil, 0
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			local volume = child.Size.X * child.Size.Y * child.Size.Z
			if volume > bestVolume then
				best, bestVolume = child, volume
			end
		end
	end
	return best
end

local function setFollow(enabled: boolean)
	followEnabled = enabled
	if followButton then
		followButton.Text = if enabled then "\u{1F4F7} FOLLOW: ON" else "\u{1F4F7} FOLLOW: OFF"
	end
	if enabled then
		local flagship = getFlagship()
		if flagship then
			local look = flagship.CFrame.LookVector
			followYaw = math.atan2(-look.X, -look.Z)
			followPitch = -0.35
		end
	else
		rotatingCamera = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = getHumanoid()
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	-- re-render every ship before anything reads a ship position this frame
	ShipSmoothing.update(dt)

	local target = currentTarget
	if not target or not target.Parent then
		if targetHighlight.Enabled then
			hideWarpMenu()
		end
	else
		local screenPos, onScreen = camera:WorldToViewportPoint(target.Position)
		if onScreen then
			warpButton.Visible = true
			warpButton.Position = UDim2.fromOffset(screenPos.X, screenPos.Y - 24)
		else
			warpButton.Visible = false
		end
	end

	if followEnabled then
		local flagship = getFlagship()
		if flagship then
			-- ShipSmoothing already removed the replication steps, so the camera
			-- can sit rigidly on the hull: any lag here would put the jitter back
			-- as relative motion between ship and frame.
			camera.CameraType = Enum.CameraType.Scriptable
			local focus = flagship.Position
			camera.CFrame = CFrame.lookAt(focus + followOffset() * followZoom, focus)
		else
			setFollow(false) -- fleet is gone
		end
	end
end)

----------------------------------------------------------------
-- Hangar + HUD buttons
----------------------------------------------------------------

local hangar = FleetHangarUI.create(screenGui, function(loadout)
	buildRemote:FireServer(loadout)
end)

local hangarToggle = Instance.new("TextButton")
hangarToggle.Name = "HangarToggle"
hangarToggle.Size = UDim2.fromOffset(130, 34)
hangarToggle.Position = UDim2.fromOffset(12, 60)
hangarToggle.BackgroundColor3 = PANEL_BG
hangarToggle.BackgroundTransparency = 0.15
hangarToggle.Text = "\u{2699} HANGAR"
hangarToggle.TextColor3 = ACCENT
hangarToggle.Font = Enum.Font.GothamBold
hangarToggle.TextSize = 14
hangarToggle.Parent = screenGui
local tCorner = Instance.new("UICorner")
tCorner.CornerRadius = UDim.new(0, 8)
tCorner.Parent = hangarToggle
hangarToggle.Activated:Connect(function()
	hangar.toggle()
end)

local followBtn = Instance.new("TextButton")
followBtn.Name = "FollowButton"
followBtn.Size = UDim2.fromOffset(150, 34)
followBtn.Position = UDim2.fromOffset(12, 100)
followBtn.BackgroundColor3 = PANEL_BG
followBtn.BackgroundTransparency = 0.15
followBtn.Text = "\u{1F4F7} FOLLOW: OFF"
followBtn.TextColor3 = ACCENT
followBtn.Font = Enum.Font.GothamBold
followBtn.TextSize = 14
followBtn.Parent = screenGui
local fCorner = Instance.new("UICorner")
fCorner.CornerRadius = UDim.new(0, 8)
fCorner.Parent = followBtn
followButton = followBtn
followBtn.Activated:Connect(function()
	setFollow(not followEnabled)
end)

-- the hangar covers the screen, so fold the HUD away while it is up
hangar.onVisibilityChanged(function(open)
	hangarToggle.Visible = not open
	followBtn.Visible = not open
	if open then
		hideWarpMenu()
	end
end)

destroyedRemote.OnClientEvent:Connect(function()
	hangar.open()
end)

hangar.open() -- start in the hangar: nothing is flying yet

----------------------------------------------------------------
-- Click marker
----------------------------------------------------------------

local function spawnClickMarker(pos: Vector3)
	local marker = Instance.new("Part")
	marker.Shape = Enum.PartType.Ball
	marker.Size = Vector3.one * 2
	marker.Position = pos
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(120, 255, 160)
	marker.Parent = camera -- client-only effect
	TweenService:Create(marker, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		Size = Vector3.one * 0.2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(marker, 0.9)
end

----------------------------------------------------------------
-- Input
----------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		local humanoid = getHumanoid()
		if humanoid then
			humanoid.WalkSpeed = SPRINT_SPEED
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		setFollow(not followEnabled)
	elseif input.KeyCode == Enum.KeyCode.H then
		hangar.toggle()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and followEnabled then
		rotatingCamera = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		local humanoid = getHumanoid()
		if humanoid then
			humanoid.WalkSpeed = WALK_SPEED
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		rotatingCamera = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if rotatingCamera and followEnabled then
			followYaw -= input.Delta.X * 0.008
			followPitch = math.clamp(followPitch + input.Delta.Y * 0.008, -1.2, 0.5)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel
		and followEnabled and not gameProcessed then
		followZoom = math.clamp(followZoom * (1 - input.Position.Z * 0.12), 20, 400)
	end
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or hangar.isOpen() then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local exclude = {}
	if player.Character then
		table.insert(exclude, player.Character)
	end
	rayParams.FilterDescendantsInstances = exclude

	local ray = camera:ViewportPointToRay(input.Position.X, input.Position.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 5000, rayParams)
	if not result then
		hideWarpMenu()
		return
	end

	local warpName = result.Instance:GetAttribute("WarpTarget")
	local fleets = workspace:FindFirstChild("Fleets")
	if warpName then
		showWarpMenu(result.Instance, warpName)
	elseif fleets and result.Instance:IsDescendantOf(fleets) then
		showWarpMenu(result.Instance, "Hostile Fleet")
	else
		hideWarpMenu()
		moveToRemote:FireServer(result.Position)
		spawnClickMarker(result.Position)
	end
end)