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

-- The suspension: how bouncy (natural frequency, per second) and how damped. About 1.9 Hz and 0.45 feels like
-- a firm road car.
local SPRING_HZ = 1.9
local DAMPING_RATIO = 0.45
local RIDE_LENGTH = 1.2 -- studs from the top of the spring to the hub at ride height
local DROOP = 0.7 -- how far a wheel can drop below ride height before it leaves the road
local BUMP_STOP = 0.3 -- spring length where the bump stop takes over
local ANTI_ROLL = 0.6 -- anti-roll bars, as a share of the spring stiffness

-- The tyre's grip curve (a cut-down Pacejka "magic formula"): grip rises steeply to a peak at about 10 degrees
-- of slip and fades to about 85% when sliding sideways. The back fades a little more, so slides happen at the
-- back and can be held.
local CURVE_B = 10
local CURVE_C_FRONT = 1.45
local CURVE_C_REAR = 1.52
local SLIP_FLOOR = 4 -- studs/s: below this, slip angles are worked out as if moving this fast (no jitter at a stop)

local HANDBRAKE_GRIP = 0.6 -- share of sideways grip the rear tyres keep with the handbrake on

-- Stability: a slide may only rotate the car so fast. A grip-limited car turns at most at grip / speed; a slide is
-- allowed SLIDE_YAW times that (plus a little), so the back swings out properly but at a speed you can catch
-- with countersteer, instead of spinning round in half a second. Normal driving never reaches the limit.
local SLIDE_YAW = 1.15
local SLIDE_YAW_EXTRA = 0.2 -- radians per second
local STABILITY_RATE = 10 -- how firmly it holds the limit (per second)
-- Spin guard: once the car is more than SPIN_GUARD sideways, its rotation is damped, more the further round it
-- is, so a big slide that's left alone straightens up rather than swapping ends
local SPIN_GUARD = math.rad(30)
local SPIN_GUARD_RATE = 6
-- Traction control: in a big slide, spinning rear wheels get only this share of their grip as drive, so keeping
-- your foot in holds the slide rather than spinning the car round
local SLIDE_TRACTION = 0.6
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
	steerAngle: number,
}

type Wheel = {
	joint: Motor6D,
	hub: Vector3, -- hub position at ride height, in the chassis' own space
	front: boolean,
	left: boolean,
	attachment: Attachment,
	force: VectorForce,
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
}, RaycastCar))

function RaycastCar.new(car: Model, chassis: BasePart, stats: Stats, ignore: { Instance }): Car
	local wheels: { Wheel } = {}
	for _, joint in chassis:GetChildren() do
		if joint:IsA("Motor6D") then
			local hub = joint.C0.Position
			local attachment = Instance.new("Attachment")
			attachment.Name = "SuspensionHub"
			attachment.Position = hub
			attachment.Parent = chassis
			local force = Instance.new("VectorForce")
			force.Name = "Suspension"
			force.Attachment0 = attachment
			force.RelativeTo = Enum.ActuatorRelativeTo.World
			force.ApplyAtCenterOfMass = false
			force.Force = Vector3.zero
			force.Parent = chassis
			table.insert(wheels, {
				joint = joint,
				hub = hub,
				front = hub.Z < 0,
				left = hub.X < 0,
				attachment = attachment,
				force = force,
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

	-- Steering: full lock when parking, less and less with speed (a little goes a long way at 60 mph). Steering
	-- into a slide gets as much lock as it takes to catch it.
	local speed = math.abs(forwardSpeed)
	local lock = stats.maxLock / (1 + speed / 33)
	local bodySlip = math.atan2(sideSpeed, math.max(speed, 1))
	if input.steer * bodySlip > 0 then
		lock = math.min(stats.maxLock, math.max(lock, math.abs(bodySlip) + math.rad(6)))
	end
	local steerAngle = input.steer * lock

	-- Pass 1: where each wheel meets the road, and how hard its spring pushes
	type Contact = { wheel: Wheel, hit: RaycastResult?, load: number }
	local contacts: { Contact } = {}
	local drivenDown = 0
	for _, wheel in self.wheels do
		local mount = cframe:PointToWorldSpace(wheel.hub + Vector3.new(0, RIDE_LENGTH, 0))
		local hit = Workspace:Raycast(mount, -up * (maxLength + radius), self.rayParams)
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
	for _, contact in contacts do
		local wheel = contact.wheel
		local hit = contact.hit
		local total = Vector3.zero
		local vLong = forwardSpeed
		if hit then
			local normal = hit.Normal
			local heading = if wheel.front then CFrame.fromAxisAngle(up, -steerAngle):VectorToWorldSpace(look) else look
			local forward = (heading - normal * heading:Dot(normal)).Unit
			local side = forward:Cross(normal)
			local pointVelocity = chassis:GetVelocityAtPosition(hit.Position)
			vLong = pointVelocity:Dot(forward)
			local vLat = pointVelocity:Dot(side)
			local load = contact.load
			local budget = mu * load -- most force this tyre can make, in any direction

			-- Sideways: from the slip angle, but never more than would stop the sideways motion this frame
			local slipAngle = math.atan2(vLat, math.max(math.abs(vLong), SLIP_FLOOR))
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
			local brakeShare = if wheel.front then 0.3 else 0.2
			local braking = mass * input.brake * brakeShare
			local stopRolling = math.abs(vLong) * quarter / dt
			if braking > 0 then
				longitudinal -= if direction ~= 0 then direction * math.min(braking, stopRolling) else vLong * quarter / dt
			end
			local locked = input.handbrake and not wheel.front
			if locked then
				longitudinal = -direction * math.min(budget * 0.9, stopRolling)
				lateral *= HANDBRAKE_GRIP
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
					local share = if math.abs(bodySlip) > SLIDE_TRACTION_FROM then SLIDE_TRACTION else 0.85
					longitudinal = math.sign(longitudinal) * budget * share
					lateral = math.sign(lateral) * math.min(math.abs(lateral), math.sqrt(budget * budget - longitudinal * longitudinal) * 0.7)
				else
					local scale = budget / wanted
					longitudinal *= scale
					lateral *= scale
				end
			end

			total = up * load + forward * longitudinal + side * lateral
			if not wheel.front and math.abs(slipAngle) > 0.12 then
				slip += math.abs(vLat)
			end
			if locked and math.abs(vLong) > 5 then
				slip += 8
			end
		end
		wheel.force.Force = total

		-- The wheel you see: up and down with the spring, turned by the steering, rolling with the road
		local spinRate = vLong / radius + (if spinning and not wheel.front then 25 * math.sign(input.drive) else 0)
		if input.handbrake and not wheel.front then
			spinRate = 0
		end
		wheel.spin -= spinRate * dt
		wheel.joint.Transform = CFrame.new(0, RIDE_LENGTH - wheel.length, 0)
			* CFrame.Angles(0, if wheel.front then -steerAngle else 0, 0)
			* CFrame.Angles(wheel.spin, 0, 0)
	end

	self.drag.Force = -velocity * velocity.Magnitude * DRAG * mass

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
		steerAngle = steerAngle,
	}
end

-- Takes the forces away and puts the wheels back, when the driver gets out
function RaycastCar.destroy(self: Car)
	for _, wheel in self.wheels do
		wheel.force:Destroy()
		wheel.attachment:Destroy()
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
