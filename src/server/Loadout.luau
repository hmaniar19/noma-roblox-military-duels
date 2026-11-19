--!strict
-- Loadout picks. Normal rounds: a primary and a gadget from the pre-round screen, plus the pistol and
-- the knife everyone carries. Sudden Death (4-4): each team gets one sniper and one knife; players
-- ask for a role and the server resolves who gets what. Picks are validated against Config.Loadout.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)

type WeaponId = Config.WeaponId
type GadgetId = Config.GadgetId
type Role = Config.Role

export type Kit = { weapons: { WeaponId }, gadget: GadgetId? }
type Choice = { primary: WeaponId, gadget: GadgetId, role: Role? }

local Loadout = {}

-- Set by Match: called after a player changes a pick so the change shows up during the freeze.
Loadout.onChange = function(_player: Player) end

local choices: { [Player]: Choice } = {}
local random = Random.new()

local function choiceOf(player: Player): Choice
	local c = choices[player]
	if not c then
		c = { primary = "AR", gadget = "Frag", role = nil }
		choices[player] = c
	end
	return c
end

function Loadout.standard(player: Player?): Kit
	local primary: WeaponId, gadget: GadgetId
	if player then
		local c = choiceOf(player)
		primary, gadget = c.primary, c.gadget
	else
		-- Bots vary their primary and carry a med kit, which they know how to use.
		primary = Config.Loadout.Primary[random:NextInteger(1, #Config.Loadout.Primary)]
		gadget = "Medkit"
	end
	return { weapons = { primary, Config.Loadout.Sidearm, Config.Loadout.Melee }, gadget = gadget }
end

function Loadout.suddenDeath(role: Role): Kit
	return { weapons = { if role == "Sniper" then "Sniper" else "Knife" }, gadget = nil }
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
function Loadout.resetRoles()
	for player, c in choices do
		c.role = nil
		player:SetAttribute("PickRole", nil)
	end
end

function Loadout.bind()
	Net.Loadout.OnServerEvent:Connect(function(player, kind, value)
		if not Net.allow(player, "Loadout", 6, 4) or typeof(value) ~= "string" then
			return
		end
		local c = choiceOf(player)
		if kind == "Primary" and table.find(Config.Loadout.Primary, value :: any) then
			c.primary = value :: WeaponId
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
		player:SetAttribute("PickGadget", "Frag")
	end)
	Players.PlayerRemoving:Connect(function(player)
		choices[player] = nil
	end)
end

return Loadout
