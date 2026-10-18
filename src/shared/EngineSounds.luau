-- Real engine sounds for the cars that have them (a vehicle's `engine` in Vehicles; CarBuilder puts it on the
-- car as the "EngineSound" attribute). Each profile is a few recordings of the engine held at set revs.
-- VehicleEffects plays them all at once and blends between the two nearest the engine's rpm, speeding each
-- one up or down to match, which is how racing games make engines sound real.
-- Cars without a profile use VehicleEffects' own two-recording engine.
--
-- The rpm of each recording was worked out from its firing frequency (a straight-six fires 3 times a turn, so
-- rpm = frequency x 20), checked against BMW recordings labelled with their revs. The volumes even out how
-- loud each recording is. All are public Creator Store sounds, checked 18 Oct 2026.

export type Loop = {
	id: string,
	rpm: number, -- the revs it was recorded at
	volume: number,
}

export type Profile = {
	loops: { Loop }, -- lowest revs first
	farts: { string }?, -- the "brap" on a flat-out upshift (picked at random)
	fartVolume: number?,
	burble: string?, -- crackle when you lift off at high revs
	startup: string?, -- when someone gets in the driver's seat
}

local EngineSounds = {}

EngineSounds.Profiles = {
	-- BMW B58 3.0 turbo straight-six (M140i, M340i)
	b58 = {
		loops = {
			{ id = "rbxassetid://117441998977977", rpm = 730, volume = 0.95 }, -- B58_IDLE by oshakeel
			{ id = "rbxassetid://79449611704764", rpm = 2000, volume = 0.6 }, -- Engine_2000 BMW by drygkrakena
			{ id = "rbxassetid://139163114617276", rpm = 3760, volume = 0.6 }, -- b58lowrev by YaBoyZenvo
			{ id = "rbxassetid://113954634252023", rpm = 5600, volume = 0.68 }, -- b58midrev by YaBoyZenvo
			{ id = "rbxassetid://133672841771116", rpm = 7000, volume = 1.3 }, -- B58highrev by YaBoyZenvo
		},
		farts = {
			"rbxassetid://128640768661650", -- upshift by TA7A_IS9Here: 7 deep bangs in 0.2 s
			"rbxassetid://114592589407764", -- B9 Upshift: 8 bangs in 0.2 s
		},
		fartVolume = 2.4,
		burble = "rbxassetid://75835637931827", -- b58burble2 by CATTERGAMEMER1111
		startup = "rbxassetid://78811978152098", -- I6 3.0L BMW B58 140I ENG STARTUP by ttsoarrr
	},
} :: { [string]: Profile }

-- Every sound id in every profile, for loading them up front
function EngineSounds.allIds(): { string }
	local ids = {}
	for _, profile in EngineSounds.Profiles do
		for _, loop in profile.loops do
			table.insert(ids, loop.id)
		end
		local farts: { string } = profile.farts or {}
		for _, id in farts do
			table.insert(ids, id)
		end
		if profile.burble then
			table.insert(ids, profile.burble)
		end
		if profile.startup then
			table.insert(ids, profile.startup)
		end
	end
	return ids
end

return EngineSounds
