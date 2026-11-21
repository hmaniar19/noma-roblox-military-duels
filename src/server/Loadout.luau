--!strict
-- Loadout picks. Normal rounds: a primary, a melee and a gadget from the pre-round screen, plus the
-- pistol everyone carries. Shop weapons (A Mother's Wrath, Double Trouble) can be picked for their
-- slot once owned. Sudden Death (4-4): each team gets one sniper and one melee fighter; players ask
-- for a role and the server resolves who gets what. Picks are validated on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)

type WeaponId = Config.WeaponId
type GadgetId = Config.GadgetId
type Role = Config.Role

export type Kit = { weapons: { WeaponId }, gadget: GadgetId? }
type Choice = { primary: WeaponId, melee: WeaponId, gadget: GadgetId, role: Role? }

local Loadout = {}

-- Set by the arena registry: called after a player changes a pick so it shows during the freeze.
Loadout.onChange = function(_player: Player) end

local choices: { [Player]: Choice } = {}
local random = Random.new()

local function choiceOf(player: Player): Choice
	local c = choices[player]
	if not c then
		c = { primary = "AR", melee = Config.Loadout.Melee, gadget = "Frag", role = nil }
		choices[player] = c
	end
	return c
end

-- True if `id` may go in `slot` for this player: a standard option, or a shop weapon for that slot
-- that the server has recorded as owned (Economy publishes "Owns_<id>").
local function allowed(player: Player, slot: string, id: string): boolean
	if
		slot == "Primary" and table.find(Config.Loadout.Primary, id)
		or slot == "Melee" and id == Config.Loadout.Melee
	then
		return true
	end
	for _, w in Config.ShopWeapons do
		if w.id == id and w.slot == slot then
			return player:GetAttribute("Owns_" .. id) == true
		end
	end
	return false
end

local function meleeOf(player: Player?): WeaponId
	local c = if player then choiceOf(player) else nil
	return if c and player and allowed(player, "Melee", c.melee) then c.melee else Config.Loadout.Melee
end

function Loadout.standard(player: Player?): Kit
	local primary: WeaponId, gadget: GadgetId
	if player then
		local c = choiceOf(player)
		primary = if allowed(player, "Primary", c.primary) then c.primary else "AR"
		gadget = c.gadget
	else
		-- Bots vary their primary and carry a med kit, which they know how to use.
		primary = Config.Loadout.Primary[random:NextInteger(1, #Config.Loadout.Primary)]
		gadget = "Medkit"
	end
	return { weapons = { primary, Config.Loadout.Sidearm, meleeOf(player) }, gadget = gadget }
end

-- Each role fights with the player's own pick when it fits: a scoped primary (A Mother's Wrath) for
-- the sniper, their melee (Double Trouble) for the knife role.
function Loadout.suddenDeath(role: Role, player: Player?): Kit
	if role ~= "Sniper" then
		return { weapons = { meleeOf(player) }, gadget = nil }
	end
	local c = if player then choiceOf(player) else nil
	local own = c and player and allowed(player, "Primary", c.primary) and Config.Weapons[c.primary].scoped
	return { weapons = { if own and c then c.primary else "Sniper" }, gadget = nil }
end

-- One team's Sudden Death roles for `count` slots, in slot order; `members[i]` is nil for a bot.
-- A lone fighter gets what they asked for (default sniper). A pair gets one of each: the first
-- member's request wins, and nobody who asked is overruled unless both asked for the same role.
function Loadout.roles(members: { Player? }, count: number): { Role }
	local function wants(p: Player?): Role?
		return if p then choiceOf(p).role else nil
	end
	if count == 1 then
		return { wants(members[1]) or "Sniper" }
	end
	local first = wants(members[1])
	if not first then
		local second = wants(members[2])
		first = if second == "Sniper" then "Knife" else "Sniper"
	end
	return { first :: Role, if first == "Sniper" then "Knife" else "Sniper" }
end

-- Sudden Death role requests are per match; a stale one must not override a teammate next time.
function Loadout.resetRoles(players: { Player })
	for _, player in players do
		local c = choices[player]
		if c then
			c.role = nil
		end
		player:SetAttribute("PickRole", nil)
	end
end

function Loadout.bind()
	Net.Loadout.OnServerEvent:Connect(function(player, kind, value)
		if not Net.allow(player, "Loadout", 6, 4) or typeof(value) ~= "string" then
			return
		end
		local c = choiceOf(player)
		if (kind == "Primary" or kind == "Melee") and allowed(player, kind, value) then
			if kind == "Primary" then
				c.primary = value :: WeaponId
			else
				c.melee = value :: WeaponId
			end
		elseif kind == "Gadget" and table.find(Config.Loadout.Gadget, value :: any) then
			c.gadget = value :: GadgetId
		elseif kind == "Role" and (value == "Sniper" or value == "Knife") then
			c.role = value :: Role
		else
			return
		end
		player:SetAttribute("Pick" .. kind, value)
		Loadout.onChange(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("PickPrimary", "AR")
		player:SetAttribute("PickMelee", Config.Loadout.Melee)
		player:SetAttribute("PickGadget", "Frag")
	end)
	Players.PlayerRemoving:Connect(function(player)
		choices[player] = nil
	end)
end

return Loadout
