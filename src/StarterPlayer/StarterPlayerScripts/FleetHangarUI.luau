--!nonstrict
-- FleetHangarUI: the ship tree and fitting bench.
--
--   left   - the tree, four columns wide, faction lines converging rightwards
--   right  - HULL tab (what the selected ship is) / FITTING tab (what you hang
--            on the ship in the active fleet slot)
--   bottom - the three fleet slots and the deploy button
--
-- Nothing here talks to the server directly: the deploy button hands the
-- finished loadout to the callback passed into create().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShipClasses = require(ReplicatedStorage:WaitForChild("ShipClasses"))
local Fittings = require(ReplicatedStorage:WaitForChild("Fittings"))
local WeaponSpecs = require(ReplicatedStorage:WaitForChild("WeaponSpecs"))

local FleetHangarUI = {}

local ACCENT = Color3.fromRGB(120, 200, 255)
local BG = Color3.fromRGB(8, 12, 20)
local PANEL = Color3.fromRGB(16, 23, 36)
local CARD = Color3.fromRGB(24, 33, 50)
local CARD_HI = Color3.fromRGB(34, 52, 78)
local TEXT = Color3.fromRGB(232, 240, 250)
local SUBTEXT = Color3.fromRGB(132, 152, 178)
local GOOD = Color3.fromRGB(120, 240, 160)
local BAD = Color3.fromRGB(255, 120, 120)

local NODE_W, NODE_H = 150, 76
local COL_X = { 8, 190, 372, 554 }
local ROWS_3 = { 30, 126, 222 }
local ROWS_2 = { 78, 174 }
local CANVAS = Vector2.new(712, 314)

-- readable names for the stat keys the hull bonuses are written in
local STAT_NAMES = {
	Health = "hull",
	SublightSpeed = "speed",
	AlignTurnRate = "agility",
	AlignSpeed = "align",
	WarpMaxSpeed = "warp",
	WarpAccelK = "warp accel",
	OrbitRange = "engage range",
	Damage = "damage",
	WeaponRange = "weapon range",
	Cooldown = "cycle",
}

local STAT_ROWS = {
	{ key = "Health", label = "HULL", fmt = "%.0f" },
	{ key = "SublightSpeed", label = "SPEED", fmt = "%.0f" },
	{ key = "AlignTurnRate", label = "AGILITY", fmt = "%.2f" },
	{ key = "WarpMaxSpeed", label = "WARP", fmt = "%.0f" },
	{ key = "OrbitRange", label = "ENGAGE", fmt = "%.0f" },
	{ key = "Damage", label = "DAMAGE", fmt = "%.0f" },
	{ key = "WeaponRange", label = "RANGE", fmt = "%.0f" },
	{ key = "Cooldown", label = "CYCLE", fmt = "%.1fs", lowerBetter = true },
}

local function new(className, props, parent)
	local inst = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function round(inst, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, inst)
	return inst
end

local function outline(inst, color, transparency)
	return new("UIStroke", { Color = color, Transparency = transparency or 0.5 }, inst)
end

local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.Gotham
	props.TextColor3 = props.TextColor3 or TEXT
	props.TextSize = props.TextSize or 14
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return new("TextLabel", props, parent)
end

function FleetHangarUI.create(screenGui, onDeploy)
	local ceilings = Fittings.statCeilings()

	local state = {
		loadout = {
			{ hull = "VexDart", modules = {} },
			{ hull = "KorrSting", modules = {} },
			{ hull = "AuranSpark", modules = {} },
		},
		activeSlot = 1,
		selectedHull = "VexDart",
		faction = "Vex", -- which faction's tree is on screen
		pickerSlot = nil,
		mode = "hull",
	}

	-- forward declarations: the tabs need these before they are defined
	local refreshAll
	local buildTree
	local nodeButtons, nodeBadges = {}, {}

	------------------------------------------------------------------
	-- Shell
	------------------------------------------------------------------

	local window = new("Frame", {
		Name = "Hangar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.9),
		BackgroundColor3 = BG,
		BackgroundTransparency = 0.02,
		Active = true, -- sink clicks so they never reach the world
		Visible = false,
	}, screenGui)
	new("UISizeConstraint", { MaxSize = Vector2.new(1120, 700) }, window)
	round(window, 14)
	outline(window, ACCENT, 0.55)

	label({
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.fromOffset(320, 54),
		Text = "FLEET HANGAR",
		Font = Enum.Font.GothamBold,
		TextColor3 = ACCENT,
		TextSize = 21,
	}, window)

	label({
		Position = UDim2.fromOffset(210, 0),
		Size = UDim2.fromOffset(420, 54),
		Text = "one line per faction \u{00B7} pick a tab, pick a hull, fit it",
		TextSize = 12,
		TextColor3 = Color3.fromRGB(90, 108, 132),
	}, window)

	local closeButton = new("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(32, 30),
		BackgroundColor3 = CARD,
		Text = "\u{2715}",
		TextColor3 = SUBTEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		AutoButtonColor = false,
	}, window)
	round(closeButton, 8)

	local body = new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -166),
		BackgroundTransparency = 1,
	}, window)

	------------------------------------------------------------------
	-- Tree
	------------------------------------------------------------------

	local treePanel = new("Frame", {
		Name = "TreePanel",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -388, 1, 0),
		BackgroundColor3 = PANEL,
	}, body)
	round(treePanel, 10)

	-- faction tabs across the top of the tree panel
	local tabStrip = new("Frame", {
		Name = "FactionTabs",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 34),
		BackgroundTransparency = 1,
	}, treePanel)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabStrip)

	local factionTabs = {}
	for order, factionId in ShipClasses.FactionOrder do
		local faction = ShipClasses.Factions[factionId]
		local tab = new("TextButton", {
			Name = "FactionTab_" .. factionId,
			LayoutOrder = order, -- otherwise the list sorts the tabs by name
			Size = UDim2.fromOffset(206, 34),
			BackgroundColor3 = CARD,
			Text = "",
			AutoButtonColor = false,
		}, tabStrip)
		round(tab, 8)
		local tabStroke = outline(tab, faction.Color, 0.75)
		new("Frame", {
			Position = UDim2.fromOffset(12, 13),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = faction.Color,
			BorderSizePixel = 0,
		}, tab)
		local tabLabel = label({
			Position = UDim2.fromOffset(28, 0),
			Size = UDim2.new(1, -36, 1, 0),
			Text = faction.Name:upper() .. "  \u{00B7}  " .. WeaponSpecs[faction.Weapon].Name,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = SUBTEXT,
		}, tab)
		tab.Activated:Connect(function()
			if state.faction == factionId then return end
			state.faction = factionId
			-- show this faction's entry hull, so the panel follows the tab
			state.selectedHull = ShipClasses.Trees[factionId][1][1]
			state.mode = "hull"
			buildTree(factionId)
			refreshAll()
		end)
		factionTabs[factionId] = { button = tab, stroke = tabStroke, textLabel = tabLabel }
	end

	local treeScroll = new("ScrollingFrame", {
		Name = "TreeCanvas",
		Position = UDim2.fromOffset(10, 48),
		Size = UDim2.new(1, -20, 1, -56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(CANVAS.X, CANVAS.Y),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = ACCENT,
	}, treePanel)

	-- The tree is rebuilt whenever the faction tab changes: only one line is on
	-- screen at a time, so nodes are created fresh rather than hidden.
	buildTree = function(factionId)
		for _, child in treeScroll:GetChildren() do
			child:Destroy()
		end
		table.clear(nodeButtons)
		table.clear(nodeBadges)

		local tree = ShipClasses.Trees[factionId]
		local color = ShipClasses.Factions[factionId].Color
		local nodePos = {}
		for tier, ids in tree do
			local rows = if #ids == 3 then ROWS_3 else ROWS_2
			for i, hullId in ids do
				nodePos[hullId] = Vector2.new(COL_X[tier], rows[i])
			end
			label({
				Position = UDim2.fromOffset(COL_X[tier], 4),
				Size = UDim2.fromOffset(NODE_W, 18),
				Text = ShipClasses.TierNames[tier]:upper(),
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = Color3.fromRGB(90, 108, 132),
			}, treeScroll)
		end

		-- connectors first so nodes draw over them
		local function segment(x, y, w, h)
			new("Frame", {
				Position = UDim2.fromOffset(math.floor(x), math.floor(y)),
				Size = UDim2.fromOffset(math.max(w, 2), math.max(h, 2)),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
				ZIndex = 1,
			}, treeScroll)
		end
		for _, hullId in ShipClasses.hullsOf(factionId) do
			for _, parentId in ShipClasses.Hulls[hullId].Requires do
				local a, b = nodePos[parentId], nodePos[hullId]
				if a and b then
					local x1, y1 = a.X + NODE_W, a.Y + NODE_H / 2
					local x2, y2 = b.X, b.Y + NODE_H / 2
					local midX = (x1 + x2) / 2
					segment(x1, y1 - 1, midX - x1, 2)
					segment(midX - 1, math.min(y1, y2), 2, math.abs(y2 - y1))
					segment(midX, y2 - 1, x2 - midX, 2)
				end
			end
		end

		for _, hullId in ShipClasses.hullsOf(factionId) do
			local hull = ShipClasses.Hulls[hullId]
			local pos = nodePos[hullId]

			local node = new("TextButton", {
				Name = "Node_" .. hullId,
				Position = UDim2.fromOffset(pos.X, pos.Y),
				Size = UDim2.fromOffset(NODE_W, NODE_H),
				BackgroundColor3 = CARD,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 2,
			}, treeScroll)
			round(node, 9)
			local nodeStroke = outline(node, color, 0.6)

			new("Frame", {
				Size = UDim2.fromOffset(4, NODE_H - 20),
				Position = UDim2.fromOffset(0, 10),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, node)
			label({
				Position = UDim2.fromOffset(14, 8),
				Size = UDim2.fromOffset(NODE_W - 20, 20),
				Text = hull.Name,
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				ZIndex = 3,
			}, node)
			-- inside a faction tab the role is what tells the hulls apart
			label({
				Position = UDim2.fromOffset(14, 28),
				Size = UDim2.fromOffset(NODE_W - 20, 16),
				Text = hull.Role:upper(),
				Font = Enum.Font.GothamBold,
				TextSize = 10,
				TextColor3 = color,
				ZIndex = 3,
			}, node)
			label({
				Position = UDim2.fromOffset(14, 48),
				Size = UDim2.fromOffset(NODE_W - 20, 18),
				Text = string.format("%d slots  \u{00B7}  %d hull",
					hull.Slots, hull.Stats.Health),
				TextSize = 10,
				TextColor3 = SUBTEXT,
				ZIndex = 3,
			}, node)

			local badge = label({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 8),
				Size = UDim2.fromOffset(46, 16),
				Text = "",
				Font = Enum.Font.GothamBold,
				TextSize = 10,
				TextColor3 = GOOD,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 3,
			}, node)

			node.Activated:Connect(function()
				state.selectedHull = hullId
				state.mode = "hull"
				refreshAll()
			end)

			nodeButtons[hullId] = { button = node, stroke = nodeStroke }
			nodeBadges[hullId] = badge
		end
	end

	------------------------------------------------------------------
	-- Right panel
	------------------------------------------------------------------

	local side = new("Frame", {
		Name = "SidePanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.new(0, 360, 1, 0),
		BackgroundColor3 = PANEL,
	}, body)
	round(side, 10)

	local tabBar = new("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 32),
		BackgroundTransparency = 1,
	}, side)

	local function makeTab(text, x)
		local tab = new("TextButton", {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(160, 32),
			BackgroundColor3 = CARD,
			Text = text,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = SUBTEXT,
			AutoButtonColor = false,
		}, tabBar)
		round(tab, 7)
		return tab
	end
	local hullTab = makeTab("HULL", 0)
	hullTab.Name = "HullTab"
	local fitTab = makeTab("FITTING", 168)
	fitTab.Name = "FitTab"

	local function makePage()
		local page = new("ScrollingFrame", {
			Position = UDim2.fromOffset(10, 50),
			Size = UDim2.new(1, -20, 1, -60),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = ACCENT,
			Visible = false,
		}, side)
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		return page
	end
	local hullPage = makePage()
	local fitPage = makePage()
	hullPage.Name = "HullPage"
	fitPage.Name = "FitPage"

	-- one stat line: label, bar, value (and an optional "was" comparison)
	local function statRow(parent, order, row, value, baseValue, color)
		local holder = new("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		label({
			Size = UDim2.fromOffset(66, 26),
			Text = row.label,
			TextSize = 10,
			TextColor3 = SUBTEXT,
		}, holder)

		local track = new("Frame", {
			Position = UDim2.fromOffset(70, 9),
			Size = UDim2.new(1, -162, 0, 8),
			BackgroundColor3 = Color3.fromRGB(30, 40, 58),
			BorderSizePixel = 0,
		}, holder)
		round(track, 4)
		local ceiling = ceilings[row.key] or 1
		local fraction = math.clamp(value / ceiling, 0, 1)
		if row.lowerBetter then
			fraction = math.clamp(1 - value / ceiling, 0.04, 1)
		end
		round(new("Frame", {
			Size = UDim2.fromScale(fraction, 1),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, track), 4)

		local text = string.format(row.fmt, value)
		local valueColor = TEXT
		if baseValue and math.abs(value - baseValue) > 0.01 then
			local better = if row.lowerBetter then value < baseValue else value > baseValue
			valueColor = if better then GOOD else BAD
			text = string.format("%s %s", if better then "\u{25B2}" else "\u{25BC}", text)
		end
		label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.fromOffset(80, 26),
			Text = text,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = valueColor,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, holder)
	end

	local function clearPage(page)
		for _, child in page:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
	end

	------------------------------------------------------------------
	-- Bottom bar: fleet slots + deploy
	------------------------------------------------------------------

	local bottom = new("Frame", {
		Name = "FleetBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.new(1, -28, 0, 96),
		BackgroundColor3 = PANEL,
	}, window)
	round(bottom, 10)

	local slotCards = {}
	for i = 1, 3 do
		local card = new("TextButton", {
			Name = "SlotCard" .. i,
			Position = UDim2.fromOffset(12 + (i - 1) * 218, 12),
			Size = UDim2.fromOffset(208, 72),
			BackgroundColor3 = CARD,
			Text = "",
			AutoButtonColor = false,
		}, bottom)
		round(card, 9)
		local cardStroke = outline(card, ACCENT, 0.85)
		local stripe = new("Frame", {
			Size = UDim2.fromOffset(4, 52),
			Position = UDim2.fromOffset(0, 10),
			BorderSizePixel = 0,
		}, card)
		label({
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.fromOffset(80, 16),
			Text = "SLOT " .. i,
			TextSize = 10,
			TextColor3 = SUBTEXT,
		}, card)
		local nameLabel = label({
			Position = UDim2.fromOffset(14, 22),
			Size = UDim2.fromOffset(180, 22),
			Text = "-",
			Font = Enum.Font.GothamBold,
			TextSize = 16,
		}, card)
		local fitLabel = label({
			Position = UDim2.fromOffset(14, 46),
			Size = UDim2.fromOffset(180, 18),
			Text = "",
			TextSize = 11,
			TextColor3 = SUBTEXT,
		}, card)
		slotCards[i] = {
			button = card, stroke = cardStroke, stripe = stripe,
			nameLabel = nameLabel, fitLabel = fitLabel,
		}
	end

	local fleetSummary = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10),
		Size = UDim2.fromOffset(240, 34),
		Text = "",
		TextSize = 11,
		TextColor3 = SUBTEXT,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, bottom)

	local deployButton = new("TextButton", {
		Name = "DeployButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -12),
		Size = UDim2.fromOffset(240, 40),
		BackgroundColor3 = Color3.fromRGB(25, 95, 52),
		Text = "\u{1F680} DEPLOY FLEET",
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(160, 255, 190),
		AutoButtonColor = false,
	}, bottom)
	round(deployButton, 8)

	------------------------------------------------------------------
	-- Rendering
	------------------------------------------------------------------

	local function setHullForSlot(slotIndex, hullId)
		local entry = state.loadout[slotIndex]
		entry.hull = hullId
		local slots = ShipClasses.Hulls[hullId].Slots
		while #entry.modules > slots do
			table.remove(entry.modules)
		end
		state.activeSlot = slotIndex
		state.pickerSlot = nil
		refreshAll()
	end

	local function renderHullPage()
		clearPage(hullPage)
		local hullId = state.selectedHull
		local hull = ShipClasses.Hulls[hullId]
		local faction = ShipClasses.Factions[hull.Faction]
		local weapon = WeaponSpecs[hull.Weapon]
		local stats = Fittings.baseStats(hullId)
		local color = faction.Color

		label({
			Size = UDim2.new(1, 0, 0, 26),
			Text = hull.Name,
			Font = Enum.Font.GothamBold,
			TextSize = 22,
			LayoutOrder = 1,
		}, hullPage)
		label({
			Size = UDim2.new(1, 0, 0, 18),
			Text = string.format("%s %s  \u{00B7}  %s  \u{00B7}  %s %s",
				faction.Name, hull.Role, ShipClasses.TierNames[hull.Tier],
				weapon.Icon, weapon.Name),
			TextSize = 12,
			TextColor3 = color,
			LayoutOrder = 2,
		}, hullPage)
		label({
			Size = UDim2.new(1, 0, 0, 34),
			Text = hull.Blurb,
			TextSize = 12,
			TextColor3 = SUBTEXT,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 3,
		}, hullPage)

		for i, row in STAT_ROWS do
			statRow(hullPage, 10 + i, row, stats[row.key], nil, color)
		end

		local bonusText = {}
		for key, amount in hull.Bonuses do
			table.insert(bonusText, string.format("%+d%% %s",
				math.round(amount * 100), STAT_NAMES[key] or key))
		end
		label({
			Size = UDim2.new(1, 0, 0, 46),
			Text = if #bonusText > 0
				then "HULL BONUS  " .. table.concat(bonusText, "   ")
				else "HULL BONUS  none",
			TextSize = 11,
			TextColor3 = GOOD,
			TextWrapped = true,
			LayoutOrder = 30,
		}, hullPage)
		label({
			Size = UDim2.new(1, 0, 0, 20),
			Text = string.format("FITTING SLOTS  %d", hull.Slots),
			TextSize = 11,
			TextColor3 = ACCENT,
			LayoutOrder = 31,
		}, hullPage)

		-- kept high in the page so it stays reachable without scrolling
		local assignRow = new("Frame", {
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundTransparency = 1,
			LayoutOrder = 4,
		}, hullPage)
		for i = 1, 3 do
			local inUse = state.loadout[i].hull == hullId
			local assign = new("TextButton", {
				Name = "AssignSlot" .. i,
				Position = UDim2.fromOffset((i - 1) * 110, 0),
				Size = UDim2.fromOffset(104, 34),
				BackgroundColor3 = if inUse then CARD_HI else CARD,
				Text = if inUse then "IN SLOT " .. i else "TO SLOT " .. i,
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = if inUse then GOOD else TEXT,
				AutoButtonColor = false,
			}, assignRow)
			round(assign, 7)
			assign.Activated:Connect(function()
				setHullForSlot(i, hullId)
			end)
		end
	end

	local function renderFitPage()
		clearPage(fitPage)
		local slotIndex = state.activeSlot
		local entry = state.loadout[slotIndex]
		local hull = ShipClasses.Hulls[entry.hull]
		local color = ShipClasses.factionColor(entry.hull)
		local base = Fittings.baseStats(entry.hull)
		local fitted = Fittings.computeStats(entry.hull, entry.modules)

		label({
			Size = UDim2.new(1, 0, 0, 24),
			Text = string.format("SLOT %d  \u{00B7}  %s", slotIndex, hull.Name),
			Font = Enum.Font.GothamBold,
			TextSize = 17,
			LayoutOrder = 1,
		}, fitPage)
		label({
			Size = UDim2.new(1, 0, 0, 16),
			Text = string.format("%d of %d slots used", #entry.modules, hull.Slots),
			TextSize = 11,
			TextColor3 = SUBTEXT,
			LayoutOrder = 2,
		}, fitPage)

		local strip = new("Frame", {
			Name = "SlotStrip",
			Size = UDim2.new(1, 0, 0, 46),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
		}, fitPage)
		for i = 1, hull.Slots do
			local moduleId = entry.modules[i]
			local fitting = moduleId and Fittings.Modules[moduleId]
			local selected = state.pickerSlot == i
			local slotButton = new("TextButton", {
				Name = "FitSlot" .. i,
				Position = UDim2.fromOffset((i - 1) * 60, 0),
				Size = UDim2.fromOffset(54, 44),
				BackgroundColor3 = if fitting then CARD_HI else CARD,
				Text = if fitting then fitting.Icon else "+",
				Font = Enum.Font.GothamBold,
				TextSize = if fitting then 20 else 18,
				TextColor3 = if fitting then TEXT else Color3.fromRGB(80, 96, 118),
				AutoButtonColor = false,
			}, strip)
			round(slotButton, 8)
			if selected then
				outline(slotButton, ACCENT, 0)
			end
			slotButton.Activated:Connect(function()
				if entry.modules[i] then
					table.remove(entry.modules, i) -- clicking a fitted module strips it
					state.pickerSlot = nil
				else
					state.pickerSlot = if state.pickerSlot == i then nil else i
				end
				refreshAll()
			end)
		end

		label({
			Size = UDim2.new(1, 0, 0, 16),
			Text = if #entry.modules >= hull.Slots
				then "All slots full \u{00B7} click a fitted module to strip it"
				else "Pick a module below to fit it",
			TextSize = 10,
			TextColor3 = SUBTEXT,
			LayoutOrder = 4,
		}, fitPage)

		for order, moduleId in Fittings.Order do
			local fitting = Fittings.Modules[moduleId]
			local full = #entry.modules >= hull.Slots
			local row = new("TextButton", {
				Name = "Module_" .. moduleId,
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = CARD,
				BackgroundTransparency = if full then 0.55 else 0,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = 10 + order,
			}, fitPage)
			round(row, 8)
			label({
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.fromOffset(30, 40),
				Text = fitting.Icon,
				TextSize = 18,
			}, row)
			label({
				Position = UDim2.fromOffset(44, 3),
				Size = UDim2.new(1, -54, 0, 18),
				Text = fitting.Name,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
			}, row)
			label({
				Position = UDim2.fromOffset(44, 20),
				Size = UDim2.new(1, -54, 0, 16),
				Text = fitting.Desc,
				TextSize = 11,
				TextColor3 = SUBTEXT,
			}, row)
			row.Activated:Connect(function()
				if #entry.modules >= hull.Slots then return end
				local target = state.pickerSlot
				if target and target <= #entry.modules then
					table.insert(entry.modules, target, moduleId)
				else
					table.insert(entry.modules, moduleId)
				end
				state.pickerSlot = nil
				refreshAll()
			end)
		end

		label({
			Size = UDim2.new(1, 0, 0, 22),
			Text = "FITTED PERFORMANCE",
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = ACCENT,
			LayoutOrder = 40,
		}, fitPage)
		for i, row in STAT_ROWS do
			statRow(fitPage, 40 + i, row, fitted[row.key], base[row.key], color)
		end
	end

	local function renderSlots()
		for i, card in slotCards do
			local entry = state.loadout[i]
			local hull = ShipClasses.Hulls[entry.hull]
			local active = state.activeSlot == i and state.mode == "fit"
			card.button.BackgroundColor3 = if active then CARD_HI else CARD
			card.stroke.Transparency = if active then 0 else 0.85
			card.stripe.BackgroundColor3 = ShipClasses.factionColor(entry.hull)
			card.nameLabel.Text = hull.Name
			card.fitLabel.Text = string.format("%s  \u{00B7}  %d/%d fitted",
				ShipClasses.Factions[hull.Faction].Name, #entry.modules, hull.Slots)
		end

		-- fleet-wide figures: always the slowest ship in the fleet
		local fleet = {}
		for _, entry in state.loadout do
			local stats = Fittings.computeStats(entry.hull, entry.modules)
			for _, key in Fittings.MoveKeys do
				fleet[key] = if fleet[key] then math.min(fleet[key], stats[key]) else stats[key]
			end
		end
		fleetSummary.Text = string.format(
			"FLEET PACE (slowest ship)\nwarp %.0f  \u{00B7}  cruise %.0f  \u{00B7}  agility %.2f",
			fleet.WarpMaxSpeed, fleet.SublightSpeed, fleet.AlignTurnRate)
	end

	local function renderTree()
		local usage = {}
		for i, entry in state.loadout do
			usage[entry.hull] = (usage[entry.hull] or "") .. tostring(i)
		end
		for hullId, node in nodeButtons do
			local selected = state.selectedHull == hullId
			local used = usage[hullId]
			node.button.BackgroundColor3 = if selected then CARD_HI else CARD
			node.stroke.Transparency = if selected then 0 elseif used then 0.35 else 0.75
			nodeBadges[hullId].Text = if used then "\u{25CF} " .. used else ""
		end

		-- tabs: highlight the open faction, and mark the ones the fleet uses
		for factionId, tab in factionTabs do
			local active = state.faction == factionId
			local inFleet = false
			for _, entry in state.loadout do
				if ShipClasses.Hulls[entry.hull].Faction == factionId then
					inFleet = true
				end
			end
			tab.button.BackgroundColor3 = if active then CARD_HI else CARD
			tab.stroke.Transparency = if active then 0 elseif inFleet then 0.4 else 0.8
			tab.textLabel.TextColor3 = if active then TEXT else SUBTEXT
		end
	end

	function refreshAll()
		hullTab.BackgroundColor3 = if state.mode == "hull" then CARD_HI else CARD
		hullTab.TextColor3 = if state.mode == "hull" then TEXT else SUBTEXT
		fitTab.BackgroundColor3 = if state.mode == "fit" then CARD_HI else CARD
		fitTab.TextColor3 = if state.mode == "fit" then TEXT else SUBTEXT
		hullPage.Visible = state.mode == "hull"
		fitPage.Visible = state.mode == "fit"
		if state.mode == "hull" then
			renderHullPage()
		else
			renderFitPage()
		end
		renderTree()
		renderSlots()
	end

	------------------------------------------------------------------
	-- Wiring
	------------------------------------------------------------------

	for i, card in slotCards do
		card.button.Activated:Connect(function()
			state.activeSlot = i
			state.mode = "fit"
			state.pickerSlot = nil
			local hullId = state.loadout[i].hull
			state.selectedHull = hullId
			-- follow the slot to its own faction's tab
			local factionId = ShipClasses.Hulls[hullId].Faction
			if factionId ~= state.faction then
				state.faction = factionId
				buildTree(factionId)
			end
			refreshAll()
		end)
	end

	hullTab.Activated:Connect(function()
		state.mode = "hull"
		refreshAll()
	end)
	fitTab.Activated:Connect(function()
		state.mode = "fit"
		refreshAll()
	end)

	local api = {}
	local visibilityCallback = nil

	function api.isOpen()
		return window.Visible
	end
	-- let the caller hide its own HUD while the hangar covers the screen
	function api.onVisibilityChanged(callback)
		visibilityCallback = callback
		callback(window.Visible)
	end
	function api.open()
		window.Visible = true
		refreshAll()
		if visibilityCallback then
			visibilityCallback(true)
		end
	end
	function api.close()
		window.Visible = false
		if visibilityCallback then
			visibilityCallback(false)
		end
	end
	function api.toggle()
		if window.Visible then
			api.close()
		else
			api.open()
		end
	end

	closeButton.Activated:Connect(function()
		api.close()
	end)
	deployButton.Activated:Connect(function()
		local payload = {}
		for i, entry in state.loadout do
			payload[i] = { hull = entry.hull, modules = table.clone(entry.modules) }
		end
		onDeploy(payload)
		api.close()
	end)

	buildTree(state.faction)
	refreshAll()
	return api
end

return FleetHangarUI