-- The camera while you drive one of our cars, made to flow like Birmingham Vehicle Simulator's instead of
-- Roblox's stiff default:
--   - it trails behind the car and swings round after it, catching up over about a second, so turns and slides
--     look smooth (in a slide it follows the way the car is going, so you see the car side-on)
--   - it stays the same distance at any speed (no zooming out)
--   - drag with the right mouse button (or the right stick, or a finger) to look round; let go and it drifts
--     back behind the car after a moment
--   - the mouse wheel zooms in and out
--   - it never goes through walls
-- Driving starts it when you get in and stops it when you get out. It steps aside while the menu is open.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent:WaitForChild("Ui"))

local ChaseCamera = {}

local FOLLOW_RATE = 2.4 -- how quickly the camera swings round behind the car (per second): lower trails more
local VELOCITY_SHARE = 0.65 -- how much it looks where the car's going rather than where its nose points
-- Placed like BVS's (measured off Lewis's screen, 18 Oct 2026, then raised when Lewis felt it sat too low): above
-- the car, about 22 degrees up from its middle, looking a little down the road over the roof, so the car sits low
-- in the picture with the road ahead filling the rest. It stays the same distance at any speed.
local ELEVATION = math.rad(22) -- how far above the car the camera sits, as an angle from the car's middle
local LOOK_DOWN = math.rad(7) -- how far below level it looks
local DISTANCE = 1.25 -- studs from the car's middle per stud of car length
local SPEED_PULLBACK = 0 -- extra studs back per stud per second of speed
local CAMERA_RADIUS = 0.6 -- keeps the camera this far off walls and things in the way
local BASE_FOV = 70
local SPEED_FOV = 0 -- degrees wider flat out
local RETURN_DELAY = 1.4 -- seconds after you stop moving the camera before it drifts back
local RETURN_RATE = 2.5 -- how quickly it drifts back (per second)
local MOUSE_TURN = 0.008 -- radians per pixel of mouse drag
local STICK_TURN = 3 -- radians per second with the stick pushed all the way

type State = {
	chassis: BasePart,
	ignore: { Instance },
	yaw: number, -- where the camera points, round the car (radians, world)
	lookYaw: number, -- how far you've turned it yourself
	lookPitch: number,
	lookedAt: number, -- when you last moved it
	zoom: number, -- your zoom, as a share of the normal distance
	focus: Vector3,
	stickSeenCentred: boolean, -- a stick that's never been let go is ignored (Lewis's controller sticks)
	connections: { RBXScriptConnection },
	dragging: boolean,
	finger: InputObject?, -- the touch that's dragging the view, on a touch screen
}

local state: State? = nil
local RENDER_NAME = "ChaseCamera"

local function headingOf(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

-- The shortest way round from one angle to another
local function angleTo(from: number, to: number): number
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

local function update(dt: number)
	local s = state
	if not s or Ui.menuOpen then
		return
	end
	local chassis = s.chassis
	if not chassis.Parent then
		return
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	local cframe = chassis.CFrame
	local look = cframe.LookVector * Vector3.new(1, 0, 1)
	local velocity = chassis.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local speed = velocity.Magnitude
	local forward = velocity:Dot(look)

	-- Where the camera wants to be: behind the car, leaning towards the way it's going once it's moving
	-- forwards (reversing, it keeps looking forwards)
	local direction = look
	if forward > 6 and look.Magnitude > 0.01 then
		local blend = VELOCITY_SHARE * math.clamp((forward - 6) / 20, 0, 1)
		direction = look.Unit * (1 - blend) + velocity.Unit * blend
	end
	if direction.Magnitude > 0.01 then
		s.yaw += angleTo(s.yaw, headingOf(direction)) * (1 - math.exp(-FOLLOW_RATE * dt))
	end

	-- Looking round with the right stick; anything you've turned drifts back after a moment
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		for _, input in UserInputService:GetGamepadState(gamepad) do
			if input.KeyCode == Enum.KeyCode.Thumbstick2 then
				local stick = Vector2.new(input.Position.X, input.Position.Y)
				if stick.Magnitude < 0.2 then
					s.stickSeenCentred = true
				elseif s.stickSeenCentred then
					s.lookYaw -= stick.X * STICK_TURN * dt
					s.lookPitch = math.clamp(s.lookPitch - stick.Y * STICK_TURN * 0.6 * dt, -0.15, 0.9)
					s.lookedAt = os.clock()
				end
			end
		end
	end
	if os.clock() - s.lookedAt > RETURN_DELAY and not s.dragging then
		local back = 1 - math.exp(-RETURN_RATE * dt)
		s.lookYaw -= s.lookYaw * back
		s.lookPitch -= s.lookPitch * back
	end

	-- The car's middle, exactly, so the camera never drops back as the car speeds up (it used to follow a smoothed
	-- copy that lagged further behind the faster you went, which shrank the car). Only the height is smoothed, so
	-- the springs' bobbing doesn't shake the picture.
	local target = cframe.Position
	local height = s.focus.Y + (target.Y - s.focus.Y) * (1 - math.exp(-14 * dt))
	if math.abs(target.Y - height) > 6 then
		height = target.Y
	end
	s.focus = Vector3.new(target.X, height, target.Z)

	local distance = (chassis.Size.Z * DISTANCE + speed * SPEED_PULLBACK) * s.zoom
	local elevation = ELEVATION + s.lookPitch
	local turn = CFrame.Angles(0, s.yaw + s.lookYaw, 0)
	local offset = turn:VectorToWorldSpace(Vector3.new(0, math.sin(elevation), math.cos(elevation)) * distance)

	-- Not through walls or into anything solid: a ball swept out from the middle of the car stops the camera
	-- short of the first solid thing in the way (see-through and walk-through parts don't count)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = s.ignore
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local hit = Workspace:Spherecast(s.focus, CAMERA_RADIUS, offset, params)
	local position = if hit then s.focus + offset.Unit * math.max(hit.Distance, 0.5) else s.focus + offset

	-- Looking almost level down the road, tipping down as much as you've swung the camera up
	local down = LOOK_DOWN + s.lookPitch
	camera.CFrame = CFrame.lookAt(position, position + turn:VectorToWorldSpace(Vector3.new(0, -math.sin(down), -math.cos(down))))

	local wide = BASE_FOV + SPEED_FOV * math.clamp((speed - 32) / 112, 0, 1)
	camera.FieldOfView += (wide - camera.FieldOfView) * (1 - math.exp(-2.5 * dt))
end

function ChaseCamera.start(car: Model, chassis: BasePart, character: Instance?)
	ChaseCamera.stop()
	local look = chassis.CFrame.LookVector
	local s: State = {
		chassis = chassis,
		ignore = { car, character :: Instance },
		yaw = headingOf(look),
		lookYaw = 0,
		lookPitch = 0,
		lookedAt = 0,
		zoom = 1,
		focus = chassis.Position,
		stickSeenCentred = false,
		connections = {},
		dragging = false,
		finger = nil,
	}
	state = s

	-- Right mouse button (or a finger on a touch screen) drags the view round; the wheel zooms
	table.insert(s.connections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			s.dragging = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.UserInputType == Enum.UserInputType.Touch and not s.finger
			and input.Position.X > Workspace.CurrentCamera.ViewportSize.X / 2 then
			-- Only a finger on the right half of the screen: the left half is the steering stick
			s.finger = input
			s.dragging = true
		end
	end))
	table.insert(s.connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input == s.finger then
			s.dragging = false
			s.finger = nil
			s.lookedAt = os.clock()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end))
	table.insert(s.connections, UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			s.zoom = math.clamp(s.zoom - input.Position.Z * 0.04, 0.7, 1.6)
		elseif s.dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == s.finger) then
			s.lookYaw -= input.Delta.X * MOUSE_TURN
			s.lookPitch = math.clamp(s.lookPitch + input.Delta.Y * MOUSE_TURN * 0.7, -0.15, 0.9)
			s.lookedAt = os.clock()
		end
	end))

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 2, update)
end

function ChaseCamera.stop()
	local s = state
	if not s then
		return
	end
	state = nil
	RunService:UnbindFromRenderStep(RENDER_NAME)
	for _, connection in s.connections do
		connection:Disconnect()
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local camera = Workspace.CurrentCamera
	camera.FieldOfView = BASE_FOV
	if not Ui.menuOpen then
		camera.CameraType = Enum.CameraType.Custom
	end
end

return ChaseCamera
