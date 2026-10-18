-- A pretend gearbox, so cars rev up, change gear and sound like real ones. The car's speed is still what the
-- physics uses; this works out which gear it's in and how fast the engine is turning. Driving uses it for the
-- car you drive, and VehicleEffects uses it to make every car on the road sound right.
-- A car's "Gears" attribute picks the gearbox (see Gearbox.Boxes): 6 speeds unless it says otherwise.

local Gearbox = {}

Gearbox.IDLE = 750 -- rpm with the engine ticking over
Gearbox.REDLINE = 7000 -- rpm where it changes up (or hits the limiter in top gear)
Gearbox.UP_AT = 6600 -- rpm to change up at when you're on the accelerator
Gearbox.DOWN_AT = 2600 -- rpm to change down at
Gearbox.DOWN_BRAKING = 3800 -- rpm to change down at while braking, so it drops down the gears with a blip each

export type Box = {
	ratios: { number }, -- how much of the car's top speed each gear reaches at the redline
	pull: { number }, -- how hard each gear pulls compared with the car's acceleration figure
	shiftTime: number, -- seconds with no drive while it changes up
}

Gearbox.Boxes = {
	[6] = {
		ratios = { 0.22, 0.37, 0.52, 0.67, 0.83, 1.0 },
		pull = { 1.45, 1.25, 1.05, 0.88, 0.74, 0.62 },
		shiftTime = 0.2,
	},
	-- An 8-speed automatic like the ZF one in fast saloons and hot hatches: close ratios and quick changes
	[8] = {
		ratios = { 0.2, 0.31, 0.43, 0.55, 0.67, 0.79, 0.9, 1.0 },
		pull = { 1.5, 1.36, 1.2, 1.06, 0.93, 0.82, 0.72, 0.64 },
		shiftTime = 0.14,
	},
} :: { [number]: Box }

-- The gearbox for a car, from its "Gears" attribute
function Gearbox.boxFor(car: Instance): Box
	local gears = car:GetAttribute("Gears")
	return Gearbox.Boxes[if typeof(gears) == "number" then gears else 6] or Gearbox.Boxes[6]
end

-- The fastest a gear goes, in studs per second
function Gearbox.gearTop(box: Box, gear: number, topSpeed: number): number
	local ratio = box.ratios[math.clamp(gear, 1, #box.ratios)]
	return topSpeed * ratio
end

-- Engine speed in rpm, for a speed (studs per second) in a gear. Gear 0 is reverse.
function Gearbox.rpm(box: Box, speed: number, gear: number, topSpeed: number, reverseSpeed: number): number
	local top = if gear <= 0 then reverseSpeed * 1.15 else Gearbox.gearTop(box, gear, topSpeed)
	local share = math.clamp(math.abs(speed) / math.max(top, 1), 0, 1.04)
	return Gearbox.IDLE + (Gearbox.REDLINE - Gearbox.IDLE) * share
end

-- 0 at tick-over, 1 at the redline
function Gearbox.share(rpm: number): number
	return math.clamp((rpm - Gearbox.IDLE) / (Gearbox.REDLINE - Gearbox.IDLE), 0, 1)
end

-- How strong the engine is at an rpm (a little weak at the very bottom, strongest in the middle)
function Gearbox.torque(rpm: number): number
	local share = Gearbox.share(rpm)
	return 0.8 + 0.3 * math.sin(math.pi * math.clamp(share * 1.1, 0, 1))
end

-- The gear a car would be in at a speed, for cars we can only watch (other players'): changes up and down
-- at the same points the driver's own gearbox does, starting from the gear it was in
function Gearbox.guess(box: Box, speed: number, current: number, topSpeed: number, accelerating: boolean): number
	local top = #box.ratios
	local gear = math.clamp(current, 1, top)
	for _ = 1, top do
		local rpm = Gearbox.rpm(box, speed, gear, topSpeed, 1)
		if rpm >= (if accelerating then Gearbox.UP_AT else Gearbox.REDLINE * 0.9) and gear < top then
			gear += 1
		elseif rpm < Gearbox.DOWN_AT and gear > 1 then
			gear -= 1
		else
			break
		end
	end
	return gear
end

return Gearbox
