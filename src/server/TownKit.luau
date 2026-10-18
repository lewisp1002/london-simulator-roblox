-- Basic building blocks for the test town: anchored parts, road paint and signs with words on them.
-- TownProps, TownBuildings, RoadKit and LondonMap all use these, so the whole town shares one set of colours and heights.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local TownKit = {}

-- Heights, in studs. Roads sit just above the ground and pavements are one kerb higher. The kerb is the AHDEV
-- UK road pack's (a quarter of a stud: low, like real kerbs), so our roads match the pack Lewis bought.
TownKit.ROAD_TOP = 0.1
TownKit.KERB_HEIGHT = 0.25
TownKit.KERB_WIDTH = 0.75 -- the darker kerb stones between the road and the pavement
-- Roads, kerbs, pavements and their paint are all matte Concrete, like the pack: Roblox's Asphalt material
-- looks rough and plasticky up close
TownKit.ROAD_MATERIAL = Enum.Material.Concrete
TownKit.PAVEMENT_TOP = TownKit.ROAD_TOP + TownKit.KERB_HEIGHT
TownKit.FLOOR = 11 -- one storey of a building

TownKit.Colours = {
	-- The AHDEV road pack's colours: dark grey road, mid grey kerb stones, light grey pavement, bright paint
	Asphalt = Color3.fromRGB(84, 83, 80),
	White = Color3.fromRGB(248, 248, 248),
	Yellow = Color3.fromRGB(255, 255, 0),
	Pavement = Color3.fromRGB(163, 162, 165),
	RedPaving = Color3.fromRGB(176, 112, 100), -- block paving on the high streets
	Kerb = Color3.fromRGB(99, 95, 98),
	Grass = Color3.fromRGB(78, 128, 58),
	Hedge = Color3.fromRGB(45, 90, 40),
	PostOfficeRed = Color3.fromRGB(200, 16, 30),
	StreetBlack = Color3.fromRGB(28, 30, 32),
	LampGrey = Color3.fromRGB(110, 112, 116),
	Stone = Color3.fromRGB(205, 198, 182),
	Portland = Color3.fromRGB(226, 219, 201),
	Gothic = Color3.fromRGB(206, 186, 142),
	RedBrick = Color3.fromRGB(140, 70, 50),
	StockBrick = Color3.fromRGB(170, 150, 118),
	Stucco = Color3.fromRGB(236, 232, 222),
	Slate = Color3.fromRGB(70, 72, 78),
	Glass = Color3.fromRGB(70, 92, 108),
	Concrete = Color3.fromRGB(158, 158, 154),
	Water = Color3.fromRGB(60, 90, 100),
	Bronze = Color3.fromRGB(80, 62, 40),
	Gold = Color3.fromRGB(205, 165, 70),
	TreeTrunk = Color3.fromRGB(85, 65, 45),
	Leaves = Color3.fromRGB(62, 110, 48),
}

local folder: Instance? = nil

-- Everything made after this goes into `parent`
function TownKit.setParent(parent: Instance)
	folder = parent
end

function TownKit.getParent(): Instance?
	return folder
end

-- An anchored block. `cframe` is its centre.
function TownKit.box(size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material?, className: string?): Part
	-- Typed as a Part so callers can set Shape; WedgeParts made here just never use it
	local part = Instance.new((className or "Part") :: any) :: Part
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = colour
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanTouch = false
	part.Parent = folder
	return part
end

-- Roblox won't make a part bigger than 2048 studs, so big flat areas (grass, the riverbed) are cut into tiles.
-- `size` and `centre` are for the whole area; it can't be turned.
function TownKit.tiles(size: Vector3, centre: Vector3, colour: Color3, material: Enum.Material?): { Part }
	local MAX = 2000
	local countX, countZ = math.ceil(size.X / MAX), math.ceil(size.Z / MAX)
	local tileX, tileZ = size.X / countX, size.Z / countZ
	local made = {}
	for i = 0, countX - 1 do
		for j = 0, countZ - 1 do
			local x = centre.X - size.X / 2 + tileX * (i + 0.5)
			local z = centre.Z - size.Z / 2 + tileZ * (j + 0.5)
			table.insert(made, TownKit.box(Vector3.new(tileX, size.Y, tileZ), CFrame.new(x, centre.Y, z), colour, material))
		end
	end
	return made
end

-- A decoration that cars and players pass through and raycasts ignore (lamps' heads, signs, paint)
function TownKit.detail(size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material?, className: string?): Part
	local part = TownKit.box(size, cframe, colour, material, className)
	part.CanCollide = false
	part.CanQuery = false
	return part
end

-- Flat road paint at road level, turned `angle` radians around the vertical
function TownKit.paint(sizeX: number, sizeZ: number, position: Vector3, colour: Color3?, angle: number?): Part
	local cframe = CFrame.new(position.X, TownKit.ROAD_TOP + 0.02, position.Z) * CFrame.Angles(0, angle or 0, 0)
	local part = TownKit.detail(Vector3.new(sizeX, 0.05, sizeZ), cframe, colour or TownKit.Colours.White, Enum.Material.Concrete)
	part.CastShadow = false
	return part
end

-- A vertical cylinder standing on the ground at `base`
function TownKit.post(diameter: number, height: number, base: Vector3, colour: Color3, material: Enum.Material?): Part
	local part = TownKit.box(Vector3.new(height, diameter, diameter), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), colour, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Words printed on one face of a part
function TownKit.text(host: BasePart, face: Enum.NormalId, text: string, colour: Color3, background: Color3?, weight: Enum.FontWeight?): TextLabel
	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 30
	surface.LightInfluence = 0.8
	surface.MaxDistance = 220 -- don't bother drawing words nobody's close enough to read
	surface.Parent = host

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if background then 0 else 1
	label.BackgroundColor3 = background or Color3.new()
	label.BorderSizePixel = 0
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", weight or Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextColor3 = colour
	label.Text = text
	label.Parent = surface

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.Parent = label
	return label
end

function TownKit.tag(instance: Instance, tagName: string)
	CollectionService:AddTag(instance, tagName)
end

-- A copy of a prop from the bought packs (ServerStorage → PropKit, made by tools/prepare_prop_kit.luau),
-- standing at `cframe` with its front facing the way `cframe` faces. nil if the kit doesn't have it.
function TownKit.prop(name: string, cframe: CFrame): Model?
	local kit = ServerStorage:FindFirstChild("PropKit")
	local template = kit and kit:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	model:PivotTo(cframe)
	model.Parent = folder
	return model
end

-- A CFrame at `position` facing `direction` (flattened so it's level)
function TownKit.facing(position: Vector3, direction: Vector3): CFrame
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return CFrame.lookAt(position, position + flat.Unit)
end

return TownKit
