-- Turns numbers into text for the UI.

local Config = require(script.Parent.Config)

local Format = {}

-- 1250 -> "£1,250"
function Format.money(amount: number): string
	local digits = tostring(math.floor(math.abs(amount)))
	local withCommas = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	local sign = if amount < 0 then "-" else ""
	return sign .. Config.CurrencySymbol .. withCommas
end

return Format
