-- A bright British day with fluffy clouds, like Birmingham Vehicle Simulator: soft shadows, haze in the distance, gentle colour grading.
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
	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 51.5 -- London, so the sun sits where it should
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(40, 40, 45)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 135)
	Lighting.EnvironmentDiffuseScale = 1 -- light bounces off the sky onto everything
	Lighting.EnvironmentSpecularScale = 1 -- shiny things (car paint, glass) reflect the sky
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.ExposureCompensation = 0.1

	local atmosphere = freshEffect("Atmosphere", Lighting) :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 199, 199)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2

	local bloom = freshEffect("BloomEffect", Lighting) :: BloomEffect
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.8

	local grading = freshEffect("ColorCorrectionEffect", Lighting) :: ColorCorrectionEffect
	grading.Brightness = 0.02
	grading.Contrast = 0.12
	grading.Saturation = 0.02
	grading.TintColor = Color3.fromRGB(255, 250, 245)

	local sunRays = freshEffect("SunRaysEffect", Lighting) :: SunRaysEffect
	sunRays.Intensity = 0.05
	sunRays.Spread = 0.8

	local clouds = freshEffect("Clouds", Workspace.Terrain) :: Clouds
	clouds.Cover = 0.55
	clouds.Density = 0.7
	clouds.Color = Color3.fromRGB(235, 235, 235)
end

return LightingSetup
