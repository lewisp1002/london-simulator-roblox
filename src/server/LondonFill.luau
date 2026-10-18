--!nocheck
-- Everything that fills London's blocks, as data. MADE BY tools/london_fill.py (run tools/london_layout.py):
-- don't edit this file by hand. LondonMap builds it. The rows themselves are in LondonFillData1, 2...
--   styles: names used by buildings (kit building names, or CityBuildings styles)
--   buildings: { kit (1) or parts (0), style index, front x, front z, turn (degrees), width, depth, storeys, seed, back (1/0), flank }
--     the front edge is centred on (x, z); turn 0 faces north (-z)
--     flank: on a corner, 1 if the building's right side faces a street too, -1 its left side, 0 neither
--   gardens: { kind (1 lawn, 2 yard, 3 car park), front x, front z, turn, width, depth }
--   walls: { kind (1 brick, 2 fence, 3 hedge, 4 railing), x0, z0, x1, z1 }
--   trees: { x, z, size, form (1 round, 2 tall, 3 wide, 4 bush) }

local fill = {
	styles = { "concrete", "corner", "council", "darwick", "detached_a", "detached_b", "detached_c", "detached_d", "duggen", "georgian", "gosford", "gosford_double", "mansion", "mitchell", "morton", "office", "pub", "semi_a", "semi_b", "semi_c", "shed", "shop_1", "shop_2", "shop_3", "shop_4", "shop_5", "shop_6", "shop_7", "shops", "stone", "terrace_a", "terrace_b", "victorian", "warehouse", "windsor" },
	buildings = {},
	gardens = {},
	walls = {},
	trees = {},
}
for i = 1, 4 do
	local part = require(script.Parent:FindFirstChild("LondonFillData" .. i))
	for kind, rows in part do
		for _, row in rows do
			table.insert(fill[kind], row)
		end
	end
end
return fill
