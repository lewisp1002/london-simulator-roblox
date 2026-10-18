-- People walking on the pavements, like the pedestrians in Birmingham Vehicle Simulator.
-- This part runs on the server: it makes a set of different people (skin, clothes, hair, height) and puts
-- them in ReplicatedStorage → PedestrianModels. Each player's device then walks copies of them along the
-- pavements near that player (see the Pedestrians client script), so they cost the server nothing.
-- The pavements they walk along are in MapInfo → Pavements, written by LondonMap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pedestrians = {}

local PEOPLE = 16

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SKIN = { rgb(255, 220, 190), rgb(234, 192, 160), rgb(198, 150, 112), rgb(160, 110, 80), rgb(110, 72, 50), rgb(80, 52, 38), rgb(245, 205, 175) }
local TOPS = {
	rgb(30, 30, 34), rgb(40, 60, 110), rgb(150, 30, 35), rgb(225, 225, 220), rgb(90, 100, 90), rgb(120, 90, 60),
	rgb(60, 110, 150), rgb(200, 160, 60), rgb(70, 40, 80), rgb(160, 160, 165), rgb(20, 80, 60), rgb(220, 120, 140),
}
local TROUSERS = { rgb(30, 40, 70), rgb(25, 25, 28), rgb(60, 70, 90), rgb(110, 100, 80), rgb(80, 80, 85), rgb(45, 55, 100) }
local HAIR = { rgb(30, 22, 16), rgb(70, 45, 25), rgb(120, 80, 40), rgb(200, 170, 110), rgb(20, 20, 20), rgb(150, 150, 150) }

local function choose<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

local function makePerson(index: number, random: Random): Model?
	local description = Instance.new("HumanoidDescription")
	local skin = choose(SKIN, random)
	local top = choose(TOPS, random)
	local longSleeves = random:NextNumber() < 0.6
	description.HeadColor = skin
	description.TorsoColor = top
	description.LeftArmColor = if longSleeves then top else skin
	description.RightArmColor = if longSleeves then top else skin
	description.LeftLegColor = choose(TROUSERS, random)
	description.RightLegColor = description.LeftLegColor
	description.HeightScale = random:NextNumber(0.9, 1.05)
	description.WidthScale = random:NextNumber(0.85, 1)
	description.DepthScale = description.WidthScale
	description.BodyTypeScale = random:NextNumber(0, 0.3)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[Pedestrians] couldn't make a person: " .. tostring(result))
		return nil
	end
	local model = result :: Model
	model.Name = "Person" .. index
	-- Hair: a cap on top of the head, sometimes longer at the back
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local long = random:NextNumber() < 0.4
		local hair = Instance.new("Part")
		hair.Name = "Hair"
		hair.Size = Vector3.new(head.Size.X * 1.06, head.Size.Y * (if long then 0.85 else 0.42), head.Size.Z * 1.08)
		hair.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * (if long then 0.12 else 0.34), head.Size.Z * 0.06)
		hair.Color = choose(HAIR, random)
		hair.Material = Enum.Material.Fabric
		hair.TopSurface = Enum.SurfaceType.Smooth
		hair.BottomSurface = Enum.SurfaceType.Smooth
		hair.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = hair
		weld.Parent = hair
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Massless = true
		elseif item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.EvaluateStateMachine = false
		humanoid.BreakJointsOnDeath = false
	end
	return model
end

-- Makes the people (it takes a few seconds, so it runs in the background)
function Pedestrians.setup()
	task.spawn(function()
		local folder = Instance.new("Folder")
		folder.Name = "PedestrianModels"
		local random = Random.new(42)
		for i = 1, PEOPLE do
			local person = makePerson(i, random)
			if person then
				person.Parent = folder
			end
		end
		folder.Parent = ReplicatedStorage
	end)
end

return Pedestrians
