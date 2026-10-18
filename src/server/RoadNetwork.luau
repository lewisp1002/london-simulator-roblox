-- Builds every road in the map from LondonLayout (which tools/london_layout.py writes):
--   * the tarmac, kerbs and pavements, following each road's curves
--   * junctions with rounded kerbs, give-way and stop lines, and traffic lights
--   * roundabouts with an island, and mini roundabouts with a painted dot
--   * lane lines for every kind of road, from side streets to the motorway
--   * bridges and flyovers: parapets, pillars and ramps wherever a road is above the ground
--   * slip roads that taper into the motorway, and laybys
-- LondonMap calls RoadNetwork.build once, then uses what it returns for buildings, props and the minimap.

local Workspace = game:GetService("Workspace")

local RoadKit = require(script.Parent.RoadKit)
local TownKit = require(script.Parent.TownKit)
local TownProps = require(script.Parent.TownProps)

type Path = RoadKit.Path

local C = TownKit.Colours
local ROAD_TOP = TownKit.ROAD_TOP
local KERB = TownKit.KERB_HEIGHT

local ROAD = { colour = C.Asphalt, material = Enum.Material.Asphalt, thickness = 2 }
local MOTORWAY_ROAD = { colour = Color3.fromRGB(90, 91, 94), material = Enum.Material.Asphalt, thickness = 2 }
local PAVEMENT = { colour = C.Pavement, material = Enum.Material.Pavement, thickness = KERB + 2 }
local RED_PAVEMENT = { colour = C.RedPaving, material = Enum.Material.Pavement, thickness = KERB + 2 }
local ISLAND = { colour = C.Grass, material = Enum.Material.Grass, thickness = KERB + 2 }
local CONCRETE = { colour = C.Concrete, material = Enum.Material.Concrete, thickness = KERB + 2 }
local PARAPET_COLOUR = Color3.fromRGB(178, 176, 170)
local PILLAR_COLOUR = Color3.fromRGB(150, 150, 146)

local MAX_TRIM = 150 -- a junction never cuts more than this off a road
local HAZARD_LENGTH = 45 -- long "warning" dashes on the centre line for this far before a junction

export type Profile = {
	lanes: number,
	lane: number,
	parking: number?, -- a strip along each kerb where cars park
	res: number,
	shoulder: number,
	edge: number,
	side: string,
	sideWidth: number,
	limit: number,
	rank: number,
	oneway: boolean?,
}

export type Node = {
	id: string,
	pos: Vector3, -- road surface height
	kind: string,
	radius: number,
	island: number,
	name: string,
	ends: { End },
	reach: number, -- how far the junction's tarmac spreads from its middle
}

export type Road = {
	id: string,
	name: string,
	kind: string,
	profile: Profile,
	a: Node,
	b: Node,
	path: Path,
	hw: number, -- half the width of the tarmac
	sideWidth: number,
	side: string,
	limit: number,
	startTrim: number,
	endTrim: number,
	sideFrom: { [number]: number }, -- [1] left, [-1] right: where the pavement starts and stops
	sideTo: { [number]: number },
	gaps: { { number } },
	laybys: { { number } },
	taper: string?,
	taperFrom: Vector3?,
	raised: { { number } }, -- stretches above the ground (bridges, flyovers, ramps)
}

export type End = {
	road: Road,
	node: Node,
	atStart: boolean,
	sign: number, -- 1 at the start of the road, -1 at the end
	dir: Vector3, -- flat, pointing away from the junction along the road
	left: Vector3, -- flat, to the left looking along dir
	angle: number,
	hw: number,
	trim: number,
	leftTrim: number,
	rightTrim: number,
	major: boolean,
	axis: string?,
}

export type Result = {
	roads: { Road },
	nodes: { Node },
	byId: { [string]: Road },
	minimap: { { any } },
}

local RoadNetwork = {}

local function halfWidth(p: Profile): number
	if p.oneway then
		return p.lanes * p.lane / 2 + p.edge
	end
	return p.res / 2 + p.lanes * p.lane + (p.parking or 0) + p.shoulder + p.edge
end

-- Where along the road a point `distance` from this end is
local function stationFor(e: End, distance: number): number
	return if e.atStart then distance else e.road.path.length - distance
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Where the line p + d*s meets the line q + e*u (flat)
local function intersect(p: Vector3, d: Vector3, q: Vector3, e: Vector3): (number?, number?)
	local den = d.X * e.Z - d.Z * e.X
	if math.abs(den) < 1e-6 then
		return nil, nil
	end
	local dx, dz = q.X - p.X, q.Z - p.Z
	return (dx * e.Z - dz * e.X) / den, (dx * d.Z - dz * d.X) / den
end

-- Points round a circle from one point to another, the short way
local function shortArc(centre: Vector3, from: Vector3, to: Vector3, y: number): { Vector3 }
	local a0 = math.atan2(from.Z - centre.Z, from.X - centre.X)
	local a1 = math.atan2(to.Z - centre.Z, to.X - centre.X)
	local sweep = a1 - a0
	while sweep > math.pi do
		sweep -= 2 * math.pi
	end
	while sweep < -math.pi do
		sweep += 2 * math.pi
	end
	local radius = (Vector3.new(from.X, 0, from.Z) - Vector3.new(centre.X, 0, centre.Z)).Magnitude
	return RoadKit.arc(Vector3.new(centre.X, y, centre.Z), radius, a0, a0 + sweep)
end

local function setLimit(parts: { BasePart }, limit: number)
	for _, part in parts do
		part:SetAttribute("SpeedLimit", limit)
	end
end

local function cylinder(radius: number, thickness: number, top: Vector3, colour: Color3, material: Enum.Material): Part
	local part = TownKit.box(Vector3.new(thickness, radius * 2, radius * 2), CFrame.new(top - Vector3.new(0, thickness / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), colour, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Kerb radius at a corner between two roads
local function cornerRadius(a: End, b: End): number
	local rank = math.max(a.road.profile.rank, b.road.profile.rank)
	local base = if rank >= 3 then 24 else 16
	local pave = math.max(if a.road.side == "pavement" then a.road.sideWidth else 0, if b.road.side == "pavement" then b.road.sideWidth else 0)
	return math.max(base, pave + 3)
end

-- Junctions ----------------------------------------------------------------------------------

type Corner = {
	a: End,
	b: End,
	straight: boolean,
	centre: Vector3?,
	radius: number,
	ta: Vector3?,
	tb: Vector3?,
	sharp: boolean?,
}

local function solveJunction(node: Node): { Corner }
	local ends = node.ends
	local corners: { Corner } = {}
	for _, e in ends do
		e.trim, e.leftTrim, e.rightTrim = 2, 0, 0
	end
	if #ends < 2 then
		return corners
	end
	local origin = flat(node.pos)
	for i, a in ends do
		local b = ends[i % #ends + 1]
		local delta = (b.angle - a.angle) % (2 * math.pi)
		if #ends == 2 and i == 2 then
			delta = (2 * math.pi) - ((ends[2].angle - ends[1].angle) % (2 * math.pi))
		end
		local corner: Corner = { a = a, b = b, straight = true, radius = 0 }
		if delta < math.rad(170) and delta > 1e-3 then
			local radius = cornerRadius(a, b)
			for _ = 1, 6 do
				local pa = origin + a.left * (a.hw + radius)
				local pb = origin - b.left * (b.hw + radius)
				local s, u = intersect(pa, a.dir, pb, b.dir)
				if s and u and s >= 0 and u >= 0 and s < MAX_TRIM and u < MAX_TRIM then
					corner.straight = false
					corner.radius = radius
					corner.centre = pa + a.dir * s
					corner.ta = origin + a.dir * s + a.left * a.hw
					corner.tb = origin + b.dir * u - b.left * b.hw
					a.leftTrim = math.max(a.leftTrim, s)
					b.rightTrim = math.max(b.rightTrim, u)
					break
				end
				radius *= 0.6
				if radius < 3 then
					break
				end
			end
			if corner.straight then
				-- A sharp corner where the two kerbs meet
				local s, u = intersect(origin + a.left * a.hw, a.dir, origin - b.left * b.hw, b.dir)
				if s and u and s >= 0 and u >= 0 and s < MAX_TRIM * 2 and u < MAX_TRIM * 2 then
					corner.straight = false
					corner.sharp = true
					corner.ta = origin + a.dir * s + a.left * a.hw
					corner.tb = corner.ta
					a.leftTrim = math.max(a.leftTrim, s)
					b.rightTrim = math.max(b.rightTrim, u)
				end
			end
		end
		table.insert(corners, corner)
	end
	for _, e in ends do
		e.trim = math.max(e.trim, e.leftTrim, e.rightTrim) + 1
	end
	return corners
end

-- The edges of a road's tarmac at `distance` from this end: (right, left) looking away from the junction
local function endEdges(e: End, distance: number): (Vector3, Vector3)
	local p, _, n = RoadKit.at(e.road.path, stationFor(e, distance))
	local left = n * e.sign
	return p - left * e.hw, p + left * e.hw
end

local function buildJunctionSurface(node: Node, corners: { Corner })
	local ring: { Vector3 } = {}
	local y = node.pos.Y
	for i, a in node.ends do
		local right, left = endEdges(a, a.trim)
		table.insert(ring, right)
		table.insert(ring, left)
		local corner = corners[i]
		if corner and not corner.straight then
			local b = corner.b
			local ta = Vector3.new((corner.ta :: Vector3).X, y, (corner.ta :: Vector3).Z)
			local tb = Vector3.new((corner.tb :: Vector3).X, y, (corner.tb :: Vector3).Z)
			if a.leftTrim < a.trim - 0.05 then
				table.insert(ring, ta)
			end
			if not corner.sharp then
				local arc = shortArc(corner.centre :: Vector3, ta, tb, y)
				for k = 2, #arc - 1 do
					table.insert(ring, arc[k])
				end
			end
			if b.rightTrim < b.trim - 0.05 then
				table.insert(ring, tb)
			end
		end
	end
	local limit = 0
	for _, e in node.ends do
		limit = math.max(limit, e.road.limit)
	end
	setLimit(RoadKit.fan(node.pos, ring, ROAD), limit)
	local reach = 0
	for _, p in ring do
		reach = math.max(reach, (flat(p) - flat(node.pos)).Magnitude)
	end
	node.reach = reach
end

-- Pavement round each rounded corner, joining the pavements of the two roads
local function buildCornerPavements(node: Node, corners: { Corner })
	if node.pos.Y > 1 + ROAD_TOP then
		return
	end
	for _, corner in corners do
		if corner.straight or corner.sharp then
			continue
		end
		local a, b = corner.a, corner.b
		local widthA = if a.road.side == "pavement" then a.road.sideWidth else 0
		local widthB = if b.road.side == "pavement" then b.road.sideWidth else 0
		local width = math.min(math.max(widthA, widthB), corner.radius - 1)
		if width <= 0 then
			continue
		end
		local y = node.pos.Y
		local ta, tb = corner.ta :: Vector3, corner.tb :: Vector3
		local points = shortArc(corner.centre :: Vector3, Vector3.new(ta.X, y, ta.Z), Vector3.new(tb.X, y, tb.Z), y)
		RoadKit.strip(points, RoadKit.normalsFor(points), -width, 0, PAVEMENT, KERB)
	end
end

-- Roundabouts --------------------------------------------------------------------------------

type Fillet = { centre: Vector3, onRoad: Vector3, onCircle: Vector3 }
type RoundaboutEnd = { e: End, left: Fillet, right: Fillet }

local function solveRoundabout(node: Node): { RoundaboutEnd }
	local origin = node.pos
	local outer = node.radius
	local out: { RoundaboutEnd } = {}
	for _, e in node.ends do
		local width = if e.road.side == "pavement" then e.road.sideWidth else 0
		local radius = math.max(18, width + 3)
		local hw = math.min(e.hw, outer - 4)
		local along = math.sqrt(math.max(0, (outer + radius) ^ 2 - (hw + radius) ^ 2))
		local function fillet(side: number): Fillet
			local centre = origin + e.dir * along + e.left * side * (hw + radius)
			local onRoad = origin + e.dir * along + e.left * side * hw
			local onCircle = origin + flat(centre - origin).Unit * outer
			return { centre = centre, onRoad = onRoad, onCircle = onCircle }
		end
		e.trim = along + 1
		e.leftTrim, e.rightTrim = along, along
		table.insert(out, { e = e, left = fillet(1), right = fillet(-1) })
	end
	return out
end

local function buildRoundabout(node: Node, ends: { RoundaboutEnd })
	local y = node.pos.Y
	local limit = 0
	for _, info in ends do
		limit = math.max(limit, info.e.road.limit)
	end
	-- The circle of tarmac, a touch lower than the roads so the two never flicker
	local disc = cylinder(node.radius, 2, node.pos - Vector3.new(0, 0.05, 0), C.Asphalt, Enum.Material.Asphalt)
	disc:SetAttribute("SpeedLimit", limit)
	-- The island: a kerb ring, filled with real grass (Terrain), which looks better than a grassy part
	cylinder(node.island + 0.6, KERB + 1.5, node.pos + Vector3.new(0, KERB - 0.1, 0), C.Kerb, Enum.Material.Concrete)
	-- A low grassy mound that rises a little above the kerb. Terrain needs at least 4 studs of height to
	-- fill anything, so most of this sits hidden below the road.
	Workspace.Terrain:FillCylinder(CFrame.new(node.pos + Vector3.new(0, KERB - 2.1, 0)), 6, node.island - 0.4, Enum.Material.Grass)
	-- On stilts if it's above the ground (motorway junctions)
	if y > 1 + ROAD_TOP then
		cylinder(node.radius - 1, y - 2, node.pos - Vector3.new(0, 2, 0), PILLAR_COLOUR, Enum.Material.Concrete)
	end

	-- Where each road opens out into the circle
	for _, info in ends do
		local e = info.e
		local right, left = endEdges(e, e.trim)
		local leftChain = { left, Vector3.new(info.left.onRoad.X, y, info.left.onRoad.Z) }
		for _, p in shortArc(info.left.centre, info.left.onRoad, info.left.onCircle, y) do
			table.insert(leftChain, p)
		end
		local rightChain = { right, Vector3.new(info.right.onRoad.X, y, info.right.onRoad.Z) }
		for _, p in shortArc(info.right.centre, info.right.onRoad, info.right.onCircle, y) do
			table.insert(rightChain, p)
		end
		local count = math.max(#leftChain, #rightChain, 6)
		setLimit(RoadKit.between(RoadKit.resample(rightChain, count), RoadKit.resample(leftChain, count), ROAD), limit)
	end

	-- Kerb, pavement (or a parapet on stilts) round the outside, between each pair of roads
	table.sort(ends, function(p, q)
		return p.e.angle < q.e.angle
	end)
	local raised = y > 1 + ROAD_TOP
	for i, info in ends do
		local nextInfo = ends[i % #ends + 1]
		local a, b = info.e, nextInfo.e
		local width = math.max(if a.road.side == "pavement" then a.road.sideWidth else 0, if b.road.side == "pavement" then b.road.sideWidth else 0)
		local points: { Vector3 } = {}
		for _, p in shortArc(info.left.centre, info.left.onRoad, info.left.onCircle, y) do
			table.insert(points, p)
		end
		-- Round the circle the way that doesn't cross either road (clockwise on the map)
		local from = math.atan2(info.left.onCircle.Z - node.pos.Z, info.left.onCircle.X - node.pos.X)
		local to = math.atan2(nextInfo.right.onCircle.Z - node.pos.Z, nextInfo.right.onCircle.X - node.pos.X)
		local sweep = (from - to) % (2 * math.pi)
		if #ends == 1 then
			sweep = 2 * math.pi - 0.01
		else
			-- When two roads come in close together their kerb curves overlap, and the pavement would go the
			-- long way round, straight across every other road's entrance. Leave it out instead.
			local gap = (math.atan2(a.dir.Z, a.dir.X) - math.atan2(b.dir.Z, b.dir.X)) % (2 * math.pi)
			if sweep > gap + 0.3 then
				continue
			end
		end
		local circle = RoadKit.arc(Vector3.new(node.pos.X, y, node.pos.Z), node.radius, from, from - sweep)
		for k = 2, #circle - 1 do
			table.insert(points, circle[k])
		end
		for _, p in shortArc(nextInfo.right.centre, nextInfo.right.onCircle, nextInfo.right.onRoad, y) do
			table.insert(points, p)
		end
		local normals = RoadKit.normalsFor(points)
		if raised then
			RoadKit.parapet(RoadKit.offset(points, normals, -0.6), 3, 2, 1.2, PARAPET_COLOUR, Enum.Material.Concrete)
		elseif width > 0 then
			RoadKit.strip(points, normals, -math.min(width, 17), 0, PAVEMENT, KERB)
		end
	end

	-- Lane line round the middle of big roundabouts
	local ring = node.radius - node.island
	if ring >= 24 then
		local middle = node.island + ring / 2
		local count = math.floor(2 * math.pi * middle / 14)
		for k = 0, count - 1 do
			local angle = k / count * 2 * math.pi
			local at = node.pos + Vector3.new(math.cos(angle) * middle, 0, math.sin(angle) * middle)
			RoadKit.mark(at, Vector3.new(-math.sin(angle), 0, math.cos(angle)), 0.45, 6, C.White)
		end
	end
	node.reach = node.radius + 4
end

-- Markings at the end of a road -------------------------------------------------------------

-- Which offsets (left is positive) carry traffic towards this end of the road
local function incomingSpan(e: End): (number?, number?)
	local road = e.road
	local p = road.profile
	if p.oneway then
		if e.atStart then
			return nil, nil -- one-way roads only arrive at their far end
		end
		return -road.hw + p.edge, road.hw - p.edge
	end
	local inner = p.res / 2
	local outer = road.hw - p.edge - p.shoulder
	-- Traffic heading towards this end drives on its left, which is the road's right at the start
	if e.atStart then
		return -outer, -inner
	end
	return inner, outer
end

local function acrossLine(e: End, distance: number, from: number, to: number, dashed: boolean, thick: number)
	local p, _, n = RoadKit.at(e.road.path, stationFor(e, distance))
	if dashed then
		local o = from + 1.3
		while o + 0.8 <= to do
			RoadKit.mark(p + n * o, n, 0.5 * thick, 1.6, C.White)
			o += 2.6
		end
	else
		RoadKit.mark(p + n * ((from + to) / 2), n, 0.7 * thick, to - from - 0.6, C.White)
	end
end

local function giveWay(e: End, distance: number)
	local from, to = incomingSpan(e)
	if not from or not to then
		return
	end
	acrossLine(e, distance + 0.6, from, to, true, 1)
	acrossLine(e, distance + 1.8, from, to, true, 1)
	-- The upside-down triangle warning drivers before the line
	if e.road.profile.rank <= 2 and e.road.path.length > e.trim + 60 then
		local p, _, n = RoadKit.at(e.road.path, stationFor(e, distance + 22))
		local middle = (from + to) / 2
		local towards = flat(e.dir) * -1 -- the direction traffic is going
		local tip = p + n * middle + towards * 5
		local baseCentre = p + n * middle - towards * 9
		RoadKit.paintTriangle(tip, baseCentre + n * 3.2, baseCentre - n * 3.2, C.White)
	end
end

local function stopLine(e: End, distance: number)
	local from, to = incomingSpan(e)
	if not from or not to then
		return
	end
	acrossLine(e, distance + 1, from, to, false, 1)
end

-- Picks the main road through a junction: the two roads that line up best, biggest first
local function markMajor(node: Node)
	local best, bestScore = nil, -math.huge
	for i = 1, #node.ends do
		for j = i + 1, #node.ends do
			local a, b = node.ends[i], node.ends[j]
			local straightness = -a.dir:Dot(b.dir)
			local score = straightness + (a.road.profile.rank + b.road.profile.rank) * 0.3
			if straightness > 0.5 and score > bestScore then
				best, bestScore = { a, b }, score
			end
		end
	end
	if best then
		best[1].major = true
		best[2].major = true
	end
end

-- A spot on the pavement or verge to the left of the traffic coming in at this end, `distance` from the junction,
-- facing that traffic (where give way signs and traffic lights stand)
local function roadsideSpot(e: End, distance: number, extra: number?): (Vector3, Vector3)
	local p, _, n = RoadKit.at(e.road.path, stationFor(e, distance))
	local side = if e.atStart then -1 else 1
	local base = p + n * side * (e.hw + (extra or 1.6))
	return Vector3.new(base.X, base.Y + KERB, base.Z), e.dir
end

-- White arrows in the lanes coming up to a set of traffic lights
local function laneArrows(e: End)
	local from, to = incomingSpan(e)
	if not from or not to or e.road.path.length < e.trim + 60 then
		return
	end
	local p = e.road.profile
	local lanes = p.lanes
	-- The arrow sits in the moving lanes, not in the parking strip along the kerb
	local inner = math.min(math.abs(from), math.abs(to))
	local sign = if from < 0 then -1 else 1
	for lane = 1, lanes do
		local offset = sign * (inner + p.lane * (lane - 0.5))
		local at, _, n = RoadKit.at(e.road.path, stationFor(e, e.trim + 22))
		TownProps.laneArrow(at + n * offset, -e.dir)
	end
end

local function trafficLights(node: Node)
	-- Opposite roads change together
	local ends = node.ends
	local paired: { [End]: boolean } = {}
	local axes = { "NS", "EW" }
	local which = 1
	for _, a in ends do
		if paired[a] then
			continue
		end
		local partner, best = nil, 0.5
		for _, b in ends do
			if b ~= a and not paired[b] and -a.dir:Dot(b.dir) > best then
				partner, best = b, -a.dir:Dot(b.dir)
			end
		end
		a.axis = axes[which]
		paired[a] = true
		if partner then
			partner.axis = axes[which]
			paired[partner] = true
		end
		which = which % 2 + 1
	end
	for _, e in ends do
		local from, to = incomingSpan(e)
		if not from or not to then
			continue
		end
		local p, _, n = RoadKit.at(e.road.path, stationFor(e, e.trim + 3))
		-- On the pavement to the left of the traffic coming in
		local side = if e.atStart then -1 else 1
		local base = p + n * side * (e.hw + 1.6)
		TownProps.trafficLight(TownKit.facing(Vector3.new(base.X, base.Y - ROAD_TOP, base.Z), e.dir), node.id, e.axis or "NS")
	end
end

-- Roads -------------------------------------------------------------------------------------

-- Splits [s0, s1] into the pieces on one side that aren't in a gap
local function sidePieces(road: Road, side: number, s0: number, s1: number): { { number } }
	local cuts = { { s0, s1 } }
	local function cut(c0: number, c1: number)
		local out = {}
		for _, piece in cuts do
			if c1 <= piece[1] or c0 >= piece[2] then
				table.insert(out, piece)
			else
				if c0 > piece[1] then
					table.insert(out, { piece[1], c0 })
				end
				if c1 < piece[2] then
					table.insert(out, { c1, piece[2] })
				end
			end
		end
		cuts = out
	end
	for _, gap in road.gaps do
		if gap[1] == side then
			cut(gap[2], gap[3])
		end
	end
	for _, layby in road.laybys do
		if layby[1] == side then
			cut(layby[2], layby[3])
		end
	end
	return cuts
end

local function centreLines(road: Road, s0: number, s1: number)
	local p = road.profile
	local path = road.path
	if p.oneway then
		local inside = road.hw - p.edge - 0.6
		RoadKit.pathLine(path, s0, s1, inside, 0.45, C.White)
		RoadKit.pathLine(path, s0, s1, -inside, 0.45, C.White)
		return
	end
	if p.res == 0 then
		local dash, gap = 6, 6
		if road.kind == "street" or road.kind == "lane" or road.kind == "back" then
			dash, gap = 3, 9
		elseif road.kind == "high" then
			dash, gap = 4, 7
		end
		-- Long warning dashes just before junctions
		local hazardStart = if road.a.kind == "attach" or road.a.kind == "end" or road.a.kind == "join" then s0 else s0 + HAZARD_LENGTH
		local hazardEnd = if road.b.kind == "attach" or road.b.kind == "end" or road.b.kind == "join" then s1 else s1 - HAZARD_LENGTH
		if hazardEnd - hazardStart > 30 then
			RoadKit.dashes(path, s0, hazardStart, 0, 0.5, 6, 2, C.White)
			RoadKit.dashes(path, hazardStart, hazardEnd, 0, 0.5, dash, gap, C.White)
			RoadKit.dashes(path, hazardEnd, s1, 0, 0.5, 6, 2, C.White)
		else
			RoadKit.dashes(path, s0, s1, 0, 0.5, 6, 2, C.White)
		end
		if p.edge > 0 then
			for _, side in { 1, -1 } do
				for _, piece in sidePieces(road, side, s0, s1) do
					RoadKit.pathLine(path, piece[1], piece[2], side * (road.hw - p.edge - 0.4), 0.4, C.White)
				end
			end
		end
		-- Double yellow lines (no parking) along the kerbs near each junction. The parking strips themselves
		-- aren't marked, like in BVS, which keeps the streets clean (and saves thousands of parts).
		local parking = p.parking or 0
		if parking > 0 then
			local near = math.min(55, (s1 - s0) / 2)
			for _, range in { { s0, s0 + near }, { s1 - near, s1 } } do
				for _, side in { 1, -1 } do
					for _, inset in { 0.9, 1.6 } do
						RoadKit.pathLine(path, range[1], range[2], side * (road.hw - inset), 0.32, C.Yellow)
					end
				end
			end
		end
		return
	end
	-- Dual carriageways and the motorway: each side has its own lanes
	for _, side in { 1, -1 } do
		local inner = p.res / 2
		RoadKit.pathLine(path, s0, s1, side * (inner + 0.6), 0.45, C.White)
		for k = 1, p.lanes - 1 do
			RoadKit.dashes(path, s0, s1, side * (inner + p.lane * k), 0.45, 9, 14, C.White)
		end
		local laneEdge = inner + p.lanes * p.lane
		local width = if p.shoulder > 0 then 0.8 else 0.45
		local offset = if p.shoulder > 0 then laneEdge else road.hw - p.edge - 0.5
		-- Solid along the edge, broken where slip roads join or a layby opens
		local covered = s0
		for _, piece in sidePieces(road, side, s0, s1) do
			if piece[1] > covered + 1 then
				RoadKit.dashes(path, covered, piece[1], side * offset, width, 6, 6, C.White)
			end
			RoadKit.pathLine(path, piece[1], piece[2], side * offset, width, C.White)
			covered = piece[2]
		end
		if s1 > covered + 1 then
			RoadKit.dashes(path, covered, s1, side * offset, width, 6, 6, C.White)
		end
	end
end

local function buildLayby(road: Road, layby: { number })
	local side, s0, s1 = layby[1], layby[2], layby[3]
	local depth, taper = 11, 30
	local inner, outer = {}, {}
	local s = s0
	while true do
		local p, _, n = RoadKit.at(road.path, s)
		local into = depth
		if s < s0 + taper then
			into = depth * (s - s0) / taper
		elseif s > s1 - taper then
			into = depth * (s1 - s) / taper
		end
		table.insert(inner, p + n * side * road.hw)
		table.insert(outer, p + n * side * (road.hw + math.max(into, 0.05)))
		if s >= s1 then
			break
		end
		s = math.min(s + 10, s1)
	end
	if side > 0 then
		setLimit(RoadKit.between(inner, outer, ROAD), road.limit)
	else
		setLimit(RoadKit.between(outer, inner, ROAD), road.limit)
	end
	-- A blue "P" sign in the middle
	local p, direction, n = RoadKit.at(road.path, (s0 + s1) / 2)
	local post = p + n * side * (road.hw + depth + 3)
	TownKit.post(0.3, 7, Vector3.new(post.X, post.Y - ROAD_TOP, post.Z), C.LampGrey, Enum.Material.Metal)
	local facing = if side > 0 then -direction else direction
	local sign = TownKit.detail(Vector3.new(2.4, 2.4, 0.15), TownKit.facing(post + Vector3.new(0, 7, 0), facing), Color3.fromRGB(20, 70, 160))
	TownKit.text(sign, Enum.NormalId.Front, "P", Color3.new(1, 1, 1))
end

local function groundBelow(ground: (number, number) -> number, p: Vector3): number
	return ground(p.X, p.Z)
end

local function buildRaised(road: Road, ground: (number, number) -> number, isRoad: (number, number) -> boolean)
	local path = road.path
	local s0, s1 = road.startTrim, path.length - road.endTrim
	if s1 - s0 < 1 then
		return
	end
	-- Find the stretches above the ground
	local raised: { { number } } = {}
	local currentStretch: { number }? = nil
	local s = s0
	while s <= s1 do
		local p, _, n = RoadKit.at(path, s)
		local height = p.Y - ROAD_TOP
		local above = math.max(
			height - groundBelow(ground, p),
			height - groundBelow(ground, p + n * road.hw),
			height - groundBelow(ground, p - n * road.hw)
		)
		if above > 1.2 then
			local stretch = currentStretch or { math.max(s0, s - 8), s }
			if not currentStretch then
				table.insert(raised, stretch)
				currentStretch = stretch
			end
			stretch[2] = math.min(s1, s + 8)
		else
			currentStretch = nil
		end
		if s >= s1 then
			break
		end
		s = math.min(s + 8, s1)
	end
	road.raised = raised

	local outer = road.hw + (if road.side == "pavement" then road.sideWidth else 0)
	local walkLift = if road.side == "pavement" then KERB else 0
	for _, stretch in raised do
		local points, normals = RoadKit.slice(path, stretch[1], stretch[2])
		for _, side in { 1, -1 } do
			-- Parapet walls along both edges
			local edge = RoadKit.offset(points, normals, side * (outer + 0.6), walkLift)
			RoadKit.parapet(edge, 3, 2.5 + walkLift, 1.2, PARAPET_COLOUR, Enum.Material.Concrete)
		end
		-- Pillars, or solid walls where the road is only a little way up
		local spacing = 60
		local distance = stretch[1] + 10
		while distance < stretch[2] - 5 do
			local p, direction, n = RoadKit.at(path, distance)
			local bottom = p.Y - 2
			local groundY = groundBelow(ground, p)
			local inWater = groundY < -5
			if bottom - groundY > 6 then
				local positions: { number } = if road.hw > 22 then { -road.hw * 0.55, road.hw * 0.55 } else { 0 }
				for _, offset in positions do
					local at = p + n * offset
					if inWater or not isRoad(at.X, at.Z) then
						local height = bottom - groundY
						local colour = if inWater then C.Stone else PILLAR_COLOUR
						local material = if inWater then Enum.Material.Limestone else Enum.Material.Concrete
						local size = if inWater then Vector3.new(road.hw * 2 + 6, height, 10) else Vector3.new(5, height, 7)
						if inWater and offset ~= positions[1] then
							continue
						end
						local centre = if inWater then p else at
						TownKit.box(size, CFrame.lookAt(Vector3.new(centre.X, groundY + height / 2, centre.Z), Vector3.new(centre.X, groundY + height / 2, centre.Z) + direction), colour, material)
					end
				end
				distance += if inWater then 80 else spacing
			else
				distance += 8
			end
		end
		-- Low stretches (ramps) get side walls down to the ground instead of pillars
		for _, side in { 1, -1 } do
			local edge = RoadKit.offset(points, normals, side * (outer + 0.6), 0)
			for k = 2, #edge do
				local a, b = edge[k - 1], edge[k]
				local middle = (a + b) / 2
				local groundY = groundBelow(ground, middle)
				local drop = middle.Y - 2.5 - groundY
				if drop > 0.2 and drop < 7 and groundY > -5 then
					RoadKit.parapet({ a - Vector3.new(0, 2.5, 0), b - Vector3.new(0, 2.5, 0) }, 0, drop + 0.5, 1.4, PARAPET_COLOUR, Enum.Material.Concrete)
				end
			end
		end
	end
end

local function buildRoad(road: Road)
	local path = road.path
	local p = road.profile
	local s0, s1 = road.startTrim, path.length - road.endTrim
	if s1 - s0 < 0.5 then
		return
	end
	local points, normals = RoadKit.slice(path, s0, s1)
	local style = if road.kind == "motorway" then MOTORWAY_ROAD else ROAD
	setLimit(RoadKit.strip(points, normals, -road.hw, road.hw, style), road.limit)

	-- Central reservation: grass between kerbs on dual carriageways, a concrete barrier on the motorway
	if p.res > 0 and not p.oneway and s1 - s0 > 16 then
		local nose = 8
		local resPoints, resNormals = RoadKit.slice(path, s0 + nose, s1 - nose)
		if road.kind == "motorway" or road.kind == "westway" then
			RoadKit.strip(resPoints, resNormals, -p.res / 2, p.res / 2, CONCRETE, 0.25)
			RoadKit.parapet(resPoints, 2.6, 0, 1.2, PARAPET_COLOUR, Enum.Material.Concrete)
		else
			RoadKit.strip(resPoints, resNormals, -p.res / 2 + 0.4, p.res / 2 - 0.4, ISLAND, KERB)
			RoadKit.strip(resPoints, resNormals, -p.res / 2, -p.res / 2 + 0.4, CONCRETE, KERB - 0.05)
			RoadKit.strip(resPoints, resNormals, p.res / 2 - 0.4, p.res / 2, CONCRETE, KERB - 0.05)
			-- Keep-left bollards on both ends of the island, facing the traffic coming at them
			if road.a.kind ~= "attach" then
				local at, direction = RoadKit.at(path, s0 + nose + 1.5)
				TownProps.keepLeft(at + Vector3.new(0, KERB, 0), -direction)
			end
			if road.b.kind ~= "attach" then
				local at, direction = RoadKit.at(path, s1 - nose - 1.5)
				TownProps.keepLeft(at + Vector3.new(0, KERB, 0), direction)
			end
		end
	end

	-- Pavements
	if road.side == "pavement" then
		for _, side in { 1, -1 } do
			local from, to = road.sideFrom[side], road.sideTo[side]
			for _, piece in sidePieces(road, side, from, to) do
				local sidePoints, sideNormals = RoadKit.slice(path, piece[1], piece[2])
				local walkStyle = if road.kind == "high" then RED_PAVEMENT else PAVEMENT
				if side > 0 then
					RoadKit.strip(sidePoints, sideNormals, road.hw, road.hw + road.sideWidth, walkStyle, KERB)
				else
					RoadKit.strip(sidePoints, sideNormals, -road.hw - road.sideWidth, -road.hw, walkStyle, KERB)
				end
			end
		end
	end

	centreLines(road, s0, s1)
	for _, layby in road.laybys do
		buildLayby(road, layby)
	end

	-- Slip roads: a tapering wedge of tarmac where they leave or join the motorway
	if road.taper and road.taperFrom then
		local atStart = road.taper == "start"
		local q, _, n = RoadKit.at(path, if atStart then 0 else path.length)
		local from = Vector3.new((road.taperFrom :: Vector3).X, q.Y, (road.taperFrom :: Vector3).Z)
		setLimit(RoadKit.triangle(from, q - n * road.hw, q + n * road.hw, ROAD), road.limit)
	end
end

-- Building it all -----------------------------------------------------------------------------

local function minimapKind(kind: string): string
	if kind == "motorway" then
		return "motorway"
	elseif kind == "dual" or kind == "arterial" or kind == "westway" or kind == "slip" then
		return "dual"
	elseif kind == "street" or kind == "lane" or kind == "back" then
		return "side"
	end
	return "main"
end

-- `ground(x, z)` gives the height of the ground; `isRoad(x, z)` says whether a spot is already road
-- (LondonMap fills that in once the roads are down, so pillars don't stand in the middle of a road below).
function RoadNetwork.build(layout: any, ground: (number, number) -> number, isRoad: (number, number) -> boolean, onRoadsDown: ((Result) -> ())?): Result
	local profiles: { [string]: Profile } = layout.profiles
	local nodesById: { [string]: Node } = {}
	local nodes: { Node } = {}
	for _, info in layout.nodes do
		local node: Node = {
			id = info.id,
			pos = Vector3.new(info.x, (info.y or 0) + ROAD_TOP, info.z),
			kind = info.kind,
			radius = info.radius or 0,
			island = info.island or 0,
			name = info.name or "",
			ends = {},
			reach = 0,
		}
		nodesById[node.id] = node
		table.insert(nodes, node)
	end

	local roads: { Road } = {}
	local byId: { [string]: Road } = {}
	for _, info in layout.roads do
		local a, b = nodesById[info.a], nodesById[info.b]
		local controls = { a.pos }
		local lastY = a.pos.Y
		for _, v in info.via or {} do
			local y = if v[3] then v[3] + ROAD_TOP else lastY
			table.insert(controls, Vector3.new(v[1], y, v[2]))
			lastY = y
		end
		table.insert(controls, b.pos)
		local profile = profiles[info.profile]
		local hw = halfWidth(profile)
		local road: Road = {
			id = info.id,
			name = info.name or "",
			kind = info.profile,
			profile = profile,
			a = a,
			b = b,
			path = RoadKit.path(controls, info.radius),
			hw = hw,
			sideWidth = profile.sideWidth,
			side = profile.side,
			limit = profile.limit,
			startTrim = 0,
			endTrim = 0,
			sideFrom = {},
			sideTo = {},
			gaps = info.gaps or {},
			laybys = info.laybys or {},
			taper = info.taper,
			taperFrom = if info.taperFrom then Vector3.new(info.taperFrom[1], 0, info.taperFrom[2]) else nil,
			raised = {},
		}
		table.insert(roads, road)
		byId[road.id] = road
		for _, atStart in { true, false } do
			local node = if atStart then a else b
			local _, direction = RoadKit.at(road.path, if atStart then 0 else road.path.length)
			local dir = if atStart then direction else -direction
			local e: End = {
				road = road,
				node = node,
				atStart = atStart,
				sign = if atStart then 1 else -1,
				dir = dir,
				left = RoadKit.leftOf(dir),
				angle = math.atan2(-dir.X, -dir.Z),
				hw = hw,
				trim = 0,
				leftTrim = 0,
				rightTrim = 0,
				major = false,
			}
			table.insert(node.ends, e)
		end
	end

	-- Work out every junction first: how much each road loses at each end
	local cornersByNode: { [Node]: { Corner } } = {}
	local roundaboutsByNode: { [Node]: { RoundaboutEnd } } = {}
	for _, node in nodes do
		table.sort(node.ends, function(p, q)
			return p.angle < q.angle
		end)
		if node.kind == "roundabout" then
			roundaboutsByNode[node] = solveRoundabout(node)
		elseif node.kind == "attach" or node.kind == "end" then
			for _, e in node.ends do
				e.trim, e.leftTrim, e.rightTrim = 0, 0, 0
			end
		else
			cornersByNode[node] = solveJunction(node)
		end
	end
	for _, node in nodes do
		for _, e in node.ends do
			local road = e.road
			-- Pavements stop where the kerb starts to curve: the road's left at its start is the end's left
			local leftSide = if e.atStart then 1 else -1
			if e.atStart then
				road.startTrim = e.trim
				road.sideFrom[leftSide] = e.leftTrim
				road.sideFrom[-leftSide] = e.rightTrim
			else
				road.endTrim = e.trim
				road.sideTo[leftSide] = road.path.length - e.leftTrim
				road.sideTo[-leftSide] = road.path.length - e.rightTrim
			end
		end
	end

	-- Roads, then junctions
	for _, road in roads do
		buildRoad(road)
	end
	for _, node in nodes do
		if node.kind == "roundabout" then
			buildRoundabout(node, roundaboutsByNode[node])
		elseif node.kind == "end" then
			local e = node.ends[1]
			if e then
				local disc = cylinder(e.hw + 7, 2, node.pos - Vector3.new(0, 0.05, 0), C.Asphalt, Enum.Material.Asphalt)
				disc:SetAttribute("SpeedLimit", e.road.limit)
				node.reach = e.hw + 7
			end
		elseif node.kind ~= "attach" then
			local corners = cornersByNode[node]
			buildJunctionSurface(node, corners)
			buildCornerPavements(node, corners)
		end
	end

	local result: Result = { roads = roads, nodes = nodes, byId = byId, minimap = {} }
	if onRoadsDown then
		onRoadsDown(result)
	end

	-- Markings and signals at junctions
	for _, node in nodes do
		if node.kind == "lights" then
			for _, e in node.ends do
				stopLine(e, e.trim)
				laneArrows(e)
			end
			trafficLights(node)
		elseif node.kind == "junction" then
			markMajor(node)
			local busiest = 0
			for _, e in node.ends do
				busiest = math.max(busiest, e.road.profile.rank)
			end
			for _, e in node.ends do
				if not e.major then
					giveWay(e, e.trim)
					-- A give way sign where a side street joins a bigger road
					if e.road.profile.rank < busiest and e.road.path.length > e.trim + 30 then
						local at, facing = roadsideSpot(e, e.trim + 4)
						TownProps.sign("GiveWay", at, facing)
					end
				end
			end
		elseif node.kind == "mini" then
			for _, e in node.ends do
				giveWay(e, e.trim)
				if e.road.path.length > e.trim + 50 then
					local at, facing = roadsideSpot(e, e.trim + 30)
					TownProps.sign("MiniRoundabout", at, facing)
				end
			end
			local dot = cylinder(4, 0.08, node.pos + Vector3.new(0, 0.06, 0), C.White, Enum.Material.SmoothPlastic)
			dot.CanCollide = false
			dot.CastShadow = false
		elseif node.kind == "roundabout" then
			for _, e in node.ends do
				giveWay(e, node.radius + 0.5)
				-- No Entry at the top of each motorway exit, so nobody drives down it the wrong way
				if e.road.taper == "start" and not e.atStart then
					for _, side in { -1, 1 } do
						local p, _, n = RoadKit.at(e.road.path, stationFor(e, e.trim + 3))
						local at = p + n * side * (e.hw + 2)
						TownProps.sign("NoEntry", Vector3.new(at.X, at.Y, at.Z), -e.dir)
					end
				end
			end
		end
	end

	-- Bridges, flyovers and ramps
	for _, road in roads do
		buildRaised(road, ground, isRoad)
	end

	-- The minimap: each road as straight lines, joining up the little pieces of each curve
	for _, road in roads do
		local kind = minimapKind(road.kind)
		local width = math.round(road.hw * 2)
		local points = road.path.points
		local function line(a: Vector3, b: Vector3)
			table.insert(result.minimap, { "l" :: any, math.round(a.X), math.round(a.Z), math.round(b.X), math.round(b.Z), width, kind })
		end
		local anchor = points[1]
		local anchorDirection: Vector3? = nil
		for k = 2, #points do
			local piece = flat(points[k] - points[k - 1])
			if piece.Magnitude > 0.01 then
				local direction = piece.Unit
				local start = anchorDirection or direction
				if start:Dot(direction) < math.cos(math.rad(10)) or flat(points[k] - anchor).Magnitude > 300 then
					if flat(points[k - 1] - anchor).Magnitude > 0.5 then
						line(anchor, points[k - 1])
						anchor = points[k - 1]
					end
					start = direction
				end
				anchorDirection = start
			end
		end
		line(anchor, points[#points])
	end
	for _, node in nodes do
		if node.kind == "roundabout" then
			table.insert(result.minimap, { "c" :: any, math.round(node.pos.X), math.round(node.pos.Z), node.radius, "main" })
		end
	end
	return result
end

return RoadNetwork
