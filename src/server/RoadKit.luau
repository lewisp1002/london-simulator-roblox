-- Geometry for the roads: smooth paths through control points, strips of road that follow them,
-- triangles (made from two wedges, so curves have no gaps), walls and painted lines.
-- RoadNetwork uses it to build every road, junction and roundabout; LondonMap uses it for the river.
-- A "path" is a list of points along the middle of a road. "Offsets" are distances to the left of the
-- path (negative is right), measured flat across it.

local TownKit = require(script.Parent.TownKit)

local RoadKit = {}

export type Path = {
	points: { Vector3 }, -- points along the middle, with heights
	dists: { number }, -- distance along the path at each point (measured flat)
	normals: { Vector3 }, -- flat unit vector pointing left at each point
	length: number,
	stations: { number }, -- where each control point sits along the path
}

local MAX_TURN_STEP = math.rad(6) -- curves are cut into pieces of at most this angle
local MAX_PIECE = 1000 -- straights are cut into pieces no longer than this (parts can't be over 2048 studs)

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The flat direction 90 degrees to the left of `direction` (x east, z south)
function RoadKit.leftOf(direction: Vector3): Vector3
	return Vector3.new(direction.Z, 0, -direction.X)
end

local leftOf = RoadKit.leftOf

-- A path through `controls` with its corners rounded off to `radius`. Heights go in a straight line
-- from one control point to the next. tools/london_layout.py does exactly the same sums, so distances
-- along the path (for slip roads and laybys) match.
function RoadKit.path(controls: { Vector3 }, radius: number): Path
	local flatPoints: { Vector3 } = { flat(controls[1]) }
	local controlAt: { number } = { 1 }
	for i = 2, #controls - 1 do
		local a, b, c = flat(controls[i - 1]), flat(controls[i]), flat(controls[i + 1])
		local d1, d2 = (b - a).Unit, (c - b).Unit
		local turn = math.acos(math.clamp(d1:Dot(d2), -1, 1))
		if turn < math.rad(0.5) then
			table.insert(flatPoints, b)
			table.insert(controlAt, #flatPoints)
		else
			local t = radius * math.tan(turn / 2)
			local limit = 0.48 * math.min((b - a).Magnitude, (c - b).Magnitude)
			local r = radius
			if t > limit then
				t = limit
				r = t / math.tan(turn / 2)
			end
			local start = b - d1 * t
			local finish = b + d2 * t
			local side = leftOf(d1)
			local towards = if side:Dot(d2) > 0 then side else -side
			local centre = start + towards * r
			local a0 = math.atan2(start.Z - centre.Z, start.X - centre.X)
			local a1 = math.atan2(finish.Z - centre.Z, finish.X - centre.X)
			local sweep = a1 - a0
			while sweep > math.pi do
				sweep -= 2 * math.pi
			end
			while sweep < -math.pi do
				sweep += 2 * math.pi
			end
			local steps = math.max(1, math.ceil(math.abs(sweep) / MAX_TURN_STEP))
			table.insert(flatPoints, start)
			local middle: number? = nil
			for k = 1, steps - 1 do
				local angle = a0 + sweep * k / steps
				table.insert(flatPoints, Vector3.new(centre.X + r * math.cos(angle), 0, centre.Z + r * math.sin(angle)))
				if k == steps // 2 then
					middle = #flatPoints
				end
			end
			table.insert(flatPoints, finish)
			table.insert(controlAt, middle or #flatPoints)
		end
	end
	table.insert(flatPoints, flat(controls[#controls]))
	table.insert(controlAt, #flatPoints)

	local dists = { 0 }
	for k = 2, #flatPoints do
		dists[k] = dists[k - 1] + (flatPoints[k] - flatPoints[k - 1]).Magnitude
	end
	local stations = {}
	for i, index in controlAt do
		stations[i] = dists[index]
	end

	-- Cut long straights into shorter pieces (doesn't change any distances)
	local points: { Vector3 } = { flatPoints[1] }
	local cutDists = { 0 }
	for k = 2, #flatPoints do
		local from, to = flatPoints[k - 1], flatPoints[k]
		local pieces = math.ceil((to - from).Magnitude / MAX_PIECE)
		for j = 1, pieces do
			table.insert(points, from:Lerp(to, j / pieces))
			table.insert(cutDists, dists[k - 1] + (dists[k] - dists[k - 1]) * j / pieces)
		end
	end

	-- Heights: straight lines between control points
	local function heightAt(s: number): number
		for i = 2, #stations do
			if s <= stations[i] or i == #stations then
				local s0, s1 = stations[i - 1], stations[i]
				local f = if s1 - s0 < 1e-6 then 0 else math.clamp((s - s0) / (s1 - s0), 0, 1)
				return controls[i - 1].Y + (controls[i].Y - controls[i - 1].Y) * f
			end
		end
		return controls[#controls].Y
	end
	for k, p in points do
		points[k] = Vector3.new(p.X, heightAt(cutDists[k]), p.Z)
	end

	-- Left normals, averaging the two pieces either side of each point so strips join up neatly
	local normals: { Vector3 } = {}
	for k = 1, #points do
		local before = if k > 1 then flat(points[k] - points[k - 1]) else nil
		local after = if k < #points then flat(points[k + 1] - points[k]) else nil
		local direction: Vector3
		if before and after and before.Magnitude > 1e-6 and after.Magnitude > 1e-6 then
			direction = before.Unit + after.Unit
			if direction.Magnitude < 1e-6 then
				direction = after
			end
		else
			direction = (after or before) :: Vector3
		end
		normals[k] = leftOf(direction.Unit)
	end

	return { points = points, dists = cutDists, normals = normals, length = cutDists[#cutDists], stations = stations }
end

-- Which piece of the path distance `s` falls in, and how far through it (0 to 1)
local function locate(path: Path, s: number): (number, number)
	local dists = path.dists
	local low, high = 1, #dists
	if s <= 0 then
		return 2, 0
	end
	if s >= path.length then
		return #dists, 1
	end
	while high - low > 1 do
		local mid = (low + high) // 2
		if dists[mid] <= s then
			low = mid
		else
			high = mid
		end
	end
	local span = dists[high] - dists[low]
	return high, if span < 1e-9 then 0 else (s - dists[low]) / span
end

-- The point, flat direction of travel and left normal at distance `s` along the path
function RoadKit.at(path: Path, s: number): (Vector3, Vector3, Vector3)
	local k, f = locate(path, s)
	local a, b = path.points[k - 1], path.points[k]
	local direction = flat(b - a)
	direction = if direction.Magnitude > 1e-6 then direction.Unit else Vector3.zAxis
	local normal = path.normals[k - 1]:Lerp(path.normals[k], f)
	normal = if normal.Magnitude > 1e-6 then normal.Unit else leftOf(direction)
	return a:Lerp(b, f), direction, normal
end

-- The points and normals between distances s0 and s1, including the exact ends
function RoadKit.slice(path: Path, s0: number, s1: number): ({ Vector3 }, { Vector3 })
	local points, normals = {}, {}
	if s1 - s0 < 0.05 then
		return points, normals
	end
	local p0, _, n0 = RoadKit.at(path, s0)
	table.insert(points, p0)
	table.insert(normals, n0)
	for k = 1, #path.points do
		local d = path.dists[k]
		if d > s0 + 0.05 and d < s1 - 0.05 then
			table.insert(points, path.points[k])
			table.insert(normals, path.normals[k])
		end
	end
	local p1, _, n1 = RoadKit.at(path, s1)
	table.insert(points, p1)
	table.insert(normals, n1)
	return points, normals
end

-- Normals for any list of points (for kerbs round corners, river banks and so on)
function RoadKit.normalsFor(points: { Vector3 }): { Vector3 }
	local normals = {}
	for k = 1, #points do
		local before = if k > 1 then flat(points[k] - points[k - 1]) else nil
		local after = if k < #points then flat(points[k + 1] - points[k]) else nil
		local direction: Vector3
		if before and after and before.Magnitude > 1e-6 and after.Magnitude > 1e-6 then
			direction = before.Unit + after.Unit
			if direction.Magnitude < 1e-6 then
				direction = after
			end
		else
			direction = (after or before or Vector3.zAxis) :: Vector3
		end
		normals[k] = leftOf(if direction.Magnitude > 1e-6 then direction.Unit else Vector3.zAxis)
	end
	return normals
end

-- Points `offset` studs to the left of each point (raised by `lift`)
function RoadKit.offset(points: { Vector3 }, normals: { Vector3 }, offset: number, lift: number?): { Vector3 }
	local out = {}
	local up = Vector3.new(0, lift or 0, 0)
	for k, p in points do
		out[k] = p + normals[k] * offset + up
	end
	return out
end

-- Points along a circle round `centre`, from angle a0 to a1 (radians, measured with math.atan2(z, x))
function RoadKit.arc(centre: Vector3, radius: number, a0: number, a1: number, maxStep: number?): { Vector3 }
	local sweep = a1 - a0
	local steps = math.max(1, math.ceil(math.abs(sweep) / (maxStep or MAX_TURN_STEP)))
	local points = {}
	for k = 0, steps do
		local angle = a0 + sweep * k / steps
		table.insert(points, Vector3.new(centre.X + radius * math.cos(angle), centre.Y, centre.Z + radius * math.sin(angle)))
	end
	return points
end

-- Surfaces ---------------------------------------------------------------------------------

type Style = { colour: Color3, material: Enum.Material, thickness: number, collide: boolean? }

local function wedge(size: Vector3, cframe: CFrame, style: Style): BasePart
	local part = TownKit.box(size, cframe, style.colour, style.material, "WedgePart")
	if style.collide == false then
		part.CanCollide = false
	end
	return part
end

-- A flat-topped slab in the shape of triangle a-b-c, made from two wedges. The top is exactly on the
-- triangle; the slab hangs `thickness` below it.
function RoadKit.triangle(a: Vector3, b: Vector3, c: Vector3, style: Style, made: { BasePart }?): { BasePart }
	local out = made or {}
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-4 or bc.Magnitude < 1e-3 then
		return out
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.01 then
		return out
	end
	local top = if right.Y >= 0 then right else -right
	local shift = -top * style.thickness / 2
	local length1 = math.abs(ab:Dot(back))
	local length2 = math.abs(ac:Dot(back))
	if length1 > 0.01 then
		table.insert(out, wedge(Vector3.new(style.thickness, height, length1), CFrame.fromMatrix((a + b) / 2 + shift, right, up, back), style))
	end
	if length2 > 0.01 then
		table.insert(out, wedge(Vector3.new(style.thickness, height, length2), CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back), style))
	end
	return out
end

-- A slab with corners p1, p2, p3, p4 in order round the edge. Rectangles are one part; anything else is
-- cut into two triangles.
function RoadKit.quad(p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3, style: Style, made: { BasePart }?): { BasePart }
	local out = made or {}
	local across, along = p2 - p1, p4 - p1
	local width, length = across.Magnitude, along.Magnitude
	if width > 0.01 and length > 0.01 then
		local square = math.abs(across.Unit:Dot(along.Unit)) < 0.002 and ((p1 + across + along) - p3).Magnitude < 0.02
		if square then
			local normal = across:Cross(along).Unit
			if normal.Y < 0 then
				normal = -normal
			end
			local centre = (p1 + p3) / 2 - normal * style.thickness / 2
			local part = TownKit.box(Vector3.new(width, style.thickness, length), CFrame.fromMatrix(centre, across.Unit, normal), style.colour, style.material)
			if style.collide == false then
				part.CanCollide = false
			end
			table.insert(out, part)
			return out
		end
	end
	RoadKit.triangle(p1, p2, p3, style, out)
	RoadKit.triangle(p1, p3, p4, style, out)
	return out
end

-- A strip between offsets `from` and `to` (left is positive) along points with their normals
function RoadKit.strip(points: { Vector3 }, normals: { Vector3 }, from: number, to: number, style: Style, lift: number?): { BasePart }
	local made = {}
	local up = Vector3.new(0, lift or 0, 0)
	for k = 2, #points do
		local r0 = points[k - 1] + normals[k - 1] * from + up
		local l0 = points[k - 1] + normals[k - 1] * to + up
		local r1 = points[k] + normals[k] * from + up
		local l1 = points[k] + normals[k] * to + up
		RoadKit.quad(r0, l0, l1, r1, style, made)
	end
	return made
end

-- A strip whose two edges are given point by point (they must have the same number of points)
function RoadKit.between(right: { Vector3 }, left: { Vector3 }, style: Style): { BasePart }
	local made = {}
	for k = 2, math.min(#right, #left) do
		RoadKit.quad(right[k - 1], left[k - 1], left[k], right[k], style, made)
	end
	return made
end

-- A fan of triangles from `centre` round the outline `ring` (closed)
function RoadKit.fan(centre: Vector3, ring: { Vector3 }, style: Style): { BasePart }
	local made = {}
	for k = 1, #ring do
		local a, b = ring[k], ring[k % #ring + 1]
		if (a - b).Magnitude > 0.02 then
			RoadKit.triangle(centre, a, b, style, made)
		end
	end
	return made
end

-- Resamples a line of points to exactly `count` points, evenly spaced along it
function RoadKit.resample(points: { Vector3 }, count: number): { Vector3 }
	local total = 0
	local lengths = { 0 }
	for k = 2, #points do
		total += (points[k] - points[k - 1]).Magnitude
		lengths[k] = total
	end
	local out = {}
	local k = 2
	for i = 0, count - 1 do
		local s = total * i / (count - 1)
		while k < #points and lengths[k] < s do
			k += 1
		end
		local span = lengths[k] - lengths[k - 1]
		local f = if span < 1e-9 then 0 else math.clamp((s - lengths[k - 1]) / span, 0, 1)
		out[i + 1] = points[k - 1]:Lerp(points[k], f)
	end
	return out
end

-- A wall along a line of points: from height `bottom` to `top` (absolute), `thickness` thick, centred on the line
function RoadKit.wall(points: { Vector3 }, bottom: number, top: number, thickness: number, colour: Color3, material: Enum.Material): { BasePart }
	local made: { BasePart } = {}
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local along = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local length = along.Magnitude
		if length > 0.05 then
			local middle = Vector3.new((a.X + b.X) / 2, (bottom + top) / 2, (a.Z + b.Z) / 2)
			local part = TownKit.box(Vector3.new(thickness, top - bottom, length + thickness * 0.5), CFrame.lookAt(middle, middle + along), colour, material)
			table.insert(made, part)
		end
	end
	return made
end

-- A wall that follows a sloping line: `height` tall above each point, hanging `below` under it
function RoadKit.parapet(points: { Vector3 }, height: number, below: number, thickness: number, colour: Color3, material: Enum.Material): { BasePart }
	local made: { BasePart } = {}
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local along = b - a
		if along.Magnitude > 0.05 then
			local middle = (a + b) / 2 + Vector3.new(0, (height - below) / 2, 0)
			local part = TownKit.box(Vector3.new(thickness, height + below, along.Magnitude + thickness * 0.5), CFrame.lookAt(middle, middle + along), colour, material)
			table.insert(made, part)
		end
	end
	return made
end

-- Paint ------------------------------------------------------------------------------------

local PAINT_LIFT = 0.035 -- paint sits this far above the road so it never flickers

local function paintPiece(a: Vector3, b: Vector3, width: number, colour: Color3, extra: number?): BasePart?
	local along = b - a
	local length = along.Magnitude
	if length < 0.05 then
		return nil
	end
	local middle = (a + b) / 2 + Vector3.new(0, PAINT_LIFT, 0)
	local part = TownKit.detail(Vector3.new(width, 0.05, length + (extra or 0)), CFrame.lookAt(middle, middle + along), colour)
	part.CastShadow = false
	return part
end

-- A solid line `width` wide at `offset` along points (with normals)
function RoadKit.line(points: { Vector3 }, normals: { Vector3 }, offset: number, width: number, colour: Color3)
	for k = 2, #points do
		paintPiece(points[k - 1] + normals[k - 1] * offset, points[k] + normals[k] * offset, width, colour, 0.25)
	end
end

-- A dashed line along a path between s0 and s1: `dash` long, `gap` apart
function RoadKit.dashes(path: Path, s0: number, s1: number, offset: number, width: number, dash: number, gap: number, colour: Color3)
	local s = s0 + gap / 2
	while s + dash <= s1 do
		local a, _, na = RoadKit.at(path, s)
		local b, _, nb = RoadKit.at(path, s + dash)
		paintPiece(a + na * offset, b + nb * offset, width, colour)
		s += dash + gap
	end
end

-- A solid line along a path between s0 and s1
function RoadKit.pathLine(path: Path, s0: number, s1: number, offset: number, width: number, colour: Color3)
	local points, normals = RoadKit.slice(path, s0, s1)
	RoadKit.line(points, normals, offset, width, colour)
end

-- One flat painted rectangle centred on `at`, `along` long in direction `direction`
function RoadKit.mark(at: Vector3, direction: Vector3, width: number, along: number, colour: Color3): BasePart?
	return paintPiece(at - direction * along / 2, at + direction * along / 2, width, colour)
end

-- A painted triangle (give-way triangles, chevrons)
function RoadKit.paintTriangle(a: Vector3, b: Vector3, c: Vector3, colour: Color3)
	local lift = Vector3.new(0, PAINT_LIFT + 0.025, 0)
	local made = RoadKit.triangle(a + lift, b + lift, c + lift, { colour = colour, material = Enum.Material.SmoothPlastic, thickness = 0.05, collide = false })
	for _, part in made do
		part.CanQuery = false
		part.CastShadow = false
	end
end

return RoadKit
