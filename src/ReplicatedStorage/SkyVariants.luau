--!nonstrict
-- SkyVariants: the hand-made galaxy skyboxes, plus the lighting that suits each.
--
-- IMPORTANT - these are IMAGE ids, not the decal ids from the Creator Dashboard.
-- Uploading a picture to Roblox produces a *Decal* asset that wraps the real
-- image, and Sky/ImageLabel need the image inside it: a decal id simply fails
-- to load with no error. The originals are kept below for reference; the image
-- ids were pulled out with InsertService:LoadAsset(decalId) and reading the
-- resulting Decal's .Texture. Do the same for any new face you upload.

local SkyVariants = {}

SkyVariants.Variants = {
	{
		Name = "Crimson", -- red and purple nebula with a bright core
		Faces = {
			SkyboxRt = "rbxassetid://74690848780150",  -- decal 128774982035395
			SkyboxUp = "rbxassetid://125934302436668", -- decal 76700307905059
			SkyboxLf = "rbxassetid://82327344179989",  -- decal 123941700223125
			SkyboxFt = "rbxassetid://137887389730525", -- decal 130016806394330
			SkyboxDn = "rbxassetid://75389126509283",  -- decal 105038005941652
			SkyboxBk = "rbxassetid://107439410546373", -- decal 73372813117002
		},
		-- the star this nebula is lit by
		LightColor = Color3.fromRGB(255, 196, 220),
		StarColor = Color3.fromRGB(255, 242, 235),
		CoronaColor = Color3.fromRGB(255, 150, 180),
		Ambient = Color3.fromRGB(48, 30, 46),
		AtmosphereColor = Color3.fromRGB(90, 40, 80),
		AtmosphereDecay = Color3.fromRGB(60, 20, 55),
	},
	{
		Name = "Ashen", -- grey nebula
		Faces = {
			SkyboxLf = "rbxassetid://92385327278608",  -- decal 71725929436117
			SkyboxDn = "rbxassetid://81997532444202",  -- decal 105640965630378
			SkyboxBk = "rbxassetid://103485293437200", -- decal 90534075626743
			SkyboxFt = "rbxassetid://107978174329662", -- decal 117000155411826
			SkyboxRt = "rbxassetid://84806341472535",  -- decal 120522807640879
			SkyboxUp = "rbxassetid://130719070726203", -- decal 72385067145688
		},
		LightColor = Color3.fromRGB(220, 230, 245),
		StarColor = Color3.fromRGB(245, 250, 255),
		CoronaColor = Color3.fromRGB(160, 200, 245),
		Ambient = Color3.fromRGB(38, 40, 46),
		AtmosphereColor = Color3.fromRGB(70, 74, 82),
		AtmosphereDecay = Color3.fromRGB(45, 48, 55),
	},
}

function SkyVariants.get(name: string)
	for _, variant in SkyVariants.Variants do
		if variant.Name == name then
			return variant
		end
	end
	return nil
end

-- Paint a variant onto Lighting: the six faces, the ambient tone, the
-- atmosphere tint, and the colour of the system's star.
--
-- There is no Roblox sun in this place. Its disc is hidden and the directional
-- light is aimed straight down (ClockTime 12) so it lines up with the star
-- hanging above the middle of the map, tinted to that star's colour. Roblox
-- caps PointLight range at 60 studs, so a real point source could never light
-- a map this size - the directional light standing in for it is the only way
-- to get map-wide illumination that appears to come from the star.
function SkyVariants.apply(variant)
	local Lighting = game:GetService("Lighting")
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	for property, assetId in variant.Faces do
		sky[property] = assetId
	end
	sky.StarCount = 0 -- the art has its own stars painted in
	sky.CelestialBodiesShown = false -- no sun or moon disc in deep space

	Lighting.ClockTime = 12 -- light straight down, from the star's direction
	Lighting.GeographicLatitude = 0
	Lighting.Brightness = 2.2
	Lighting.ColorShift_Top = variant.LightColor -- tints whatever the star lights
	Lighting.Ambient = variant.Ambient
	Lighting.OutdoorAmbient = variant.Ambient

	-- Atmosphere has to stay switched off in space. Its Decay property paints
	-- the sky BELOW the horizon, so any density at all buries the bottom half
	-- of the skybox behind a flat slab of colour - with a dark decay tint that
	-- reads as pitch black. The star's glow comes from BloomEffect instead.
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0
		atmosphere.Haze = 0
		atmosphere.Glare = 0
		atmosphere.Color = variant.AtmosphereColor
		atmosphere.Decay = variant.AtmosphereDecay
	end

	-- the star model itself: core colour and its local glow
	local starModel = workspace:FindFirstChild("SystemStar")
	if starModel then
		local core = starModel:FindFirstChild("Core")
		if core then
			core.Color = variant.StarColor or variant.LightColor
			local glow = core:FindFirstChild("SystemStar")
			if glow and glow:IsA("Light") then
				glow.Color = variant.LightColor
			end
		end
		local corona = starModel:FindFirstChild("Corona")
		if corona then
			corona.Color = variant.CoronaColor or variant.LightColor
		end
		local outer = starModel:FindFirstChild("OuterCorona")
		if outer then
			outer.Color = variant.CoronaColor or variant.LightColor
		end
	end

	return variant
end

function SkyVariants.applyRandom(seed: number?)
	local rng = if seed then Random.new(seed) else Random.new()
	local variant = SkyVariants.Variants[rng:NextInteger(1, #SkyVariants.Variants)]
	return SkyVariants.apply(variant)
end

return SkyVariants