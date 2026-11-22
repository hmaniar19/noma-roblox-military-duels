--!strict
-- Player profiles: coins, owned items, XP and level, rank points, the HUD theme, the finisher style
-- and the starter pick. Coins and XP are only earned by playing (Noelle's rules in Config.Payouts and
-- Config.Xp) and only the server changes them. Profiles are saved with DataStoreService; when saving
-- isn't available (Studio without API access) the game keeps working and profiles last for the session.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Loadout = require(script.Parent.Loadout)
local Net = require(script.Parent.Net)

type Profile = {
	coins: number,
	owned: { [string]: boolean }, -- skins, shop weapons, and finishers as "Finisher_<id>"
	equipped: { [string]: string }, -- weapon id -> skin id
	beginnersLuck: boolean, -- true once the one-time bonus has been paid
	hudTheme: string?, -- Config.HudThemes id; nil until the first-join pick
	xp: number,
	rp: number, -- rank points
	ranked: boolean, -- the player's ranked toggle
	finisher: string, -- Config.Finishers id
	starter: string?, -- starter weapon; nil until the first-join pick
}

local Economy = {}

local okStore, store = pcall(function()
	return DataStoreService:GetDataStore("MilitaryDuels_v1")
end)
local profiles: { [Player]: Profile } = {}
local loaded: { [Player]: boolean } = {}
local warnedNoSave = false

-- Everything coins can buy, by id.
type Item = { name: string, price: number, kind: string }
local CATALOG: { [string]: Item } = {}
for _, s in Config.Skins do
	CATALOG[s.id] = { name = s.name, price = s.price, kind = "Skin" }
end
for _, w in Config.ShopWeapons do
	CATALOG[w.id] = { name = Config.Weapons[w.id].name, price = w.price, kind = "Weapon" }
end
for _, f in Config.Finishers do
	CATALOG["Finisher_" .. f.id] = { name = f.name, price = f.price, kind = "Finisher" }
end

local function key(player: Player): string
	return `player_{player.UserId}`
end

-- Level for a total XP: level L -> L+1 costs Base + PerLevel * L.
local function levelOf(xp: number): (number, number, number)
	local level, need = 1, Config.Xp.Base + Config.Xp.PerLevel
	while xp >= need do
		xp -= need
		level += 1
		need = Config.Xp.Base + Config.Xp.PerLevel * level
	end
	return level, xp, need
end

local function unlockedAt(id: string): number?
	for _, u in Config.Unlocks do
		if u.id == id then
			return u.level
		end
	end
	return nil
end

-- Owned: bought, free, reached by level, or a developer (who owns the whole catalog).
local function owns(player: Player, p: Profile, id: string): boolean
	local item = CATALOG[id]
	local level = unlockedAt(id)
	return p.owned[id] == true
		or (item ~= nil and item.price == 0)
		or (level ~= nil and levelOf(p.xp) >= level)
		or (Config.Developers[player.UserId] ~= nil and item ~= nil)
end

-- A child folder of the player (made once), for data published apart from the player's own
-- attributes: Roblox caps one instance's attributes at 1024 bytes in total.
local function folder(player: Player, name: string): Folder
	local existing = player:FindFirstChild(name)
	if existing then
		return existing :: Folder
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = player
	return f
end

-- Mirrors the profile onto read-only attributes for the HUD, shop and inventory (read with
-- Shared.Profile): ownership in player.Owned, equipped skins in player.Skins.
local function publish(player: Player, p: Profile)
	local level, into, need = levelOf(p.xp)
	player:SetAttribute("Coins", p.coins)
	player:SetAttribute("XP", p.xp)
	player:SetAttribute("Level", level)
	player:SetAttribute("XpInto", into)
	player:SetAttribute("XpNeed", need)
	player:SetAttribute("RP", p.rp)
	player:SetAttribute("RankedUnlocked", level >= (unlockedAt("Ranked") or 0))
	player:SetAttribute("Ranked", p.ranked and level >= (unlockedAt("Ranked") or 0))
	player:SetAttribute("Title", if level >= (unlockedAt("EddiesHonor") or math.huge) then "EddiesHonor" else nil)
	player:SetAttribute("Finisher", p.finisher)
	player:SetAttribute("StarterPicked", p.starter ~= nil)
	player:SetAttribute("HudTheme", p.hudTheme or Config.HudThemes[1].id)
	player:SetAttribute("ThemePicked", p.hudTheme ~= nil) -- false shows the first-join picker
	local owned, skins = folder(player, "Owned"), folder(player, "Skins")
	for id in CATALOG do
		owned:SetAttribute(id, if owns(player, p, id) then true else nil)
	end
	for weapon in Config.Weapons do
		skins:SetAttribute(weapon, p.equipped[weapon] or "Standard")
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
		warn(`[Economy] saving is unavailable ({err}); progress lasts for this session only`)
	end
end

local function field(data: any, name: string, kind: string): any
	return if typeof(data) == "table" and typeof(data[name]) == kind then data[name] else nil
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
			warn(`[Economy] loading is unavailable ({result}); progress lasts for this session only`)
		end
	end
	local p: Profile = {
		coins = field(data, "coins", "number") or 0,
		owned = field(data, "owned", "table") or {},
		equipped = field(data, "equipped", "table") or {},
		beginnersLuck = field(data, "beginnersLuck", "boolean") == true,
		hudTheme = field(data, "hudTheme", "string"),
		xp = field(data, "xp", "number") or 0,
		rp = field(data, "rp", "number") or Config.RankedStart,
		ranked = field(data, "ranked", "boolean") == true,
		finisher = field(data, "finisher", "string") or Config.Finishers[1].id,
		starter = field(data, "starter", "string"),
	}
	p.owned.Standard = true
	if player.Parent == nil then
		return
	end
	profiles[player] = p
	if p.starter then
		Loadout.choose(player, "Primary", p.starter)
	end
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
	task.spawn(save, player) -- DataStore writes yield; the match loop that pays out must not wait
end

-- XP for a finished match; announces level-ups and anything they unlock.
function Economy.awardXp(player: Player, amount: number)
	local p = profiles[player]
	if not p or amount <= 0 then
		return
	end
	local before = levelOf(p.xp)
	p.xp += amount
	local after = levelOf(p.xp)
	publish(player, p)
	if after > before then
		local unlocked = {}
		for _, u in Config.Unlocks do
			if u.level > before and u.level <= after then
				table.insert(unlocked, u.name)
			end
		end
		local sub = if #unlocked > 0 then `Unlocked: {table.concat(unlocked, ", ")}` else `+{amount} XP`
		Net.Toast:FireClient(player, `LEVEL {after}!`, sub)
	end
	task.spawn(save, player)
end

-- Ranked: a win moves RankedSwing points from the loser to the winner. Only counts for players
-- with ranked on (level 50+).
function Economy.ranked(player: Player, won: boolean)
	local p = profiles[player]
	if not p or not player:GetAttribute("Ranked") then
		return
	end
	p.rp = math.max(0, p.rp + (if won then Config.RankedSwing else -Config.RankedSwing))
	publish(player, p)
	task.spawn(save, player)
end

-- The winner's finisher ink color for the round-win cutscene.
function Economy.finisherInk(player: Player?): Color3?
	local p = if player then profiles[player] else nil
	for _, f in Config.Finishers do
		if p and f.id == p.finisher then
			return f.ink
		end
	end
	return nil
end

-- Leaderboard text: the richest players and, when anyone plays ranked, the top rank points.
function Economy.leaderboard(count: number): string
	local rows = {}
	for player, p in profiles do
		table.insert(rows, { name = player.DisplayName, coins = p.coins, rp = p.rp, ranked = p.ranked })
	end
	table.sort(rows, function(a, b)
		return a.coins > b.coins
	end)
	local lines = { "TOP SOLDIERS" }
	for i = 1, math.min(count, #rows) do
		table.insert(lines, `{i}. {rows[i].name}   {rows[i].coins} coins`)
	end
	table.sort(rows, function(a, b)
		return a.rp > b.rp
	end)
	local ranked = 0
	for _, r in rows do
		if r.ranked and ranked < 3 then
			ranked += 1
			if ranked == 1 then
				table.insert(lines, "RANKED")
			end
			table.insert(lines, `{ranked}. {r.name}   {r.rp} RP`)
		end
	end
	return table.concat(lines, "\n")
end

local function settings(player: Player, p: Profile, setting: any, a: any, b: any)
	if setting == "Theme" then
		for _, t in Config.HudThemes do
			if t.id == a then
				p.hudTheme = t.id
			end
		end
	elseif setting == "Ranked" and typeof(a) == "boolean" then
		p.ranked = a
	elseif
		setting == "Starter"
		and not p.starter
		and table.find(Config.Starter.Weapons, a)
		and table.find(Config.Starter.Colors, b)
	then
		-- A free starter weapon color, equipped on the starter weapon, which becomes the default primary.
		p.starter = a
		p.owned[b] = true
		p.equipped[a] = b
		Loadout.choose(player, "Primary", a)
	else
		return
	end
	publish(player, p)
	task.spawn(save, player)
end

function Economy.bind()
	Net.Settings.OnServerEvent:Connect(function(player, setting, a, b)
		local p = profiles[player]
		if p and Net.allow(player, "Settings", 4, 2) then
			settings(player, p, setting, a, b)
		end
	end)
	Net.Shop.OnServerEvent:Connect(function(player, action, a, b)
		local p = profiles[player]
		if not p or not Net.allow(player, "Shop", 4, 4) then
			return
		end
		if action == "Buy" and typeof(a) == "string" and CATALOG[a] then
			local item = CATALOG[a]
			if owns(player, p, a) then
				return
			end
			if p.coins < item.price then
				Net.Toast:FireClient(player, "Not enough coins", `{item.name} costs {item.price}`)
				return
			end
			p.coins -= item.price
			p.owned[a] = true
			publish(player, p)
			local how = if item.kind == "Weapon"
				then "Pick it on the loadout screen."
				elseif item.kind == "Finisher" then "Equip it in the shop's FINISHERS tab."
				else "Equip it in your Inventory."
			Net.Toast:FireClient(player, "Unlocked!", `{item.name}. {how}`)
			save(player)
		elseif action == "EquipFinisher" and typeof(a) == "string" and owns(player, p, "Finisher_" .. a) then
			p.finisher = a
			publish(player, p)
			task.spawn(save, player)
		elseif
			action == "Equip"
			and typeof(a) == "string"
			and Config.Weapons[a]
			and typeof(b) == "string"
			and owns(player, p, b)
			and CATALOG[b]
			and CATALOG[b].kind == "Skin"
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
