--!strict
-- Player profiles: coins, owned items, XP and level, rank points, the HUD theme, the finisher style
-- and the starter pick. Coins and XP are only earned by playing (Noelle's rules in Config.Payouts and
-- Config.Xp) and only the server changes them. Profiles are saved with DataStoreService; when saving
-- isn't available (Studio without API access) the game keeps working and profiles last for the session.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	starterSkin: string?, -- free starter colour, usable only on the starter weapon
	bootcamp: boolean, -- Bot Bootcamp: flagged for cheating, matched only against perfect bots
	cleanStreak: number, -- zero-flag matches in a row while in Bot Bootcamp
	wins: number,
	losses: number, -- leaving mid-match counts as a loss
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
	player:SetAttribute("Bootcamp", p.bootcamp)
	player:SetAttribute("CleanStreak", p.cleanStreak)
	local owned, skins = folder(player, "Owned"), folder(player, "Skins")
	for id in CATALOG do
		owned:SetAttribute(id, if owns(player, p, id) then true else nil)
	end
	for weapon in Config.Weapons do
		skins:SetAttribute(weapon, p.equipped[weapon] or "Standard")
	end
end

-- One write in flight per player; markDirty queues a save that the loop in bind sends at most every
-- SAVE_GAP seconds. Session locking: the saved record names the server that owns it ("lock"); a save
-- only writes while this server still owns the lock, so an old server can never overwrite a newer
-- session after a quick rejoin. Saves refresh the lock; the final save releases it.
local SAVE_GAP, LOCK_TTL = 6, 60
local JOB = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
local dirty: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {}
local lastSave: { [Player]: number } = {}

local function markDirty(player: Player)
	dirty[player] = true
end

local function save(player: Player, release: boolean?)
	local p = profiles[player]
	if not p or not loaded[player] or not okStore or saving[player] then
		return
	end
	saving[player], dirty[player], lastSave[player] = true, nil, os.clock()
	local snap: any = table.clone(p)
	snap.owned, snap.equipped = table.clone(p.owned), table.clone(p.equipped)
	snap.lock = if release then nil else { job = JOB, at = os.time() }
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(player), function(old: any)
			local lock = if typeof(old) == "table" and typeof(old.lock) == "table" then old.lock else nil
			if lock and lock.job ~= JOB then
				warn(`[Economy] not saving {player.UserId}: another server now owns this profile`)
				return nil
			end
			return snap
		end)
	end)
	saving[player] = nil
	if not ok then
		dirty[player] = true -- retried by the save loop
		if not warnedNoSave then
			warnedNoSave = true
			warn(`[Economy] saving is unavailable ({err}); progress lasts for this session only`)
		end
	end
end

-- Waits out any write in flight, then saves now (leaving and shutdown), retrying a failed write a
-- few times since the player's progress is gone once they leave; `release` frees the lock.
local function flush(player: Player, release: boolean?)
	for _ = 1, 3 do
		while saving[player] do
			task.wait()
		end
		save(player, release)
		if not dirty[player] then
			return
		end
		task.wait(1)
	end
end

-- Claims the profile for this server. A live lock held by another server (refreshed every 30 s) is
-- honored: wait up to ~30 s for that server's final save, else play this visit without saving.
-- Returns ok and the data.
local function claim(player: Player): (boolean, any)
	for _ = 1, 10 do
		local claimed, data = false, nil
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(player), function(old: any)
				local lock = if typeof(old) == "table" and typeof(old.lock) == "table" then old.lock else nil
				if lock and lock.job ~= JOB and typeof(lock.at) == "number" and os.time() - lock.at < LOCK_TTL then
					return nil
				end
				local record = if typeof(old) == "table" then old else {}
				record.lock = { job = JOB, at = os.time() }
				claimed, data = true, old
				return record
			end)
		end)
		if not ok then
			return false, err
		elseif claimed then
			return true, data
		end
		task.wait(3)
	end
	return false, "profile is busy on another server"
end

-- Frees this server's lock without writing a profile (a claim that finished after the player left).
local function unlock(player: Player)
	pcall(function()
		(store :: DataStore):UpdateAsync(key(player), function(old: any)
			if typeof(old) == "table" and typeof(old.lock) == "table" and old.lock.job == JOB then
				old.lock = nil
				return old
			end
			return nil
		end)
	end)
end

local function field(data: any, name: string, kind: string): any
	return if typeof(data) == "table" and typeof(data[name]) == kind then data[name] else nil
end

local function count(data: any, name: string, default: number): number
	local n = field(data, name, "number")
	return if n and n == n then math.clamp(math.floor(n), 0, 1e9) else default
end

local function isSkin(id: any): boolean
	return id == "Standard" or (typeof(id) == "string" and CATALOG[id] ~= nil and CATALOG[id].kind == "Skin")
end

local function known(id: any, list: { any }): string?
	for _, entry in list do
		if id == (if typeof(entry) == "table" then entry.id else entry) then
			return id
		end
	end
	return nil
end

local function load(player: Player)
	local data: any = nil
	local readOk = false
	if okStore then
		local ok, result = claim(player)
		if ok then
			data, readOk = result, true
		else
			warn(`[Economy] could not load {player.UserId} ({result}); progress lasts for this session only`)
		end
	end
	local owned, equipped = {}, {}
	for id, v in field(data, "owned", "table") or {} do
		if typeof(id) == "string" and CATALOG[id] and v == true then
			owned[id] = true
		end
	end
	for weapon, skin in field(data, "equipped", "table") or {} do
		if typeof(weapon) == "string" and Config.Weapons[weapon] and isSkin(skin) then
			equipped[weapon] = skin
		end
	end
	local p: Profile = {
		coins = count(data, "coins", 0),
		owned = owned,
		equipped = equipped,
		beginnersLuck = field(data, "beginnersLuck", "boolean") == true,
		hudTheme = known(field(data, "hudTheme", "string"), Config.HudThemes),
		xp = count(data, "xp", 0),
		rp = count(data, "rp", Config.RankedStart),
		ranked = field(data, "ranked", "boolean") == true,
		finisher = known(field(data, "finisher", "string"), Config.Finishers) or Config.Finishers[1].id,
		starter = known(field(data, "starter", "string"), Config.Starter.Weapons),
		starterSkin = known(field(data, "starterSkin", "string"), Config.Starter.Colors),
		bootcamp = field(data, "bootcamp", "boolean") == true,
		cleanStreak = math.min(count(data, "cleanStreak", 0), Config.BootcampCleanMatches),
		wins = count(data, "wins", 0),
		losses = count(data, "losses", 0),
	}
	p.owned.Standard = true
	if player.Parent == nil then
		if readOk then
			unlock(player) -- they left while the profile loaded
		end
		return
	end
	profiles[player], loaded[player] = p, readOk
	if okStore and not readOk then
		Net.Toast:FireClient(player, "Progress not saving", "Your coins and XP will last for this visit only.")
		-- Without the saved record we can't know whether this account is in Bot Bootcamp, so live
		-- servers keep it to bot matches for this visit (never saved). Studio has no saves to read.
		if not RunService:IsStudio() then
			p.bootcamp = true
		end
	end
	if p.starter then
		Loadout.choose(player, "Primary", p.starter)
	end
	-- An unread profile may already have had its grant: only a verified (or Studio) profile gets it.
	if not p.beginnersLuck and (readOk or not okStore or RunService:IsStudio()) then
		p.beginnersLuck = true
		p.coins += Config.Payouts.BeginnersLuck
		Net.Toast:FireClient(player, "beginnersluck", `+{Config.Payouts.BeginnersLuck} coins to get you started!`)
		markDirty(player)
	end
	publish(player, p) -- every profile, new or returning: the queue waits for these attributes
end

function Economy.award(player: Player, amount: number, reason: string)
	local p = profiles[player]
	if not p or amount <= 0 then
		return
	end
	p.coins += amount
	publish(player, p)
	Net.Toast:FireClient(player, `+{amount} coins`, reason)
	markDirty(player)
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
	markDirty(player)
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
	markDirty(player)
end

-- Bot Bootcamp on (flagged by AntiCheat) or off. Either way the clean-match count starts over.
function Economy.setBootcamp(player: Player, on: boolean)
	local p = profiles[player]
	if not p or p.bootcamp == on then
		return
	end
	p.bootcamp, p.cleanStreak = on, 0
	publish(player, p)
	markDirty(player)
end

-- Every finished or abandoned match. In Bot Bootcamp a clean match (zero flags) counts toward
-- getting out and any other match starts the count over.
function Economy.matchResult(player: Player, won: boolean, clean: boolean)
	local p = profiles[player]
	if not p then
		return
	end
	if won then
		p.wins += 1
	else
		p.losses += 1
	end
	-- An unread profile on a live server is held in Bootcamp for the whole visit (see load).
	local verified = loaded[player] or not okStore or RunService:IsStudio()
	if p.bootcamp and verified then
		p.cleanStreak = if clean then p.cleanStreak + 1 else 0
		if p.cleanStreak >= Config.BootcampCleanMatches then
			p.bootcamp, p.cleanStreak = false, 0
			Net.Toast:FireClient(player, "Out of Bot Bootcamp!", "You're back in matches with other players.")
		end
	end
	publish(player, p)
	markDirty(player)
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
function Economy.leaderboard(rowsShown: number): string
	local rows = {}
	for player, p in profiles do
		table.insert(rows, { name = player.DisplayName, coins = p.coins, rp = p.rp, ranked = p.ranked })
	end
	table.sort(rows, function(a, b)
		return a.coins > b.coins
	end)
	local lines = { "TOP SOLDIERS" }
	for i = 1, math.min(rowsShown, #rows) do
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
		local theme = known(a, Config.HudThemes)
		if not theme or theme == p.hudTheme then
			return
		end
		p.hudTheme = theme
	elseif setting == "Ranked" and typeof(a) == "boolean" then
		if a == p.ranked or player:GetAttribute("Arena") ~= nil or player:GetAttribute("Queued") then
			return
		end
		p.ranked = a
	elseif
		setting == "Starter"
		and not p.starter
		and table.find(Config.Starter.Weapons, a)
		and table.find(Config.Starter.Colors, b)
	then
		-- A free starter weapon color, equipped on the starter weapon, which becomes the default primary.
		p.starter, p.starterSkin = a, b
		p.equipped[a] = b
		Loadout.choose(player, "Primary", a)
	else
		return
	end
	publish(player, p)
	markDirty(player)
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
			markDirty(player)
		elseif
			action == "EquipFinisher"
			and typeof(a) == "string"
			and a ~= p.finisher
			and owns(player, p, "Finisher_" .. a)
		then
			p.finisher = a
			publish(player, p)
			markDirty(player)
		elseif
			action == "Equip"
			and typeof(a) == "string"
			and Config.Weapons[a]
			and typeof(b) == "string"
			and CATALOG[b]
			and CATALOG[b].kind == "Skin"
			and (owns(player, p, b) or (b == p.starterSkin and a == p.starter))
			and p.equipped[a] ~= b
		then
			p.equipped[a] = b
			publish(player, p)
			markDirty(player)
		end
	end)
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- Deferred so the other leave handlers run first: Lobby saves a mid-match leave as a loss.
		task.defer(function()
			flush(player, true)
			profiles[player], loaded[player], dirty[player], lastSave[player] = nil, nil, nil, nil
		end)
	end)
	task.spawn(function()
		local refreshed = os.clock()
		while true do
			task.wait(1)
			if os.clock() - refreshed > 30 then
				refreshed = os.clock() -- keep this server's locks fresh for players who aren't earning
				for player in loaded do
					dirty[player] = true
				end
			end
			for player in dirty do
				if os.clock() - (lastSave[player] or 0) >= SAVE_GAP then
					task.spawn(save, player)
				end
			end
		end
	end)
	game:BindToClose(function()
		local left = 0
		for _, player in Players:GetPlayers() do
			left += 1
			task.spawn(function()
				flush(player, true)
				left -= 1
			end)
		end
		while left > 0 do
			task.wait()
		end
	end)
end

return Economy
