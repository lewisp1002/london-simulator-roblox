-- Street furniture and road markings for the test town: lamp posts, trees, red phone and post boxes,
-- bus stops, bollards, railings, traffic lights, zebra crossings and speed cameras.
-- Each function puts one thing in the world. `cframe` arguments face the way the thing faces.

local TownKit = require(script.Parent.TownKit)

local C = TownKit.Colours
local PAVEMENT_TOP = TownKit.PAVEMENT_TOP
local box, detail, post, paint = TownKit.box, TownKit.detail, TownKit.post, TownKit.paint

local TownProps = {}

-- `at` is a point on the pavement
local function onPavement(at: Vector3): Vector3
	return Vector3.new(at.X, PAVEMENT_TOP, at.Z)
end

-- A grey London street lamp leaning its head out over the road. `towardRoad` points at the road.
function TownProps.lampPost(at: Vector3, towardRoad: Vector3)
	local base = onPavement(at)
	post(0.5, 15, base, C.LampGrey, Enum.Material.Metal)
	local frame = TownKit.facing(base + Vector3.new(0, 15, 0), towardRoad)
	local head = detail(Vector3.new(1, 0.45, 4.2), frame * CFrame.new(0, 0, -1.9), C.LampGrey, Enum.Material.Metal)
	TownKit.tag(head, "StreetLight")
end

function TownProps.tree(at: Vector3, scale: number?)
	local s = scale or 1
	local base = Vector3.new(at.X, at.Y, at.Z)
	post(1.2 * s, 9 * s, base, C.TreeTrunk, Enum.Material.Wood)
	local leaves = C.Leaves
	box(Vector3.new(10, 9, 10) * s, CFrame.new(base + Vector3.new(0, 12 * s, 0)), leaves, Enum.Material.Grass, "Part").Shape = Enum.PartType.Ball
	local top = box(Vector3.new(7, 7, 7) * s, CFrame.new(base + Vector3.new(1.5 * s, 16 * s, -1 * s)), leaves:Lerp(Color3.new(0.3, 0.5, 0.2), 0.15), Enum.Material.Grass)
	top.Shape = Enum.PartType.Ball
end

-- A tall conifer, for the woods round the edge of the map
function TownProps.pine(at: Vector3, scale: number)
	post(1.4 * scale, 8 * scale, at, C.TreeTrunk, Enum.Material.Wood)
	for i = 0, 2 do
		local width = (11 - i * 3) * scale
		local cone = box(Vector3.new(width, 9 * scale, width), CFrame.new(at + Vector3.new(0, (9 + i * 6.5) * scale, 0)), Color3.fromRGB(40, 75, 45), Enum.Material.Grass)
		cone.Shape = Enum.PartType.Ball
	end
end

function TownProps.bin(at: Vector3)
	local base = onPavement(at)
	post(1.6, 3.2, base, C.StreetBlack, Enum.Material.Metal)
	detail(Vector3.new(1.8, 0.3, 1.8), CFrame.new(base + Vector3.new(0, 3.3, 0)), C.Gold, Enum.Material.Metal)
end

function TownProps.bollard(at: Vector3)
	local base = onPavement(at)
	post(0.8, 3, base, C.StreetBlack, Enum.Material.Metal)
	post(0.86, 0.35, base + Vector3.new(0, 2.2, 0), C.White)
end

-- The classic red telephone box
function TownProps.phoneBox(at: Vector3, facing: Vector3)
	local frame = TownKit.facing(onPavement(at), facing)
	box(Vector3.new(3.4, 8, 3.4), frame * CFrame.new(0, 4, 0), C.PostOfficeRed)
	box(Vector3.new(3.8, 0.8, 3.8), frame * CFrame.new(0, 8.4, 0), C.PostOfficeRed)
	local panel = detail(Vector3.new(2.6, 4.6, 0.1), frame * CFrame.new(0, 4.3, -1.75), Color3.fromRGB(40, 50, 55), Enum.Material.Glass)
	panel.Transparency = 0.3
	local sign = detail(Vector3.new(2.8, 0.6, 0.1), frame * CFrame.new(0, 7.3, -1.76), C.StreetBlack)
	TownKit.text(sign, Enum.NormalId.Front, "TELEPHONE", C.White)
end

-- A red pillar box for posting letters
function TownProps.postBox(at: Vector3, facing: Vector3)
	local frame = TownKit.facing(onPavement(at), facing)
	local body = box(Vector3.new(4.6, 1.9, 1.9), frame * CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.pi / 2), C.PostOfficeRed)
	body.Shape = Enum.PartType.Cylinder
	box(Vector3.new(2.1, 0.5, 2.1), frame * CFrame.new(0, 4.8, 0), C.StreetBlack)
	detail(Vector3.new(1, 0.15, 0.1), frame * CFrame.new(0, 3.6, -0.96), C.StreetBlack)
end

function TownProps.bench(at: Vector3, facing: Vector3)
	local frame = TownKit.facing(onPavement(at), facing)
	box(Vector3.new(5, 0.3, 1.6), frame * CFrame.new(0, 1.6, 0), C.TreeTrunk, Enum.Material.Wood)
	detail(Vector3.new(5, 1.2, 0.25), frame * CFrame.new(0, 2.4, 0.75), C.TreeTrunk, Enum.Material.Wood)
	for _, x in { -2.1, 2.1 } do
		detail(Vector3.new(0.25, 1.5, 1.4), frame * CFrame.new(x, 0.75, 0), C.StreetBlack, Enum.Material.Metal)
	end
end

-- Black railings along `length` studs, starting at `from` and going in `direction`
function TownProps.railing(from: Vector3, direction: Vector3, length: number, colour: Color3?)
	local frame = TownKit.facing(onPavement(from), direction)
	local paintColour = colour or C.StreetBlack
	for _, height in { 1.2, 3.2 } do
		detail(Vector3.new(0.2, 0.2, length), frame * CFrame.new(0, height, -length / 2), paintColour, Enum.Material.Metal)
	end
	local posts = math.max(2, math.floor(length / 4))
	for i = 0, posts do
		local z = -length * i / posts
		box(Vector3.new(0.25, 3.4, 0.25), frame * CFrame.new(0, 1.7, z), paintColour, Enum.Material.Metal)
	end
end

-- A bus shelter, the red stop sign on its pole, and the yellow "BUS STOP" box painted on the road.
-- `frame` sits on the kerb edge facing the road.
function TownProps.busStop(frame: CFrame)
	local shelter = frame * CFrame.new(0, PAVEMENT_TOP, 5)
	local glassColour = Color3.fromRGB(150, 175, 185)
	local back = detail(Vector3.new(12, 6.5, 0.15), shelter * CFrame.new(0, 3.5, 2), glassColour, Enum.Material.Glass)
	back.Transparency = 0.55
	back.CanCollide = true
	for _, x in { -6, 6 } do
		box(Vector3.new(0.3, 7.5, 0.3), shelter * CFrame.new(x, 3.75, 2), C.StreetBlack, Enum.Material.Metal)
		box(Vector3.new(0.3, 7.5, 0.3), shelter * CFrame.new(x, 3.75, -1), C.StreetBlack, Enum.Material.Metal)
	end
	detail(Vector3.new(12.6, 0.3, 4), shelter * CFrame.new(0, 7.6, 0.5), C.StreetBlack, Enum.Material.Metal)
	box(Vector3.new(8, 0.3, 1.2), shelter * CFrame.new(0, 1.8, 1.4), C.StreetBlack, Enum.Material.Metal)

	local pole = frame * CFrame.new(9, PAVEMENT_TOP, 1.2)
	box(Vector3.new(0.35, 10, 0.35), pole * CFrame.new(0, 5, 0), C.LampGrey, Enum.Material.Metal)
	local flag = detail(Vector3.new(2.6, 2.6, 0.15), pole * CFrame.new(0, 9, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(210, 30, 35))
	TownKit.text(flag, Enum.NormalId.Front, "BUS STOP", C.White)
	TownKit.text(flag, Enum.NormalId.Back, "BUS STOP", C.White)

	-- Road markings: a yellow box with "BUS STOP" written in it
	local road = frame * CFrame.new(0, 0, -5)
	local level = CFrame.new(0, TownKit.ROAD_TOP + 0.02 - road.Position.Y, 0)
	for _, z in { -4, 4 } do
		local line = paint(40, 0.4, Vector3.zero, C.Yellow)
		line.CFrame = road * level * CFrame.new(0, 0, z)
	end
	-- Turned so the words read the right way up for traffic in the near lane (we drive on the left)
	local words = paint(8, 3, Vector3.zero, C.Yellow)
	words.CFrame = road * level * CFrame.Angles(0, math.pi / 2, 0)
	words.Transparency = 1
	local label = TownKit.text(words, Enum.NormalId.Top, "BUS STOP", C.Yellow)
	label.TextTransparency = 0.05
end

-- Traffic light head on a pole. `frame` sits on the pavement facing the drivers it controls.
-- The TrafficLights script finds the lamps by their names (Red, Amber, Green) and the tag.
function TownProps.trafficLight(frame: CFrame, junctionId: string, axis: string)
	local base = frame * CFrame.new(0, PAVEMENT_TOP, 0)
	box(Vector3.new(0.5, 11, 0.5), base * CFrame.new(0, 5.5, 0), C.LampGrey, Enum.Material.Metal)

	local head = Instance.new("Model")
	head.Name = "TrafficLight"
	head:SetAttribute("Junction", junctionId)
	head:SetAttribute("Axis", axis)
	TownKit.tag(head, "TrafficLight")

	local housing = detail(Vector3.new(1.5, 4.2, 1.1), base * CFrame.new(0, 10, -0.5), C.StreetBlack, Enum.Material.Metal)
	housing.Parent = head
	local backboard = detail(Vector3.new(2.3, 5, 0.12), base * CFrame.new(0, 10, 0.06), C.StreetBlack)
	backboard.Parent = head
	for i, name in { "Red", "Amber", "Green" } do
		local lamp = detail(Vector3.new(0.25, 1, 1), base * CFrame.new(0, 11.35 - (i - 1) * 1.35, -1.08) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(40, 40, 40), Enum.Material.SmoothPlastic)
		lamp.Shape = Enum.PartType.Cylinder
		lamp.Name = name
		lamp.Parent = head
	end
	head.Parent = TownKit.getParent()
end

-- Black-and-white striped pole with a flashing amber globe, one each side of a zebra crossing
function TownProps.belisha(at: Vector3)
	local base = onPavement(at)
	for i = 0, 5 do
		local stripe = box(Vector3.new(1.4, 0.4, 0.4), CFrame.new(base + Vector3.new(0, 0.7 + i * 1.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), if i % 2 == 0 then C.StreetBlack else C.White, Enum.Material.SmoothPlastic)
		stripe.Shape = Enum.PartType.Cylinder
	end
	local globe = detail(Vector3.new(1.4, 1.4, 1.4), CFrame.new(base + Vector3.new(0, 9.1, 0)), Color3.fromRGB(255, 160, 20), Enum.Material.Neon)
	globe.Shape = Enum.PartType.Ball
	TownKit.tag(globe, "BelishaGlobe")
end

-- White stripes across the road with zig-zags either side. `frame` is the middle of the road,
-- facing along it; `width` is how wide the road is.
function TownProps.zebra(frame: CFrame, width: number)
	local level = CFrame.new(0, TownKit.ROAD_TOP + 0.02 - frame.Position.Y, 0)
	local stripes = math.floor(width / 2.4)
	for i = 0, stripes - 1 do
		local x = -width / 2 + 1.2 + i * 2.4
		local stripe = paint(1.2, 8, Vector3.zero)
		stripe.CFrame = frame * level * CFrame.new(x, 0, 0)
	end
	-- Zig-zag lines along both kerbs, both sides of the crossing
	for _, side in { -1, 1 } do
		for _, direction in { -1, 1 } do
			for i = 0, 7 do
				local z = direction * (6 + i * 2.6)
				local zig = paint(0.35, 2.9, Vector3.zero)
				zig.CFrame = frame * level * CFrame.new(side * (width / 2 - 1.6), 0, z) * CFrame.Angles(0, if i % 2 == 0 then 0.35 else -0.35, 0)
			end
		end
	end
end

-- The double dashed "give way" line across the lane that's coming up to a junction.
-- `frame` is on the junction edge in the middle of that lane, facing the junction.
function TownProps.giveWay(frame: CFrame, laneWidth: number)
	local level = CFrame.new(0, TownKit.ROAD_TOP + 0.02 - frame.Position.Y, 0)
	local dashes = math.floor(laneWidth / 2.6)
	for row = 0, 1 do
		for i = 0, dashes - 1 do
			local x = -laneWidth / 2 + 1.3 + i * 2.6
			local dash = paint(1.6, 0.5, Vector3.zero)
			dash.CFrame = frame * level * CFrame.new(x, 0, 1.4 + row * 1.2)
		end
	end
end

-- A solid stop line and a straight-on arrow before a set of traffic lights
function TownProps.stopLine(frame: CFrame, laneWidth: number)
	local level = CFrame.new(0, TownKit.ROAD_TOP + 0.02 - frame.Position.Y, 0)
	local line = paint(laneWidth - 1, 0.7, Vector3.zero)
	line.CFrame = frame * level * CFrame.new(0, 0, 1.8)
	local shaft = paint(0.6, 7, Vector3.zero)
	shaft.CFrame = frame * level * CFrame.new(0, 0, 12)
	local head = TownKit.detail(Vector3.new(2.4, 0.05, 2.4), frame * level * CFrame.new(0, 0, 7.4) * CFrame.Angles(0, math.pi / 4, 0), C.White)
	head.CastShadow = false
end

-- A yellow speed camera on a grey pole, pointing back along the road at oncoming cars
function TownProps.speedCamera(frame: CFrame, limit: number)
	local base = frame * CFrame.new(0, PAVEMENT_TOP, 0)
	box(Vector3.new(0.6, 10, 0.6), base * CFrame.new(0, 5, 0), C.LampGrey, Enum.Material.Metal)
	local camera = box(Vector3.new(1.8, 2.2, 3.2), base * CFrame.new(0, 10.4, 0), Color3.fromRGB(245, 205, 30))
	camera:SetAttribute("SpeedLimit", limit)
	TownKit.tag(camera, "SpeedCamera")
	detail(Vector3.new(1.2, 1.2, 0.1), base * CFrame.new(0, 10.4, -1.62), C.StreetBlack, Enum.Material.Glass)
end

-- A round speed limit sign on a pole
function TownProps.limitSign(at: Vector3, facing: Vector3, limit: number)
	local frame = TownKit.facing(onPavement(at), facing)
	box(Vector3.new(0.3, 8, 0.3), frame * CFrame.new(0, 4, 0), C.LampGrey, Enum.Material.Metal)
	local disc = detail(Vector3.new(0.15, 2.6, 2.6), frame * CFrame.new(0, 8.6, -0.2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(210, 30, 30))
	disc.Shape = Enum.PartType.Cylinder
	local face = detail(Vector3.new(1.9, 1.9, 0.05), frame * CFrame.new(0, 8.6, -0.3), C.White)
	TownKit.text(face, Enum.NormalId.Front, tostring(limit), Color3.new(0, 0, 0))
end

return TownProps
