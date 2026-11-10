--[[
	ItemRegistry  (ModuleScript)
	Put in: ReplicatedStorage > Items > Modules > ItemRegistry

	One place to look up ANY item in Steal a Fish by its id, or list a whole category.

		local ItemRegistry = require(path.to.ItemRegistry)

		local bangus, category = ItemRegistry.Get("fish_bangus")  --> fish table, "Fish"
		local allNets = ItemRegistry.List("Net")                   --> array sorted by tier
		local mythics = ItemRegistry.ListFishByRarity("Mythic")    --> array of fish tables
		local nextNet = ItemRegistry.GetNext("net_pukot")          --> the tier above (or nil)

	Categories: Fish, Net, Tank, Lock, Boost, BangkaSkin, Hat, GamePass, DevProduct

	SERVER-AUTHORITATIVE TIP: clients may send you an item id (for example "buy net_pukot").
	Always check it with ItemRegistry.Exists(id) and read the price/stats from HERE on the
	server. Never trust a price or stat that the client sends.
]]

local FishData = require(script.Parent.FishData)
local NetData = require(script.Parent.NetData)
local TankData = require(script.Parent.TankData)
local LockData = require(script.Parent.LockData)
local BoostData = require(script.Parent.BoostData)
local CosmeticData = require(script.Parent.CosmeticData)
local ShopData = require(script.Parent.ShopData)

local ItemRegistry = {}

-- Display order for shops and inventories
ItemRegistry.Categories = { "Fish", "Net", "Tank", "Lock", "Boost", "BangkaSkin", "Hat", "GamePass", "DevProduct" }

-- Where each category's list lives
local SOURCES = {
	Fish = FishData.List,
	Net = NetData.List,
	Tank = TankData.List,
	Lock = LockData.List,
	Boost = BoostData.List,
	BangkaSkin = CosmeticData.BangkaSkins,
	Hat = CosmeticData.Hats,
	GamePass = ShopData.GamePasses,
	DevProduct = ShopData.DevProducts,
}

local itemById = {} -- [itemId] = item table
local categoryById = {} -- [itemId] = "Fish" / "Net" / ...
local listByCategory = {} -- [category] = array sorted by `order`

-- Build the lookup tables once, when the module is first required
for _, category in ipairs(ItemRegistry.Categories) do
	local list = SOURCES[category]
	assert(list ~= nil, "ItemRegistry: no data list for category " .. category)

	local sorted = table.clone(list) -- the original lists are frozen, so sort a copy
	table.sort(sorted, function(a, b)
		return a.order < b.order
	end)
	listByCategory[category] = sorted

	for _, item in ipairs(list) do
		if itemById[item.id] ~= nil then
			error("ItemRegistry: duplicate item id '" .. item.id .. "' (ids must be unique across ALL categories)")
		end
		itemById[item.id] = item
		categoryById[item.id] = category
	end
end

-- Returns the item table and its category, or nil if the id doesn't exist.
function ItemRegistry.Get(itemId)
	return itemById[itemId], categoryById[itemId]
end

-- True if the id is a real item. Use it to validate ids that came from a client.
function ItemRegistry.Exists(itemId)
	return type(itemId) == "string" and itemById[itemId] ~= nil
end

-- "Fish", "Net", ... or nil
function ItemRegistry.GetCategory(itemId)
	return categoryById[itemId]
end

-- All items in a category (a fresh array you may sort or filter freely).
function ItemRegistry.List(category)
	local list = listByCategory[category]
	if list == nil then
		warn("ItemRegistry.List: unknown category '" .. tostring(category) .. "'")
		return {}
	end
	return table.clone(list)
end

-- Fish of one rarity ("Common", "Rare", "Epic", "Legendary", "Mythic").
function ItemRegistry.ListFishByRarity(rarity)
	local result = {}
	for _, fish in ipairs(listByCategory.Fish) do
		if fish.rarity == rarity then
			table.insert(result, fish)
		end
	end
	return result
end

-- Nets, tanks and locks have tiers. Returns the item with that tier, or nil.
function ItemRegistry.GetByTier(category, tier)
	for _, item in ipairs(listByCategory[category] or {}) do
		if item.tier == tier then
			return item
		end
	end
	return nil
end

-- The next upgrade after this item in the same category (great for "Upgrade" buttons).
function ItemRegistry.GetNext(itemId)
	local category = categoryById[itemId]
	if category == nil then
		return nil
	end
	local list = listByCategory[category]
	for index, item in ipairs(list) do
		if item.id == itemId then
			return list[index + 1]
		end
	end
	return nil
end

-- Total number of items (65 at the time of writing).
function ItemRegistry.Count()
	local count = 0
	for _ in pairs(itemById) do
		count += 1
	end
	return count
end

return ItemRegistry
