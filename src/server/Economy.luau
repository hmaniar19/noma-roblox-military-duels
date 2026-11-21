--!strict
-- Coins and weapon skins. Coins are only earned by playing (Noelle's payout rules in Config.Payouts)
-- and only the server changes them. Profiles are saved with DataStoreService; when saving isn't
-- available (Studio without API access) the game keeps working and profiles last for the session.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)

type Profile = {
	coins: number,
	owned: { [string]: boolean },
	equipped: { [string]: string }, -- weapon id -> skin id
	beginnersLuck: boolean, -- true once the one-time bonus has been paid
}

local Economy = {}

local okStore, store = pcall(function()
	return DataStoreService:GetDataStore("MilitaryDuels_v1")
end)
local profiles: { [Player]: Profile } = {}
local loaded: { [Player]: boolean } = {}
local warnedNoSave = false

local SKINS: { [string]: { id: string, name: string, price: number } } = {}
for _, s in Config.Skins do
	SKINS[s.id] = s
end

local function key(player: Player): string
	return `player_{player.UserId}`
end

-- Mirrors the profile onto read-only player attributes for the HUD, shop and inventory.
local function publish(player: Player, p: Profile)
	player:SetAttribute("Coins", p.coins)
	local owned = {}
	for id in p.owned do
		table.insert(owned, id)
	end
	table.sort(owned)
	player:SetAttribute("OwnedSkins", table.concat(owned, ","))
	for weapon in Config.Weapons do
		player:SetAttribute("Skin_" .. weapon, p.equipped[weapon] or "Standard")
	end
end

local function save(player: Player)
	local p = profiles[player]
	if not p or not loaded[player] or not okStore then
		return
	end
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(key(player), p)
	end)
	if not ok and not warnedNoSave then
		warnedNoSave = true
		warn(`[Economy] saving is unavailable ({err}); coins last for this session only`)
	end
end

local function load(player: Player)
	local data: any = nil
	if okStore then
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			data = result
			loaded[player] = true
		elseif not warnedNoSave then
			warnedNoSave = true
			warn(`[Economy] loading is unavailable ({result}); coins last for this session only`)
		end
	end
	local p: Profile = {
		coins = if typeof(data) == "table" and typeof(data.coins) == "number" then data.coins else 0,
		owned = if typeof(data) == "table" and typeof(data.owned) == "table" then data.owned else {},
		equipped = if typeof(data) == "table" and typeof(data.equipped) == "table" then data.equipped else {},
		beginnersLuck = typeof(data) == "table" and data.beginnersLuck == true,
	}
	p.owned.Standard = true
	if player.Parent == nil then
		return
	end
	profiles[player] = p
	if not p.beginnersLuck then
		p.beginnersLuck = true
		p.coins += Config.Payouts.BeginnersLuck
		Net.Toast:FireClient(player, "beginnersluck", `+{Config.Payouts.BeginnersLuck} coins to get you started!`)
		save(player)
	end
	publish(player, p)
end

function Economy.award(player: Player, amount: number, reason: string)
	local p = profiles[player]
	if not p or amount <= 0 then
		return
	end
	p.coins += amount
	publish(player, p)
	Net.Toast:FireClient(player, `+{amount} coins`, reason)
	save(player)
end

function Economy.skinFor(player: Player?, weapon: string): string?
	local p = if player then profiles[player] else nil
	return if p then p.equipped[weapon] else nil
end

-- "Name  1,234" lines for the top players in this server.
function Economy.leaderboard(count: number): string
	local rows = {}
	for player, p in profiles do
		table.insert(rows, { name = player.DisplayName, coins = p.coins })
	end
	table.sort(rows, function(a, b)
		return a.coins > b.coins
	end)
	local lines = { "TOP SOLDIERS" }
	for i = 1, math.min(count, #rows) do
		table.insert(lines, `{i}. {rows[i].name}   {rows[i].coins} coins`)
	end
	return table.concat(lines, "\n")
end

function Economy.bind()
	Net.Shop.OnServerEvent:Connect(function(player, action, a, b)
		local p = profiles[player]
		if not p or not Net.allow(player, "Shop", 4, 4) then
			return
		end
		if action == "Buy" and typeof(a) == "string" and SKINS[a] then
			local skin = SKINS[a]
			if p.owned[a] then
				return
			end
			if p.coins < skin.price then
				Net.Toast:FireClient(player, "Not enough coins", `{skin.name} costs {skin.price}`)
				return
			end
			p.coins -= skin.price
			p.owned[a] = true
			publish(player, p)
			Net.Toast:FireClient(player, "Unlocked!", `{skin.name} skin. Equip it in your Inventory.`)
			save(player)
		elseif
			action == "Equip"
			and typeof(a) == "string"
			and Config.Weapons[a]
			and typeof(b) == "string"
			and p.owned[b]
		then
			p.equipped[a] = b
			publish(player, p)
			save(player)
		end
	end)
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		loaded[player] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			save(player)
		end
	end)
end

return Economy
