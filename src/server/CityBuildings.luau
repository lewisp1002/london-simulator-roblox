-- Buildings made from parts, in the styles of real London streets, for everywhere the bought building kit
-- doesn't cover: Georgian terraces, Victorian houses with bay windows, rows of shops with flats above,
-- red-brick mansion blocks, Portland stone offices, glass towers, 1960s concrete, warehouses, industrial
-- units, council tower blocks, corner pubs and corner shops, and plain blocks for round the edge of the map.
--
-- CityBuildings.build(style, frame, width, depth, storeys, seed, flank, isBack)
--   frame: the middle of the building's front edge, on the ground, looking out at the road
--   flank: 1 or -1 if the building is on a corner and its right (1) or left (-1) side faces a street too
--   isBack: it stands behind other buildings, so it only needs to look right from a distance
-- Each building is one Model that streams in and out as a whole.
--
-- Windows are made the cheap way: one sheet of glass over the whole face, with strips of wall (piers
-- between the windows and bands between the storeys) laid over it. That gives a full grid of windows for
-- a dozen parts a face instead of hundreds.

local TownKit = require(script.Parent.TownKit)

local box = TownKit.box
local PAVEMENT_TOP = TownKit.PAVEMENT_TOP

local CityBuildings = {}

-- Colours ------------------------------------------------------------------------------------------

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local RED_BRICK = { rgb(142, 72, 52), rgb(128, 66, 50), rgb(156, 86, 62), rgb(117, 58, 44), rgb(150, 96, 72), rgb(134, 80, 62) }
local STOCK_BRICK = { rgb(176, 152, 116), rgb(162, 140, 108), rgb(186, 164, 128), rgb(150, 128, 98) }
local STUCCO = { rgb(236, 232, 222), rgb(240, 236, 226), rgb(232, 226, 210), rgb(226, 222, 214) }
local RENDER = { rgb(214, 205, 186), rgb(196, 192, 180), rgb(224, 214, 190), rgb(204, 198, 188) }
local PORTLAND = rgb(226, 219, 201)
local STONE_TRIM = rgb(222, 214, 194)
local CONCRETE = { rgb(158, 158, 154), rgb(170, 168, 160), rgb(146, 146, 144), rgb(182, 178, 168) }
local GLASS = rgb(38, 50, 60)
local OFFICE_GLASS = { rgb(70, 98, 120), rgb(60, 84, 96), rgb(84, 108, 112), rgb(46, 62, 80), rgb(96, 116, 130) }
local SLATE = rgb(66, 68, 74)
local ROOF_FELT = rgb(52, 52, 55)
local DOORS = { rgb(20, 20, 22), rgb(30, 50, 90), rgb(110, 25, 30), rgb(25, 70, 45), rgb(235, 235, 230), rgb(200, 160, 40) }
local FASCIAS = { rgb(20, 60, 40), rgb(25, 35, 70), rgb(110, 25, 30), rgb(20, 20, 22), rgb(190, 30, 35), rgb(235, 235, 230), rgb(60, 30, 70), rgb(200, 150, 40), rgb(30, 110, 120) }
local PUB_PAINT = { rgb(24, 52, 36), rgb(80, 18, 24), rgb(18, 18, 20), rgb(22, 34, 62) }
local CLADDING = { rgb(170, 175, 180), rgb(120, 140, 160), rgb(150, 160, 150), rgb(190, 190, 185) }
local BAY_WHITE = rgb(236, 236, 230)

-- Made-up names, so there are no real shops or brands anywhere
local SHOP_NAMES = {
	"CAFÉ", "BARBERS", "NEWS & WINE", "LAUNDERETTE", "FRIED CHICKEN", "PHONE REPAIRS", "BAKERY", "FLORIST",
	"ESTATE AGENTS", "PHARMACY", "BOOKMAKERS", "DRY CLEANERS", "KEBAB HOUSE", "PIZZA", "GOLDEN DRAGON",
	"MINI MARKET", "OFF LICENCE", "NAILS & BEAUTY", "OPTICIANS", "HALAL BUTCHERS", "HARDWARE", "TAILORS",
	"FISH & CHIPS", "CHARITY SHOP", "PAWNBROKERS", "TRAVEL AGENTS", "CURRY HOUSE", "SANDWICH BAR", "VAPE SHOP",
	"KEY CUTTING", "PET SHOP", "BRIDGE CAFÉ", "FRESH CUTS", "LUCKY STAR", "CORNER STORES", "MARIO'S",
}
local PUB_NAMES = {
	"THE RED LION", "THE KING'S HEAD", "THE CROWN", "THE ROSE & CROWN", "THE WHITE HART", "THE PLOUGH",
	"THE GEORGE", "THE PRINCE ALBERT", "THE QUEEN'S ARMS", "THE NAG'S HEAD", "THE BLACK HORSE", "THE ROYAL OAK",
	"THE SHIP", "THE BELL", "THE SWAN", "THE ANGEL", "THE GREYHOUND", "THE COACH & HORSES", "THE DUKE OF YORK",
}
local FIRM_NAMES = {
	"CITY TYRES", "METRO TIMBER", "ACE MOTORS", "THAMES PLUMBING", "EAST END PRINTING", "DOCKSIDE STORAGE",
	"LONDON REMOVALS", "QUICK CLUTCH & BRAKE", "RIVERSIDE BUILDERS", "UNITED FABRICS", "BOROUGH SCAFFOLDING",
}

local function choose<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

-- Building blocks -------------------------------------------------------------------------------

-- A part placed in the building's own space: x across, y up from the ground, z back from the front
local function piece(frame: CFrame, size: Vector3, x: number, y: number, z: number, colour: Color3, material: Enum.Material): Part
	return box(size, frame * CFrame.new(x, y, z), colour, material)
end

type Grid = {
	x0: number, -- across the face, from one end
	x1: number, -- to the other
	y0: number, -- bottom of the windowed part
	y1: number, -- top of the windowed part
	bay: number, -- one window and the wall beside it
	window: number, -- window width
	storey: number,
	pane: number, -- window height
	sill: number, -- from each storey's floor up to the bottom of its windows
}

-- A grid of windows on a face. `along` turns the face: "front" (z = at, looking out to -z), "back"
-- (z = at, looking out to +z), "right" (x = at, looking out to +x) or "left" (x = at, looking out to -x).
local WHITE_FRAME = Color3.fromRGB(238, 238, 232)
local SILL_STONE = Color3.fromRGB(214, 208, 192)

-- `frameColour` (optional) adds glazing bars (a bar down and across every window, like a sash window) and
-- a stone sill under each row of windows
local function windows(frame: CFrame, along: string, at: number, g: Grid, wall: Color3, material: Enum.Material, band: Color3?, glass: Color3?, frameColour: Color3?)
	local w, h = g.x1 - g.x0, g.y1 - g.y0
	if w < 2 or h < 2 then
		return
	end
	-- Turn the face so its own x runs across it and -z looks out
	local faceFrame: CFrame
	if along == "front" then
		faceFrame = frame * CFrame.new(0, 0, at)
	elseif along == "back" then
		faceFrame = frame * CFrame.new(0, 0, at) * CFrame.Angles(0, math.pi, 0)
	elseif along == "right" then
		faceFrame = frame * CFrame.new(at, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	else
		faceFrame = frame * CFrame.new(at, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	end
	local cx, cy = (g.x0 + g.x1) / 2, (g.y0 + g.y1) / 2
	local sheet = piece(faceFrame, Vector3.new(w, h, 0.4), cx, cy, -0.1, glass or GLASS, Enum.Material.Glass)
	sheet.Reflectance = 0.08
	sheet.CastShadow = false
	local bays = math.max(1, math.round(w / g.bay))
	local bay = w / bays
	local pier = math.max(0.6, bay - g.window)
	for i = 0, bays do
		local pw = if i == 0 or i == bays then pier / 2 else pier
		local x = g.x0 + i * bay + (if i == 0 then pw / 2 elseif i == bays then -pw / 2 else 0)
		if pw > 0.05 then
			piece(faceFrame, Vector3.new(pw, h, 0.9), x, cy, -0.35, wall, material)
		end
	end
	local storeys = math.max(1, math.round(h / g.storey))
	local sh = h / storeys
	local function strip(yA: number, yB: number)
		if yB - yA > 0.05 then
			piece(faceFrame, Vector3.new(w, yB - yA, 0.9), cx, (yA + yB) / 2, -0.35, band or wall, material)
		end
	end
	strip(g.y0, g.y0 + g.sill)
	for f = 0, storeys - 1 do
		local head = g.y0 + f * sh + g.sill + g.pane
		local nextSill = if f == storeys - 1 then g.y1 else g.y0 + (f + 1) * sh + g.sill
		strip(math.min(head, nextSill), nextSill)
	end
	if frameColour then
		-- The bars sit just in front of the glass, so they only show through the window openings
		for i = 0, bays - 1 do
			local bar = piece(faceFrame, Vector3.new(0.32, h, 0.24), g.x0 + (i + 0.5) * bay, cy, -0.32, frameColour, Enum.Material.SmoothPlastic)
			bar.CastShadow = false
		end
		for f = 0, storeys - 1 do
			local floorY = g.y0 + f * sh
			local bar = piece(faceFrame, Vector3.new(w, 0.32, 0.24), cx, floorY + g.sill + g.pane * 0.55, -0.32, frameColour, Enum.Material.SmoothPlastic)
			bar.CastShadow = false
			-- A stone sill under each row of windows
			piece(faceFrame, Vector3.new(w + 0.2, 0.45, 1.5), cx, floorY + g.sill - 0.2, -0.75, SILL_STONE, Enum.Material.Limestone)
		end
	end
end

local function flatRoof(frame: CFrame, w: number, d: number, h: number, parapet: number, colour: Color3, material: Enum.Material, random: Random)
	piece(frame, Vector3.new(w, 0.5, d), 0, h + 0.25, d / 2, ROOF_FELT, Enum.Material.Concrete)
	if parapet > 0 then
		piece(frame, Vector3.new(w, parapet, 0.8), 0, h + parapet / 2, 0.4, colour, material)
		piece(frame, Vector3.new(w, parapet, 0.8), 0, h + parapet / 2, d - 0.4, colour, material)
	end
	-- A plant room or water tank or two on top
	if w < 14 or d < 14 then
		return
	end
	for _ = 1, random:NextInteger(0, 2) do
		local sx, sz = random:NextNumber(4, math.max(4.5, w * 0.3)), random:NextNumber(4, math.max(4.5, d * 0.3))
		local x = random:NextNumber(-w / 2 + sx / 2 + 1, w / 2 - sx / 2 - 1)
		local z = random:NextNumber(sz / 2 + 2, math.max(sz / 2 + 2.1, d - sz / 2 - 2))
		piece(frame, Vector3.new(sx, 4, sz), x, h + 2.5, z, rgb(150, 150, 148), Enum.Material.Metal)
	end
end

-- A slate roof with its ridge along the street
local function pitchedRoof(frame: CFrame, w: number, d: number, h: number, rise: number, colour: Color3?)
	local slate = colour or SLATE
	local front = box(Vector3.new(w + 0.6, rise, d / 2 + 0.4), frame * CFrame.new(0, h + rise / 2, d / 4 - 0.2), slate, Enum.Material.Slate, "WedgePart")
	local back = box(Vector3.new(w + 0.6, rise, d / 2 + 0.4), frame * CFrame.new(0, h + rise / 2, d * 3 / 4 + 0.2) * CFrame.Angles(0, math.pi, 0), slate, Enum.Material.Slate, "WedgePart")
	front.TopSurface = Enum.SurfaceType.Smooth
	back.TopSurface = Enum.SurfaceType.Smooth
	-- Gutters along the eaves
	local gutter = Color3.fromRGB(34, 34, 36)
	piece(frame, Vector3.new(w + 0.6, 0.5, 0.6), 0, h + 0.15, -0.5, gutter, Enum.Material.Plastic)
	piece(frame, Vector3.new(w + 0.6, 0.5, 0.6), 0, h + 0.15, d + 0.5, gutter, Enum.Material.Plastic)
end

-- A drainpipe down the front at x
local function drainpipe(frame: CFrame, x: number, h: number)
	piece(frame, Vector3.new(0.45, h, 0.45), x, h / 2, -0.75, Color3.fromRGB(34, 34, 36), Enum.Material.Plastic)
end

-- Chimney stacks along the ridge, one between each pair of houses
local function chimneys(frame: CFrame, w: number, d: number, top: number, count: number, colour: Color3)
	for i = 0, count do
		local x = math.clamp(-w / 2 + i * w / count, -w / 2 + 1.2, w / 2 - 1.2)
		piece(frame, Vector3.new(2.4, 5.5, 3.4), x, top + 1.5, d / 2, colour, Enum.Material.Brick)
		piece(frame, Vector3.new(0.9, 1.2, 0.9), x - 0.6, top + 4.8, d / 2, Color3.fromRGB(150, 80, 50), Enum.Material.Concrete)
		piece(frame, Vector3.new(0.9, 1.2, 0.9), x + 0.6, top + 4.8, d / 2, Color3.fromRGB(150, 80, 50), Enum.Material.Concrete)
	end
end

local function cornice(frame: CFrame, w: number, y: number, colour: Color3, depth: number?)
	piece(frame, Vector3.new(w + 0.8, 1.2, depth or 1.4), 0, y, -(depth or 1.4) / 2 + 0.6, colour, Enum.Material.Limestone)
end

-- A strip of paving between the pavement and the front of the building, so they meet neatly
local function apron(frame: CFrame, w: number)
	piece(frame, Vector3.new(w, PAVEMENT_TOP, 1.6), 0, PAVEMENT_TOP / 2, -0.7, TownKit.Colours.Pavement, Enum.Material.Pavement)
end

local function door(frame: CFrame, x: number, colour: Color3, wide: number?)
	piece(frame, Vector3.new(wide or 3.4, 7.6, 0.5), x, PAVEMENT_TOP + 3.8, -0.6, colour, Enum.Material.Wood)
end

local function sign(host: BasePart, text: string, colour: Color3, background: Color3?)
	TownKit.text(host, Enum.NormalId.Front, text, colour, background, Enum.FontWeight.Bold)
end

-- Styles --------------------------------------------------------------------------------------------

type Spec = { frame: CFrame, w: number, d: number, storeys: number, random: Random, flank: number, back: boolean }

-- Two-up two-down terraced houses with bay windows, chimneys and a slate roof
local function victorian(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 10
	local h = s.storeys * storeyH
	local wall = if r:NextNumber() < 0.7 then choose(RED_BRICK, r) else choose(STOCK_BRICK, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Brick)
	local houses = math.max(1, math.round(w / 16))
	local hw = w / houses
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = 0, y1 = h, bay = hw / 2, window = 4.2, storey = storeyH, pane = 6, sill = 2.6 }
	windows(f, "front", 0, grid, wall, Enum.Material.Brick, nil, nil, WHITE_FRAME)
	local doorColour = choose(DOORS, r)
	for i = 0, houses - 1 do
		local left = -w / 2 + i * hw
		local mirrored = i % 2 == 1
		local doorX = left + (if mirrored then hw * 0.75 else hw * 0.25)
		local bayX = left + (if mirrored then hw * 0.25 else hw * 0.75)
		door(f, doorX, if r:NextNumber() < 0.3 then choose(DOORS, r) else doorColour)
		-- The bay window: a painted box sticking out, with glass on its front
		local bayW = math.min(7, hw / 2 - 0.8)
		piece(f, Vector3.new(bayW, 8.6, 2.4), bayX, PAVEMENT_TOP + 4.3, -1.2, BAY_WHITE, Enum.Material.Plaster)
		local pane = piece(f, Vector3.new(bayW - 1.4, 5.2, 0.3), bayX, PAVEMENT_TOP + 4.2, -2.45, GLASS, Enum.Material.Glass)
		pane.Reflectance = 0.15
	end
	pitchedRoof(f, w, d, h, math.min(d * 0.32, 9))
	for i = 0, houses do
		local x = -w / 2 + i * hw
		if i == 0 then
			x += 1.2
		elseif i == houses then
			x -= 1.2
		end
		piece(f, Vector3.new(2.2, 5, 3.2), x, h + math.min(d * 0.32, 9) - 0.5, d / 2, wall, Enum.Material.Brick)
	end
	apron(f, w)
end

-- Georgian terraces: tall sash windows, a white ground floor or all white stucco, a cornice and parapet
local function georgian(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 11
	local h = s.storeys * storeyH
	local stucco = r:NextNumber() < 0.45
	local wall = if stucco then choose(STUCCO, r) else choose(STOCK_BRICK, r)
	local material = if stucco then Enum.Material.Plaster else Enum.Material.Brick
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, material)
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = 0, y1 = h, bay = 8, window = 4, storey = storeyH, pane = 7.4, sill = 2.6 }
	windows(f, "front", 0, grid, wall, material, nil, nil, WHITE_FRAME)
	if not stucco then
		-- The ground floor rendered white, as on so many London terraces
		piece(f, Vector3.new(w, storeyH, 1.1), 0, storeyH / 2, -0.45, choose(STUCCO, r), Enum.Material.Plaster)
		local glassFront = piece(f, Vector3.new(w - 2, 6.6, 0.3), 0, 2.6 + 3.3, -1.05, GLASS, Enum.Material.Glass)
		glassFront.Reflectance = 0.15
		-- piers between the ground floor windows
		local bays = math.max(1, math.round(w / 8))
		for i = 1, bays - 1 do
			piece(f, Vector3.new(3.8, 6.8, 0.5), -w / 2 + i * w / bays, 2.6 + 3.3, -1.2, choose(STUCCO, r), Enum.Material.Plaster)
		end
	end
	local houses = math.max(1, math.round(w / 24))
	for i = 0, houses - 1 do
		local x = -w / 2 + (i + 0.5) * w / houses - 4
		door(f, x, choose(DOORS, r))
	end
	cornice(f, w, h - 1.6, STONE_TRIM)
	if r:NextNumber() < 0.55 then
		-- A slate roof rising behind a low parapet
		piece(f, Vector3.new(w, 1.6, 0.8), 0, h + 0.8, 0.4, wall, material)
		pitchedRoof(f, w, d, h, math.min(d * 0.3, 9))
		chimneys(f, w, d, h + math.min(d * 0.3, 9) - 1, math.max(1, math.round(w / 24)), wall)
	else
		flatRoof(f, w, d, h, 2.6, wall, material, r)
	end
	-- Black railings along the front
	local rail = piece(f, Vector3.new(w - 1, 3, 0.2), 0, PAVEMENT_TOP + 1.5, -1.3, rgb(18, 18, 20), Enum.Material.Metal)
	rail.Transparency = 0.45
	rail.CastShadow = false
	apron(f, w)
end

-- A row of shops with flats above
local function shops(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local groundH, storeyH = 12, 10
	local h = groundH + (s.storeys - 1) * storeyH
	local roll = r:NextNumber()
	local wall = if roll < 0.55 then choose(RED_BRICK, r) elseif roll < 0.8 then choose(STOCK_BRICK, r) else choose(RENDER, r)
	local material = if roll < 0.8 then Enum.Material.Brick else Enum.Material.Plaster
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, material)
	local units = math.max(1, math.round(w / 18))
	local uw = w / units
	for i = 0, units - 1 do
		local x = -w / 2 + (i + 0.5) * uw
		local glass = piece(f, Vector3.new(uw - 2.2, 7.6, 0.4), x, PAVEMENT_TOP + 4.4, -0.3, GLASS, Enum.Material.Glass)
		glass.Reflectance = 0.2
		local fasciaColour = choose(FASCIAS, r)
		local fascia = piece(f, Vector3.new(uw - 0.8, 2.3, 1), x, PAVEMENT_TOP + 9.9, -0.6, fasciaColour, Enum.Material.SmoothPlastic)
		if r:NextNumber() < 0.75 then
			local light = fasciaColour.R + fasciaColour.G + fasciaColour.B > 2
			sign(fascia, choose(SHOP_NAMES, r), if light then rgb(30, 30, 30) else rgb(245, 240, 225))
		end
		if r:NextNumber() < 0.25 then
			-- A sloping awning over the window
			-- (a wedge is tallest at its back, so this one is high against the wall and low at the pavement)
			local awning = box(Vector3.new(uw - 1.6, 1.8, 3.4), f * CFrame.new(x, PAVEMENT_TOP + 8.2, -1.9), choose(FASCIAS, r), Enum.Material.Fabric, "WedgePart")
			awning.CanCollide = false
		end
	end
	for i = 0, units do
		local pw = if i == 0 or i == units then 0.8 else 1.2
		local x = -w / 2 + i * uw + (if i == 0 then pw / 2 elseif i == units then -pw / 2 else 0)
		piece(f, Vector3.new(pw, groundH, 1), x, groundH / 2, -0.5, wall, material)
	end
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = groundH, y1 = h, bay = 7, window = 3.8, storey = storeyH, pane = 6, sill = 2.4 }
	windows(f, "front", 0, grid, wall, material, nil, nil, WHITE_FRAME)
	if s.flank ~= 0 then
		local side = { x0 = -d / 2, x1 = d / 2, y0 = groundH, y1 = h, bay = 7, window = 3.8, storey = storeyH, pane = 6, sill = 2.4 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, material, nil, nil, WHITE_FRAME)
	end
	if r:NextNumber() < 0.3 then
		cornice(f, w, h - 1, STONE_TRIM)
		flatRoof(f, w, d, h, 2, wall, material, r)
	else
		pitchedRoof(f, w, d, h, math.min(d * 0.32, 10))
		chimneys(f, w, d, h + math.min(d * 0.32, 10) - 1, math.max(1, math.round(w / 20)), wall)
	end
	drainpipe(f, w / 2 - 0.6, h)
	apron(f, w)
end

-- Red-brick mansion blocks with stone bands, and shops along the bottom on the busier streets
local function mansion(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 11
	local h = s.storeys * storeyH
	local wall = if r:NextNumber() < 0.75 then choose(RED_BRICK, r) else choose(STOCK_BRICK, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Brick)
	local withShops = r:NextNumber() < 0.4 and not s.back
	local y0 = 0
	if withShops then
		y0 = storeyH + 1
		local units = math.max(1, math.round(w / 20))
		local uw = w / units
		for i = 0, units - 1 do
			local x = -w / 2 + (i + 0.5) * uw
			local glass = piece(f, Vector3.new(uw - 2.4, 7.6, 0.4), x, PAVEMENT_TOP + 4.4, -0.3, GLASS, Enum.Material.Glass)
			glass.Reflectance = 0.2
			local fascia = piece(f, Vector3.new(uw - 1, 2.2, 1), x, PAVEMENT_TOP + 9.8, -0.6, choose(FASCIAS, r), Enum.Material.SmoothPlastic)
			if r:NextNumber() < 0.6 then
				sign(fascia, choose(SHOP_NAMES, r), rgb(245, 240, 225))
			end
		end
		piece(f, Vector3.new(w, 1.4, 1.2), 0, y0 - 0.7, -0.6, STONE_TRIM, Enum.Material.Limestone)
	end
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = y0, y1 = h, bay = 9, window = 4.4, storey = storeyH, pane = 7, sill = 2.6 }
	windows(f, "front", 0, grid, wall, Enum.Material.Brick, STONE_TRIM, nil, WHITE_FRAME)
	windows(f, "back", d, grid, wall, Enum.Material.Brick, nil)
	if s.flank ~= 0 then
		local side = { x0 = -d / 2, x1 = d / 2, y0 = y0, y1 = h, bay = 9, window = 4.4, storey = storeyH, pane = 7, sill = 2.6 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, Enum.Material.Brick, STONE_TRIM, nil, WHITE_FRAME)
	end
	if not withShops then
		door(f, 0, choose(DOORS, r), 5)
	end
	cornice(f, w, h - 0.6, STONE_TRIM)
	-- A slate mansard roof with a storey in it
	piece(f, Vector3.new(w - 1, 8, d - 6), 0, h + 4, d / 2, SLATE, Enum.Material.Slate)
	apron(f, w)
end

-- Portland stone offices and government buildings
local function stone(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 11.5
	local h = s.storeys * storeyH
	local wall = PORTLAND
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Limestone)
	-- A heavier base storey
	piece(f, Vector3.new(w, storeyH + 1, 1.2), 0, (storeyH + 1) / 2, -0.5, rgb(206, 198, 180), Enum.Material.Limestone)
	local baseGlass = piece(f, Vector3.new(w - 3, 7.5, 0.3), 0, PAVEMENT_TOP + 4.6, -1.15, GLASS, Enum.Material.Glass)
	baseGlass.Reflectance = 0.15
	local bays = math.max(1, math.round(w / 10))
	for i = 0, bays do
		local x = -w / 2 + i * w / bays
		piece(f, Vector3.new(if i == 0 or i == bays then 2 else 3.4, 8, 0.6), math.clamp(x, -w / 2 + 1, w / 2 - 1), PAVEMENT_TOP + 4.6, -1.3, rgb(206, 198, 180), Enum.Material.Limestone)
	end
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH + 1, y1 = h, bay = 9, window = 4.2, storey = storeyH, pane = 7.6, sill = 2.4 }
	windows(f, "front", 0, grid, wall, Enum.Material.Limestone, nil, nil, Color3.fromRGB(64, 66, 70))
	windows(f, "back", d, grid, wall, Enum.Material.Limestone, nil)
	if s.flank ~= 0 then
		local side = { x0 = -d / 2, x1 = d / 2, y0 = storeyH + 1, y1 = h, bay = 9, window = 4.2, storey = storeyH, pane = 7.6, sill = 2.4 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, Enum.Material.Limestone, nil, nil, Color3.fromRGB(64, 66, 70))
	end
	door(f, 0, rgb(30, 30, 32), 6)
	cornice(f, w, h - 0.4, STONE_TRIM, 2)
	-- A set-back top storey
	piece(f, Vector3.new(w - 4, storeyH - 2, d - 8), 0, h + (storeyH - 2) / 2, d / 2 + 1, rgb(210, 204, 190), Enum.Material.Limestone)
	flatRoof(f, w - 4, d - 8, h + storeyH - 2, 0, wall, Enum.Material.Limestone, r)
	apron(f, w)
end

-- Glass and steel offices. Taller ones stand on a podium.
local function office(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 12
	local storeys = s.storeys
	local glassColour = choose(OFFICE_GLASS, r)
	local frameColour = if r:NextNumber() < 0.5 then rgb(70, 72, 76) else rgb(200, 200, 196)
	if storeys <= 11 and r:NextNumber() < 0.5 then
		-- A stone or concrete framed office with a grid of big windows
		local h = storeys * storeyH
		local wall = if r:NextNumber() < 0.5 then PORTLAND else choose(CONCRETE, r)
		piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Concrete)
		local grid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH, y1 = h, bay = 10, window = 7, storey = storeyH, pane = 8, sill = 2 }
		windows(f, "front", 0, grid, wall, Enum.Material.Concrete, nil, glassColour, Color3.fromRGB(64, 66, 70))
		windows(f, "back", d, grid, wall, Enum.Material.Concrete, nil, glassColour)
		if s.flank ~= 0 then
			local side = { x0 = -d / 2, x1 = d / 2, y0 = storeyH, y1 = h, bay = 10, window = 7, storey = storeyH, pane = 8, sill = 2 }
			windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, Enum.Material.Concrete, nil, glassColour, Color3.fromRGB(64, 66, 70))
		end
		local lobby = piece(f, Vector3.new(w - 2, storeyH - 1.5, 0.4), 0, PAVEMENT_TOP + (storeyH - 1.5) / 2, -0.3, glassColour, Enum.Material.Glass)
		lobby.Reflectance = 0.25
		flatRoof(f, w, d, h, 1.5, wall, Enum.Material.Concrete, r)
		apron(f, w)
		return
	end
	-- Curtain-wall glass: the whole body is glass, with a band round it at every floor
	local podium = if storeys > 12 then 3 else 0
	local tw, td = w, d
	local towerZ = d / 2
	if podium > 0 then
		local ph = podium * storeyH
		local podiumWall = choose(CONCRETE, r)
		piece(f, Vector3.new(w, ph, d), 0, ph / 2, d / 2, podiumWall, Enum.Material.Concrete)
		local lobby = piece(f, Vector3.new(w - 2, storeyH * 2 - 1, 0.4), 0, PAVEMENT_TOP + storeyH - 0.5, -0.3, glassColour, Enum.Material.Glass)
		lobby.Reflectance = 0.25
		-- Windows round the podium's upper floor
		local podiumGrid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH * 2, y1 = ph, bay = 10, window = 7, storey = storeyH, pane = 7, sill = 2.5 }
		windows(f, "back", d, { x0 = -w / 2, x1 = w / 2, y0 = 2, y1 = ph, bay = 10, window = 7, storey = storeyH, pane = 7, sill = 2.5 }, podiumWall, Enum.Material.Concrete, nil, glassColour)
		windows(f, "front", 0, podiumGrid, podiumWall, Enum.Material.Concrete, nil, glassColour)
		local sideGrid = { x0 = -d / 2, x1 = d / 2, y0 = 2, y1 = ph, bay = 10, window = 7, storey = storeyH, pane = 7, sill = 2.5 }
		windows(f * CFrame.new(0, 0, d / 2), "right", w / 2, sideGrid, podiumWall, Enum.Material.Concrete, nil, glassColour)
		windows(f * CFrame.new(0, 0, d / 2), "left", -w / 2, sideGrid, podiumWall, Enum.Material.Concrete, nil, glassColour)
		tw, td = w * r:NextNumber(0.7, 0.88), d * r:NextNumber(0.7, 0.88)
		towerZ = d / 2 + r:NextNumber(-1, 1) * (d - td) / 4
		local body = piece(f, Vector3.new(tw, (storeys - podium) * storeyH, td), 0, ph + (storeys - podium) * storeyH / 2, towerZ, glassColour, Enum.Material.Glass)
		body.Reflectance = 0.3
		for k = podium + 1, storeys do
			piece(f, Vector3.new(tw + 0.4, 1, td + 0.4), 0, k * storeyH - 0.5, towerZ, frameColour, Enum.Material.Metal)
		end
		flatRoof(f * CFrame.new(0, 0, towerZ - td / 2), tw, td, storeys * storeyH, 2, frameColour, Enum.Material.Metal, r)
	else
		local h = storeys * storeyH
		local body = piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, glassColour, Enum.Material.Glass)
		body.Reflectance = 0.3
		for k = 1, storeys do
			piece(f, Vector3.new(w + 0.4, 1, d + 0.4), 0, k * storeyH - 0.5, d / 2, frameColour, Enum.Material.Metal)
		end
		flatRoof(f, w, d, h, 2, frameColour, Enum.Material.Metal, r)
	end
	-- Corner columns
	for _, cx in { -tw / 2, tw / 2 } do
		for _, cz in { towerZ - td / 2, towerZ + td / 2 } do
			piece(f, Vector3.new(1.2, storeys * storeyH, 1.2), cx, storeys * storeyH / 2, cz, frameColour, Enum.Material.Metal)
		end
	end
	apron(f, w)
end

-- 1960s concrete: ribbon windows and plain bands
local function concrete(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 10.5
	local h = s.storeys * storeyH
	local wall = choose(CONCRETE, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Concrete)
	local ribbon = r:NextNumber() < 0.5
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH, y1 = h, bay = if ribbon then 6 else 8, window = if ribbon then 5.4 else 5, storey = storeyH, pane = if ribbon then 4.8 else 6, sill = 3 }
	windows(f, "front", 0, grid, wall, Enum.Material.Concrete, nil)
	windows(f, "back", d, grid, wall, Enum.Material.Concrete, nil)
	if s.flank ~= 0 then
		local side = { x0 = -d / 2, x1 = d / 2, y0 = storeyH, y1 = h, bay = grid.bay, window = grid.window, storey = storeyH, pane = grid.pane, sill = 3 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, side, wall, Enum.Material.Concrete, nil)
	end
	local lobby = piece(f, Vector3.new(w - 6, storeyH - 2, 0.4), 0, PAVEMENT_TOP + (storeyH - 2) / 2, -0.3, GLASS, Enum.Material.Glass)
	lobby.Reflectance = 0.2
	flatRoof(f, w, d, h, 1.2, wall, Enum.Material.Concrete, r)
	apron(f, w)
end

-- Victorian brick warehouses, with a column of loading doors and a hoist beam
local function warehouse(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 11
	local h = s.storeys * storeyH
	local wall = choose({ rgb(118, 58, 44), rgb(104, 54, 42), rgb(132, 70, 52), rgb(150, 128, 98) }, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Brick)
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = 0, y1 = h, bay = 8, window = 3.6, storey = storeyH, pane = 5.6, sill = 3.2 }
	windows(f, "front", 0, grid, wall, Enum.Material.Brick, nil, nil, Color3.fromRGB(40, 40, 42))
	windows(f, "back", d, grid, wall, Enum.Material.Brick, nil)
	local doorsX = r:NextNumber(-w / 4, w / 4)
	piece(f, Vector3.new(5, h - 4, 0.8), doorsX, (h - 4) / 2 + 1, -0.7, rgb(60, 40, 28), Enum.Material.WoodPlanks)
	piece(f, Vector3.new(0.8, 0.8, 4), doorsX, h - 1.5, -2, rgb(30, 30, 32), Enum.Material.Metal)
	flatRoof(f, w, d, h, 2.5, wall, Enum.Material.Brick, r)
	apron(f, w)
end

-- Industrial units: metal cladding, roller doors, a shallow roof
local function shed(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local h = 18
	local wall = choose(CLADDING, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Metal)
	local doors = math.max(1, math.floor(w / 30))
	for i = 1, doors do
		local x = -w / 2 + i * w / (doors + 1)
		piece(f, Vector3.new(12, 13, 0.5), x, 6.5, -0.3, rgb(120, 122, 126), Enum.Material.DiamondPlate)
	end
	local office = piece(f, Vector3.new(math.min(14, w * 0.25), 3.5, 0.4), -w / 2 + math.min(14, w * 0.25) / 2 + 1, 12, -0.3, GLASS, Enum.Material.Glass)
	office.Reflectance = 0.2
	local board = piece(f, Vector3.new(math.min(w * 0.5, 30), 3, 0.6), 0, h - 2.2, -0.5, rgb(240, 240, 236), Enum.Material.SmoothPlastic)
	sign(board, choose(FIRM_NAMES, r), choose({ rgb(20, 60, 140), rgb(170, 30, 30), rgb(20, 20, 22), rgb(20, 110, 60) }, r))
	pitchedRoof(f, w, d, h, 3, rgb(150, 154, 158))
	-- A yard of concrete in front, for vans
	piece(f, Vector3.new(w, PAVEMENT_TOP, 1.6), 0, PAVEMENT_TOP / 2, -0.7, rgb(160, 160, 156), Enum.Material.Concrete)
end

-- Council tower blocks: concrete with a balcony on every floor
local function council(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 9.5
	local h = s.storeys * storeyH
	local wall = choose({ rgb(196, 190, 176), rgb(170, 168, 160), rgb(150, 110, 90), rgb(188, 180, 160) }, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Concrete)
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = storeyH, y1 = h, bay = 9, window = 5.4, storey = storeyH, pane = 5, sill = 2.6 }
	windows(f, "front", 0, grid, wall, Enum.Material.Concrete, nil, nil, WHITE_FRAME)
	windows(f, "back", d, grid, wall, Enum.Material.Concrete, nil)
	local balcony = choose({ rgb(60, 90, 140), rgb(170, 60, 40), rgb(230, 230, 225), rgb(70, 120, 80) }, r)
	for k = 1, s.storeys - 1 do
		local panel = piece(f, Vector3.new(w - 6, 3.4, 0.4), 0, k * storeyH + 1.7, -3, balcony, Enum.Material.SmoothPlastic)
		panel.CastShadow = false
		piece(f, Vector3.new(w - 6, 0.5, 3), 0, k * storeyH + 0.25, -1.5, wall, Enum.Material.Concrete)
	end
	door(f, 0, rgb(40, 60, 90), 6)
	piece(f, Vector3.new(10, 8, 10), 0, h + 4, d / 2, wall, Enum.Material.Concrete)
	flatRoof(f, w, d, h, 1.2, wall, Enum.Material.Concrete, r)
	apron(f, w)
end

-- A corner pub: painted ground floor with big windows and the name in gold, brick above, a hanging sign
local function pub(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local groundH, storeyH = 12, 10.5
	local h = groundH + (s.storeys - 1) * storeyH
	local wall = choose(RED_BRICK, r)
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, Enum.Material.Brick)
	local paint = choose(PUB_PAINT, r)
	local name = choose(PUB_NAMES, r)
	local function groundFloor(face: CFrame, length: number)
		piece(face, Vector3.new(length, groundH, 1.2), 0, groundH / 2, -0.5, paint, Enum.Material.Wood)
		local panes = math.max(1, math.round(length / 12))
		for i = 0, panes - 1 do
			local x = -length / 2 + (i + 0.5) * length / panes
			local glass = piece(face, Vector3.new(length / panes - 3, 6.5, 0.3), x, PAVEMENT_TOP + 4.6, -1.15, rgb(60, 45, 30), Enum.Material.Glass)
			glass.Reflectance = 0.25
		end
		local fascia = piece(face, Vector3.new(length - 1, 2.4, 0.6), 0, groundH - 1.6, -1.25, paint, Enum.Material.Wood)
		sign(fascia, name, rgb(214, 178, 90))
	end
	groundFloor(f, w)
	if s.flank ~= 0 then
		local side = f * CFrame.new(s.flank * w / 2, 0, d / 2) * CFrame.Angles(0, -s.flank * math.pi / 2, 0)
		groundFloor(side, d)
		local sideGrid = { x0 = -d / 2, x1 = d / 2, y0 = groundH, y1 = h, bay = 8, window = 4, storey = storeyH, pane = 6.4, sill = 2.4 }
		windows(f * CFrame.new(0, 0, d / 2), if s.flank > 0 then "right" else "left", s.flank * w / 2, sideGrid, wall, Enum.Material.Brick, nil, nil, WHITE_FRAME)
	end
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = groundH, y1 = h, bay = 8, window = 4, storey = storeyH, pane = 6.4, sill = 2.4 }
	windows(f, "front", 0, grid, wall, Enum.Material.Brick, nil, nil, WHITE_FRAME)
	-- The hanging sign on its bracket, at the corner
	local cornerX = if s.flank ~= 0 then s.flank * (w / 2 - 1) else w / 2 - 2
	piece(f, Vector3.new(0.4, 0.4, 3.2), cornerX, groundH + 3, -1.6, rgb(20, 20, 20), Enum.Material.Metal)
	local board = piece(f, Vector3.new(0.4, 3.6, 2.8), cornerX, groundH + 0.8, -2.6, paint, Enum.Material.Wood)
	board.CanCollide = false
	cornice(f, w, h - 0.8, STONE_TRIM)
	if r:NextNumber() < 0.5 then
		pitchedRoof(f, w, d, h, math.min(d * 0.3, 9))
	else
		flatRoof(f, w, d, h, 2, wall, Enum.Material.Brick, r)
	end
	apron(f, w)
end

-- A corner shop with flats above
local function corner(s: Spec)
	shops(s)
end

-- Plain blocks for the edge of the map, seen from a distance
local function backdrop(s: Spec)
	local f, w, d, r = s.frame, s.w, s.d, s.random
	local storeyH = 10.5
	local h = s.storeys * storeyH
	local roll = r:NextNumber()
	local wall = if roll < 0.45 then choose(RED_BRICK, r) elseif roll < 0.7 then choose(STOCK_BRICK, r) else choose(CONCRETE, r)
	local material = if roll < 0.7 then Enum.Material.Brick else Enum.Material.Concrete
	piece(f, Vector3.new(w, h, d), 0, h / 2, d / 2, wall, material)
	local grid = { x0 = -w / 2, x1 = w / 2, y0 = 2, y1 = h, bay = 9, window = 4.6, storey = storeyH, pane = 6, sill = 2.4 }
	windows(f, "front", 0, grid, wall, material, nil)
	if roll < 0.75 then
		pitchedRoof(f, w, d, h, math.min(d * 0.3, 12))
	else
		flatRoof(f, w, d, h, 1.5, wall, material, r)
	end
end

local BUILDERS: { [string]: (Spec) -> () } = {
	victorian = victorian,
	georgian = georgian,
	shops = shops,
	mansion = mansion,
	stone = stone,
	office = office,
	concrete = concrete,
	warehouse = warehouse,
	shed = shed,
	council = council,
	pub = pub,
	corner = corner,
	backdrop = backdrop,
}

function CityBuildings.has(style: string): boolean
	return BUILDERS[style] ~= nil
end

-- Builds one building and returns its Model (see the top of this file)
function CityBuildings.build(style: string, frame: CFrame, width: number, depth: number, storeys: number, seed: number, flank: number, isBack: boolean): Model
	local model = Instance.new("Model")
	model.Name = style
	local parent = TownKit.getParent()
	TownKit.setParent(model)
	local builder = BUILDERS[style] or georgian
	builder({ frame = frame, w = width, d = depth, storeys = math.max(1, storeys), random = Random.new(seed), flank = flank, back = isBack })
	TownKit.setParent(parent :: Instance)
	-- Only the main body is solid. Everything else (window strips, bars, sills, roofs, chimneys, signs) is just
	-- for looks, so it's taken out of the physics engine: hundreds of thousands of physics parts used gigabytes
	-- of memory and made the game freeze. Thin details don't cast shadows either: far cheaper to draw.
	local body = model:FindFirstChildWhichIsA("BasePart")
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CanTouch = false
			if part ~= body then
				part.CanCollide = false
				part.CanQuery = false
			end
			local size = part.Size
			if math.min(size.X, size.Y, size.Z) < 1.6 then
				part.CastShadow = false
			end
		end
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = parent
	return model
end

return CityBuildings
