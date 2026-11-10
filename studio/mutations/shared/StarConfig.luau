--[[
	StarConfig  (ModuleScript)
	Put in: ReplicatedStorage > Items > Modules > StarConfig

	Star grades (quality) for fish, from 1 to 5 stars.

	How a star grade is rolled (server only, see MutationRoller):
	  weightFraction = where the fish's weight sits in its species range (0 = lightest, 1 = heaviest)
	  sizeFraction   = a separate random length roll (0 = shortest, 1 = longest)
	  quality        = (weightFraction + sizeFraction) / 2
	  stars          = the grade whose quality band contains `quality`

	Each band is computed automatically from the `odds` below. You only edit odds and
	multipliers; the thresholds re-calculate so the real odds always match the config.
	(With two uniform rolls, P(quality >= t) = 2(1-t)^2 when t >= 0.5, else 1 - 2t^2.)

	  multiplier  value multiplier for income and sell value (EconomyBalance.FishValueMultiplier)
	  odds        relative chance (bigger = more common). 5 stars is rare on purpose.
	  color       star color in UI
]]

local StarConfig = {}

StarConfig.Grades = {
	{ stars = 1, multiplier = 1.0, odds = 50, label = "Small", color = Color3.fromRGB(200, 205, 215) },
	{ stars = 2, multiplier = 1.15, odds = 28, label = "Fine", color = Color3.fromRGB(140, 220, 140) },
	{ stars = 3, multiplier = 1.35, odds = 14, label = "Great", color = Color3.fromRGB(90, 170, 255) },
	{ stars = 4, multiplier = 1.6, odds = 6, label = "Superb", color = Color3.fromRGB(190, 120, 255) },
	{ stars = 5, multiplier = 2.0, odds = 2, label = "Perfect", color = Color3.fromRGB(255, 200, 40) },
}

StarConfig.MIN_STARS = 1
StarConfig.MAX_STARS = #StarConfig.Grades

-- Visual length of a fish: sizeScale * SizeMultiplier(sizeFraction). 0.85x to 1.15x.
StarConfig.SIZE_MIN = 0.85
StarConfig.SIZE_MAX = 1.15

-- ===================================================================== derived thresholds
local totalOdds = 0
for _, grade in ipairs(StarConfig.Grades) do
	totalOdds += grade.odds
end

-- Lowest quality needed for a grade, from the probability of being at least that grade
local function thresholdForUpperTail(probability)
	if probability <= 0 then
		return 1
	elseif probability >= 1 then
		return 0
	elseif probability <= 0.5 then
		return 1 - math.sqrt(probability / 2)
	else
		return math.sqrt((1 - probability) / 2)
	end
end

StarConfig.Thresholds = {} -- [stars] = minimum quality
do
	local atLeast = 1
	for index, grade in ipairs(StarConfig.Grades) do
		StarConfig.Thresholds[grade.stars] = thresholdForUpperTail(atLeast)
		atLeast -= grade.odds / totalOdds
		grade.oddsPercent = grade.odds / totalOdds * 100
		table.freeze(grade)
		assert(grade.stars == index, "StarConfig.Grades must be listed 1, 2, 3, 4, 5 in order")
	end
end
table.freeze(StarConfig.Grades)
table.freeze(StarConfig.Thresholds)

-- ===================================================================== functions
function StarConfig.Clamp(stars)
	stars = tonumber(stars) or StarConfig.MIN_STARS
	return math.clamp(math.floor(stars), StarConfig.MIN_STARS, StarConfig.MAX_STARS)
end

function StarConfig.Get(stars)
	return StarConfig.Grades[StarConfig.Clamp(stars)]
end

function StarConfig.GetMultiplier(stars)
	if stars == nil then
		return 1 -- fish saved before stars existed count as plain
	end
	return StarConfig.Get(stars).multiplier
end

function StarConfig.QualityFromRolls(weightFraction, sizeFraction)
	return (math.clamp(weightFraction, 0, 1) + math.clamp(sizeFraction, 0, 1)) / 2
end

function StarConfig.QualityToStars(quality)
	local stars = StarConfig.MIN_STARS
	for grade = StarConfig.MIN_STARS, StarConfig.MAX_STARS do
		if quality >= StarConfig.Thresholds[grade] then
			stars = grade
		end
	end
	return stars
end

function StarConfig.SizeMultiplier(sizeFraction)
	return StarConfig.SIZE_MIN + (StarConfig.SIZE_MAX - StarConfig.SIZE_MIN) * math.clamp(sizeFraction or 0.5, 0, 1)
end

-- { {stars = 1, percent = 50}, ... } for an odds UI
function StarConfig.GetOdds()
	local odds = {}
	for _, grade in ipairs(StarConfig.Grades) do
		table.insert(odds, { stars = grade.stars, percent = grade.oddsPercent })
	end
	return odds
end

-- Average multiplier of a random catch (about 1.15 with the default table)
function StarConfig.ExpectedMultiplier()
	local sum = 0
	for _, grade in ipairs(StarConfig.Grades) do
		sum += grade.multiplier * grade.odds / totalOdds
	end
	return sum
end

return StarConfig
