-- How a car sits on its springs and grips the road, built to feel solid and catchable like Birmingham Vehicle
-- Simulator rather than twitchy like Roblox's physical wheels.
--
-- Each wheel casts a ray down to the road. A spring and damper hold the car up at its proper ride height (so it
-- rides bumps and leans naturally), and the tyre pushes on the road with forces we work out ourselves:
--   - sideways grip builds up smoothly with how much the tyre is slipping, peaks, then fades only a little past
--     the limit, so a slide grows gradually and can always be caught (real tyres behave like this; Roblox's
--     physical wheels go from full grip to none at once, which is why cars snapped into spins)
--   - each tyre has one budget of grip shared between cornering and accelerating or braking, so braking hard or
--     flooring it in a bend uses grip the tyre would otherwise corner with: that's how the back steps out when
--     you ask it to, and only then
--   - grip goes with the weight on the tyre, which moves about as the car brakes, accelerates and corners
-- All forces go through a VectorForce at each wheel hub, made on the driver's device (which runs the car's
-- physics), so nothing here touches the server. Driving works out the engine, gears and pedals and calls step.
--
-- Units: studs, seconds, studs per second per second. Grip and brakes are given as accelerations, not
-- friction coefficients, because Roblox's gravity is about 5.6 times real gravity at this game's scale: an honest
-- friction coefficient would give cars 5 g of grip.

local Workspace = game:GetService("Workspace")

local RaycastCar = {}
RaycastCar.__index = RaycastCar

-- The suspension: how bouncy (natural frequency, per second) and how damped. 2.4 Hz and 0.65 is firm and
-- settles straight away, so the car feels planted (Lewis found 1.9 Hz floaty next to BVS)
local SPRING_HZ = 2.4
local DAMPING_RATIO = 0.65
local RIDE_LENGTH = 1.2 -- studs from the top of the spring to the hub at ride height
local DROOP = 0.7 -- how far a wheel can drop below ride height before it leaves the road
local BUMP_STOP = 0.3 -- spring length where the bump stop takes over
local ANTI_ROLL = 0.6 -- anti-roll bars, as a share of the spring stiffness

-- The tyre's grip curve (a cut-down Pacejka "magic formula"): grip rises steeply to a peak at about 10 degrees
-- of slip and fades to about 85% when sliding sideways. The back fades more (to about 75%), so slides happen at
-- the back, and when a sliding rear tyre comes back under its peak it bites hard: the snap you feel when the back
-- finds grip again.
local CURVE_B = 10
local CURVE_C_FRONT = 1.45
local CURVE_C_REAR = 1.6
local SLIP_FLOOR = 4 -- studs/s: below this, slip angles are worked out as if moving this fast (no jitter at a stop)

local HANDBRAKE_GRIP = 0.6 -- share of sideways grip the rear tyres keep with the handbrake on

-- Weight transfer: braking or lifting off tips the car onto its nose, so the front tyres grip more and the back
-- less (brake in a bend and the back can step out); accelerating does the opposite. Roblox's gravity is about
-- 5.6x real at our scale, so the springs alone move hardly any weight; this adds what a real car would.
-- WEIGHT_TRANSFER is the share of an axle's load that moves when braking at the tyres' limit.
local WEIGHT_TRANSFER = 0.35
local TRANSFER_RATE = 8 -- how quickly the weight moves (per second): the car pitching and leaning
-- Cornering moves weight onto the outside tyres the same way. A tyre with more weight on it grips more, but not
-- in proportion (LOAD_SENSITIVITY), so the more weight moves across an axle, the less that axle grips overall.
-- The back takes more of it than the front (like a stiffer rear anti-roll bar), so at the limit the back lets go
-- first: turn in too hard at speed and the back steps out.
local LATERAL_TRANSFER_FRONT = 0.55
local LATERAL_TRANSFER_REAR = 0.7
local LOAD_SENSITIVITY = 0.3
-- ABS on the front wheels only: they never brake harder than this share of their grip, so you can still steer.
-- The rear wheels can lock: brake hard in a bend and a rear tyre that's already cornering hard runs out of grip,
-- locks and skids, and the back slides out (let off the brake and it grips again). Brakes are split about 64/36.
local ABS_LIMIT = 0.85
local BRAKE_FRONT = 0.32 -- share of the braking at each front wheel
local BRAKE_REAR = 0.18 -- and at each rear wheel
local SKID_GRIP = 0.8 -- a locked, skidding tyre's grip, as a share of its rolling grip
local SKID_SIDE_GRIP = 0.45 -- and the share of its cornering grip it hangs on to, so the back slides out
-- progressively instead of whipping straight round

-- The road surface: a sliding rear tyre keeps finding and losing a bit of grip on a real road, so the back of a
-- sliding car twitches about instead of gliding. Up to SURFACE_VARIATION of its grip, changing SURFACE_RATE
-- times a second, and different on each side.
local SURFACE_VARIATION = 0.22
local SURFACE_RATE = 7

-- Steering lock against speed: full lock up to FULL_LOCK_SPEED (studs/s, about 15 mph) so U-turns are tight, then
-- it fades so that at 40 mph you get about 12 degrees (what the steering was matched to BVS with)
local FULL_LOCK_SPEED = 24
local LOCK_FADE = 14.5
-- But full lock always asks at least LIMIT_MARGIN more than the tightest turn the tyres can hold at that speed, so
-- yanking the wheel at 100 mph can still overpower the tyres (gentle inputs stay gentle)
local LIMIT_MARGIN = math.rad(4)
-- Countersteering: steering into a slide lets the wheels go as far round as the slide needs, plus
-- COUNTERSTEER_EXTRA. They don't straighten up by themselves as the car comes back (only COUNTERSTEER_UNWIND
-- radians a second), so if you hold the countersteer too long the back snaps the other way and you have to
-- catch that too, like a real car.
local COUNTERSTEER_EXTRA = math.rad(4)
local COUNTERSTEER_UNWIND = 0.6

-- Stability: a slide may only rotate the car so fast. A grip-limited car turns at most at grip / speed; a slide is
-- allowed SLIDE_YAW times that (plus a little), so the back swings out properly but at a speed you can catch
-- with countersteer, instead of spinning round in half a second. Normal driving never reaches the limit.
local SLIDE_YAW = 1.25
local SLIDE_YAW_EXTRA = 0.25 -- radians per second
local STABILITY_RATE = 8 -- how firmly it holds the limit (per second)
-- Spin guard: once the car is more than SPIN_GUARD sideways, its rotation is damped, more the further round it
-- is, so you get a moment to catch a big slide before it swaps ends (but you do have to catch it)
local SPIN_GUARD = math.rad(40)
local SPIN_GUARD_RATE = 4
-- Traction control: in a big slide, spinning rear wheels get only this share of their grip as drive, so keeping
-- your foot in holds the slide rather than spinning the car round
local SLIDE_TRACTION = 0.6
local WHEELSPIN_RISE = 3 -- how quickly a spinning wheel picks up speed (per second)
local WHEELSPIN_FALL = 5 -- and drops back when it grips
local SLIDE_TRACTION_FROM = math.rad(20)
local DRAG = 3.5e-4 -- air resistance: deceleration = DRAG * speed^2

export type Stats = {
	grip: number, -- most sideways acceleration the tyres can make, studs/s²
	wheelRadius: number,
	maxLock: number, -- full steering lock, radians
}

export type Input = {
	steer: number, -- -1 full left to 1 full right (already smoothed)
	drive: number, -- acceleration the engine asks for through the driven (rear) wheels, studs/s², negative in reverse
	brake: number, -- deceleration asked of the brakes, studs/s²
	coast: number, -- engine braking and rolling resistance through the driven wheels, studs/s²
	handbrake: boolean,
}

export type Telemetry = {
	forwardSpeed: number,
	sideSpeed: number,
	wheelsDown: number,
	slip: number, -- how hard the tyres are scrubbing sideways (studs/s), for the squeal and smoke
	spinning: boolean, -- the rear wheels are spinning
	wheelspin: number, -- how hard, eased in and out: 0 gripping to 1 spinning flat out (for the revs and squeal)
	steerAngle: number,
}

type Wheel = {
	joint: Motor6D,
	hub: Vector3, -- hub position at ride height, in the chassis' own space
	front: boolean,
	left: boolean,
	attachment: Attachment,
	force: VectorForce, -- the spring, pushing up at the hub
	tyreAttachment: Attachment,
	tyreForce: VectorForce, -- the tyre's grip, pushing at the height of the car's centre of weight
	skidding: boolean,
	length: number, -- spring length last frame
	compression: number,
	spin: number,
	grounded: boolean,
}

export type Car = typeof(setmetatable({} :: {
	car: Model,
	chassis: BasePart,
	stats: Stats,
	wheels: { Wheel },
	drag: VectorForce,
	stability: Torque,
	turnInertia: number,
	contacts: { BasePart },
	rayParams: RaycastParams,
	counterLock: number, -- how far the wheels are allowed round while catching a slide (radians)
	transfer: number, -- share of axle load moved onto the front (negative: onto the back)
	sideTransfer: number, -- how hard the car is cornering, as a share of its grip (positive: turning right)
	pushAlong: number, -- the tyres' forward push last frame, as an acceleration (studs/s²)
	pushSide: number, -- and their push to the right
	wheelbase: number,
	wheelspin: number,
}, RaycastCar))

function RaycastCar.new(car: Model, chassis: BasePart, stats: Stats, ignore: { Instance }): Car
	local wheels: { Wheel } = {}
	-- The tyres push the car at the height of its centre of weight, so braking, accelerating and cornering don't
	-- tip the body (it stays flat like Birmingham Vehicle Simulator's cars); the weight still moves between the
	-- tyres for grip (see WEIGHT_TRANSFER)
	local centreHeight = chassis.CFrame:PointToObjectSpace(chassis.AssemblyCenterOfMass).Y
	local function pushAt(name: string, at: Vector3): (Attachment, VectorForce)
		local attachment = Instance.new("Attachment")
		attachment.Name = name .. "Point"
		attachment.Position = at
		attachment.Parent = chassis
		local force = Instance.new("VectorForce")
		force.Name = name
		force.Attachment0 = attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = false
		force.Force = Vector3.zero
		force.Parent = chassis
		return attachment, force
	end
	for _, joint in chassis:GetChildren() do
		if joint:IsA("Motor6D") then
			local hub = joint.C0.Position
			local attachment, force = pushAt("Suspension", hub)
			local tyreAttachment, tyreForce = pushAt("Tyre", Vector3.new(hub.X, centreHeight, hub.Z))
			table.insert(wheels, {
				joint = joint,
				hub = hub,
				front = hub.Z < 0,
				left = hub.X < 0,
				attachment = attachment,
				force = force,
				tyreAttachment = tyreAttachment,
				tyreForce = tyreForce,
				skidding = false,
				length = RIDE_LENGTH,
				compression = 0,
				spin = 0,
				grounded = false,
			})
		end
	end

	local centre = Instance.new("Attachment")
	centre.Name = "DragPoint"
	centre.Parent = chassis
	local drag = Instance.new("VectorForce")
	drag.Name = "Drag"
	drag.Attachment0 = centre
	drag.RelativeTo = Enum.ActuatorRelativeTo.World
	drag.ApplyAtCenterOfMass = true
	drag.Force = Vector3.zero
	drag.Parent = chassis

	local stability = Instance.new("Torque")
	stability.Name = "Stability"
	stability.Attachment0 = centre
	stability.RelativeTo = Enum.ActuatorRelativeTo.World
	stability.Torque = Vector3.zero
	stability.Parent = chassis
	-- How hard the car is to turn (it's the chassis box that carries the weight)
	local size = chassis.Size
	local turnInertia = chassis.AssemblyMass * (size.X * size.X + size.Z * size.Z) / 12

	-- The invisible balls that hold a parked car up get out of the springs' way while it's being driven
	local contacts: { BasePart } = {}
	for _, part in car:GetChildren() do
		if part:IsA("BasePart") and part.Name == "TyreContact" then
			part.CanCollide = false
			table.insert(contacts, part)
		end
	end

	local front, back = math.huge, -math.huge
	for _, wheel in wheels do
		front = math.min(front, wheel.hub.Z)
		back = math.max(back, wheel.hub.Z)
	end
	local wheelbase = math.max(back - front, 1)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignore
	rayParams.IgnoreWater = true

	return setmetatable({
		car = car,
		chassis = chassis,
		stats = stats,
		wheels = wheels,
		drag = drag,
		stability = stability,
		turnInertia = turnInertia,
		contacts = contacts,
		rayParams = rayParams,
		counterLock = 0,
		transfer = 0,
		sideTransfer = 0,
		pushAlong = 0,
		pushSide = 0,
		wheelbase = wheelbase,
		wheelspin = 0,
	}, RaycastCar)
end

-- How much of a tyre's grip it uses at a slip angle
local function curve(slip: number, c: number): number
	return math.sin(c * math.atan(CURVE_B * slip))
end

-- Moves the car on for this frame: suspension, tyres, steering, and the wheels you can see. Called before each
-- physics step with that step's length.
function RaycastCar.step(self: Car, dt: number, input: Input): Telemetry
	local chassis = self.chassis
	local stats = self.stats
	local cframe = chassis.CFrame
	local up = cframe.UpVector
	local look = cframe.LookVector
	local velocity = chassis.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(look)
	local sideSpeed = velocity:Dot(cframe.RightVector)
	local mass = chassis.AssemblyMass
	local gravity = Workspace.Gravity
	local quarter = mass / 4

	-- Springs, from the car's weight each frame (so a passenger doesn't change how it rides)
	local omega = 2 * math.pi * SPRING_HZ
	local stiffness = quarter * omega * omega
	local damping = 2 * DAMPING_RATIO * omega * quarter
	local freeLength = RIDE_LENGTH + gravity / (omega * omega)
	local maxLength = RIDE_LENGTH + DROOP
	local radius = stats.wheelRadius
	local mu = stats.grip / gravity -- grip as a share of the tyre's load

	-- Steering: full lock up to FULL_LOCK_SPEED (so U-turns and junctions are tight), then less and less with
	-- speed (a little goes a long way at 60 mph). Steering into a slide gets as much lock as it takes to catch it.
	local speed = math.abs(forwardSpeed)
	local lock = stats.maxLock / (1 + math.max(speed - FULL_LOCK_SPEED, 0) / LOCK_FADE)
	lock = math.max(lock, math.atan(self.wheelbase * stats.grip / math.max(speed * speed, 1)) + LIMIT_MARGIN)
	local bodySlip = math.atan2(sideSpeed, math.max(speed, 1))
	if input.steer * bodySlip > 0 then
		self.counterLock = math.max(self.counterLock, math.abs(bodySlip) + COUNTERSTEER_EXTRA)
	end
	self.counterLock = math.max(self.counterLock - COUNTERSTEER_UNWIND * dt, 0)
	lock = math.min(stats.maxLock, math.max(lock, self.counterLock))
	local steerAngle = input.steer * lock

	-- Weight transfer, from how hard the tyres pushed the car along last frame (braking pushes backwards)
	local target = math.clamp(-self.pushAlong / stats.grip, -1.2, 1.2) * WEIGHT_TRANSFER
	self.transfer += (target - self.transfer) * math.min(TRANSFER_RATE * dt, 1)
	local sideTarget = math.clamp(self.pushSide / stats.grip, -1.2, 1.2)
	self.sideTransfer += (sideTarget - self.sideTransfer) * math.min(TRANSFER_RATE * dt, 1)
	if self.transfer ~= self.transfer or self.sideTransfer ~= self.sideTransfer then
		self.transfer = 0
		self.sideTransfer = 0
	end
	local now = os.clock()

	-- Pass 1: where each wheel meets the road, and how hard its spring pushes
	type Contact = { wheel: Wheel, hit: RaycastResult?, load: number }
	local contacts: { Contact } = {}
	local drivenDown = 0
	for _, wheel in self.wheels do
		local mount = cframe:PointToWorldSpace(wheel.hub + Vector3.new(0, RIDE_LENGTH, 0))
		local hit = Workspace:Raycast(mount, -up * (maxLength + radius), self.rayParams)
		if hit and hit.Normal:Dot(up) < 0.3 then
			hit = nil -- a wall or the side of something, not road a tyre can stand on (the car's on its side)
		end
		local length = maxLength
		local load = 0
		if hit then
			length = math.clamp((hit.Position - mount).Magnitude - radius, 0, maxLength)
			local rate = (length - wheel.length) / dt
			load = stiffness * (freeLength - length) - damping * rate
			if length < BUMP_STOP then
				load += stiffness * 4 * (BUMP_STOP - length)
			end
			load = math.max(load, 0)
			if not wheel.front then
				drivenDown += 1
			end
		end
		wheel.length = length
		wheel.compression = if hit then freeLength - length else 0
		wheel.grounded = hit ~= nil
		table.insert(contacts, { wheel = wheel, hit = hit, load = load })
	end

	-- Anti-roll bars: share load between the two wheels on each axle as the car leans
	for _, a in contacts do
		for _, b in contacts do
			if a.wheel.front == b.wheel.front and a.wheel.left and not b.wheel.left and a.hit and b.hit then
				local transfer = ANTI_ROLL * stiffness * (a.wheel.compression - b.wheel.compression)
				a.load = math.max(a.load + transfer, 0)
				b.load = math.max(b.load - transfer, 0)
			end
		end
	end

	-- Pass 2: the tyre forces
	local slip = 0
	local spinning = false
	local spinAmount = 0
	local pushAlong = 0
	local pushSide = 0
	for _, contact in contacts do
		local wheel = contact.wheel
		local hit = contact.hit
		local springPush = Vector3.zero
		local tyrePush = Vector3.zero
		local vLong = forwardSpeed
		wheel.skidding = false
		if hit then
			local normal = hit.Normal
			local heading = if wheel.front then CFrame.fromAxisAngle(up, -steerAngle):VectorToWorldSpace(look) else look
			local forward = (heading - normal * heading:Dot(normal)).Unit
			local side = forward:Cross(normal)
			local pointVelocity = chassis:GetVelocityAtPosition(hit.Position)
			vLong = pointVelocity:Dot(forward)
			local vLat = pointVelocity:Dot(side)
			local load = contact.load
			-- Most force this tyre can make, in any direction: from its spring, plus the weight moved onto it by
			-- braking, accelerating and cornering (weight goes to the outside of a bend)
			local across = if wheel.front then LATERAL_TRANSFER_FRONT else LATERAL_TRANSFER_REAR
			local weight = 1 + (if wheel.front then self.transfer else -self.transfer)
				+ self.sideTransfer * across * (if wheel.left then 1 else -1)
			weight = math.max(weight, 0)
			local budget = mu * load * weight * (1 - LOAD_SENSITIVITY * (weight - 1))

			-- Sideways: from the slip angle, but never more than would stop the sideways motion this frame
			local slipAngle = math.atan2(vLat, math.max(math.abs(vLong), SLIP_FLOOR))
			if not wheel.front and math.abs(slipAngle) > 0.06 then
				local bumpy = math.noise(now * SURFACE_RATE, if wheel.left then 1.5 else 7.5) * 2
				budget *= 1 + SURFACE_VARIATION * math.clamp(bumpy, -1, 1) * math.min((math.abs(slipAngle) - 0.06) / 0.12, 1)
			end
			local lateral = -budget * curve(slipAngle, if wheel.front then CURVE_C_FRONT else CURVE_C_REAR)
			local stopSideways = math.abs(vLat) * quarter / dt
			lateral = math.clamp(lateral, -stopSideways, stopSideways)

			-- Along the wheel: the engine (rear wheels), the brakes (more at the front), engine braking and the
			-- handbrake
			local direction = if vLong > 0.5 then 1 elseif vLong < -0.5 then -1 else 0
			local longitudinal = 0
			if not wheel.front and drivenDown > 0 then
				longitudinal += mass * input.drive / drivenDown
				longitudinal -= direction * mass * input.coast / drivenDown
			end
			local brakeShare = if wheel.front then BRAKE_FRONT else BRAKE_REAR
			local braking = mass * input.brake * brakeShare
			if wheel.front then
				braking = math.min(braking, budget * ABS_LIMIT)
			end
			local stopRolling = math.abs(vLong) * quarter / dt
			if braking > 0 then
				longitudinal -= if direction ~= 0 then direction * math.min(braking, stopRolling) else vLong * quarter / dt
			end
			local locked = input.handbrake and not wheel.front
			if locked then
				longitudinal = -direction * math.min(budget * 0.9, stopRolling)
				lateral *= HANDBRAKE_GRIP
			elseif not wheel.front and braking > 0 and math.abs(vLong) > 3
				and braking * braking + lateral * lateral > budget * budget then
				-- Braking and cornering asks more than the tyre has: it locks and skids, pushing back along the way
				-- it's sliding
				local sliding = math.sqrt(vLong * vLong + vLat * vLat)
				longitudinal = -budget * SKID_GRIP * vLong / sliding
				local slide = -budget * SKID_GRIP * vLat / sliding
				local held = lateral * SKID_SIDE_GRIP
				lateral = math.clamp(if math.abs(held) > math.abs(slide) then held else slide, -stopSideways, stopSideways)
				local most = budget * SKID_GRIP
				local asked = math.sqrt(longitudinal * longitudinal + lateral * lateral)
				if asked > most then
					longitudinal *= most / asked
					lateral *= most / asked
				end
				locked = true
				wheel.skidding = true
			end
			-- Standing still with nothing pressed: the tyres hold the car where it is
			if input.drive == 0 and math.abs(vLong) < 1 then
				longitudinal = -vLong * quarter / dt
			end

			-- One grip budget for both directions. Asking a rear tyre for more drive than it can take spins it,
			-- and a spinning tyre has little sideways grip left: that's the power slide.
			local wanted = math.sqrt(longitudinal * longitudinal + lateral * lateral)
			if wanted > budget and budget > 0 then
				if not wheel.front and not locked and math.abs(longitudinal) > budget * 0.9 and input.drive ~= 0 then
					spinning = true
					spinAmount = math.max(spinAmount, math.clamp(math.abs(longitudinal) / budget - 0.9, 0, 1))
					local share = if math.abs(bodySlip) > SLIDE_TRACTION_FROM then SLIDE_TRACTION else 0.85
					longitudinal = math.sign(longitudinal) * budget * share
					lateral = math.sign(lateral) * math.min(math.abs(lateral), math.sqrt(budget * budget - longitudinal * longitudinal) * 0.7)
				else
					local scale = budget / wanted
					longitudinal *= scale
					lateral *= scale
				end
			end

			springPush = up * load
			tyrePush = forward * longitudinal + side * lateral
			pushAlong += tyrePush:Dot(look)
			pushSide += tyrePush:Dot(cframe.RightVector)
			if not wheel.front and math.abs(slipAngle) > 0.12 then
				slip += math.abs(vLat)
			end
			if locked and math.abs(vLong) > 5 then
				slip += 8
			end
		end
		wheel.force.Force = springPush
		wheel.tyreForce.Force = tyrePush

		-- The wheel you see: up and down with the spring, turned by the steering, rolling with the road
		local spinRate = vLong / radius + (if not wheel.front then 30 * self.wheelspin * math.sign(input.drive) else 0)
		if (input.handbrake and not wheel.front) or wheel.skidding then
			spinRate = 0
		end
		wheel.spin = (wheel.spin - spinRate * dt) % (2 * math.pi)
		if wheel.spin ~= wheel.spin then
			wheel.spin = 0 -- never let a bad number in, or Roblox ignores the wheel's position from then on
		end
		wheel.joint.Transform = CFrame.new(0, RIDE_LENGTH - wheel.length, 0)
			* CFrame.Angles(0, if wheel.front then -steerAngle else 0, 0)
			* CFrame.Angles(wheel.spin, 0, 0)
	end

	self.drag.Force = -velocity * velocity.Magnitude * DRAG * mass
	self.pushAlong = pushAlong / mass
	-- Wheelspin builds up and dies away over a few tenths of a second, as a real wheel speeds up and slows down,
	-- so a moment's slip doesn't flick the revs up and down
	local rate = if spinAmount > self.wheelspin then WHEELSPIN_RISE else WHEELSPIN_FALL
	self.wheelspin += (spinAmount - self.wheelspin) * math.min(rate * dt, 1)
	self.pushSide = pushSide / mass

	-- Stability: hold a slide's rotation to a speed that can be caught
	local yaw = chassis.AssemblyAngularVelocity:Dot(up)
	local limit = SLIDE_YAW * stats.grip / math.max(speed, 12) + SLIDE_YAW_EXTRA
	local excess = math.abs(yaw) - limit
	local correction = 0
	if excess > 0 and speed > 8 then
		correction -= math.sign(yaw) * excess * STABILITY_RATE
	end
	local sideways = math.abs(bodySlip)
	if sideways > SPIN_GUARD and speed > 8 then
		correction -= yaw * SPIN_GUARD_RATE * math.min((sideways - SPIN_GUARD) / SPIN_GUARD, 1)
	end
	self.stability.Torque = up * correction * self.turnInertia

	local down = 0
	for _, wheel in self.wheels do
		if wheel.grounded then
			down += 1
		end
	end
	return {
		forwardSpeed = forwardSpeed,
		sideSpeed = sideSpeed,
		wheelsDown = down,
		slip = slip,
		spinning = spinning,
		wheelspin = self.wheelspin,
		steerAngle = steerAngle,
	}
end

-- Takes the forces away and puts the wheels back, when the driver gets out
function RaycastCar.destroy(self: Car)
	for _, wheel in self.wheels do
		wheel.force:Destroy()
		wheel.attachment:Destroy()
		wheel.tyreForce:Destroy()
		wheel.tyreAttachment:Destroy()
		wheel.joint.Transform = CFrame.identity
	end
	local point = self.drag.Attachment0
	self.drag:Destroy()
	self.stability:Destroy()
	if point then
		point:Destroy()
	end
	for _, part in self.contacts do
		part.CanCollide = true
	end
end

return RaycastCar
