-- A bright British day with big white clouds, like Birmingham Vehicle Simulator: soft shadows, a light haze in the distance,
-- gentle colour grading.
-- The "Future" lighting technology can't be set from code, so the game file sets it (Lighting → Technology in Studio).

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LightingSetup = {}

-- Swaps out whatever the place already had (the Baseplate template adds some), so there's only one of each
local function freshEffect(className: string, parent: Instance): any
	for _, child in parent:GetChildren() do
		if child.ClassName == className then
			child:Destroy()
		end
	end
	local effect: any = Instance.new(className :: any)
	effect.Parent = parent
	return effect
end

function LightingSetup.apply()
	Lighting.ClockTime = 13.2
	Lighting.GeographicLatitude = 52.2 -- Cambridge, so the sun sits where it should
	Lighting.Brightness = 2.8
	Lighting.Ambient = Color3.fromRGB(42, 42, 46)
	Lighting.OutdoorAmbient = Color3.fromRGB(138, 140, 146)
	Lighting.EnvironmentDiffuseScale = 1 -- light bounces off the sky onto everything
	Lighting.EnvironmentSpecularScale = 1 -- shiny things (car paint, glass) reflect the sky
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.ExposureCompensation = 0.2

	-- Like Birmingham Vehicle Simulator's sky (from Lewis's screen, 18 Oct 2026): a clear blue sky with big white
	-- clouds, and a light blue-grey haze that softens the far fields and buildings rather than a grey fog
	local atmosphere = freshEffect("Atmosphere", Lighting) :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(199, 212, 228)
	atmosphere.Decay = Color3.fromRGB(104, 124, 152)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.15

	local bloom = freshEffect("BloomEffect", Lighting) :: BloomEffect
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.8

	local grading = freshEffect("ColorCorrectionEffect", Lighting) :: ColorCorrectionEffect
	grading.Brightness = 0.02
	grading.Contrast = 0.1
	grading.Saturation = -0.04
	grading.TintColor = Color3.fromRGB(255, 252, 248)

	local sunRays = freshEffect("SunRaysEffect", Lighting) :: SunRaysEffect
	sunRays.Intensity = 0.05
	sunRays.Spread = 0.8

	local clouds = freshEffect("Clouds", Workspace.Terrain) :: Clouds
	clouds.Cover = 0.62
	clouds.Density = 0.75
	clouds.Color = Color3.fromRGB(250, 250, 250)
end

return LightingSetup
