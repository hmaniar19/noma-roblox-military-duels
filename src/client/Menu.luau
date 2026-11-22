--!strict
-- Pre-round loadout screen (primary + gadget; Sudden Death: sniper or knife). Picks go to the
-- server, which validates them and previews the real kit in your hands during the freeze. The
-- 1v1/2v2 choice lives on the Camp More Maniar lobby bar (Lobby.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Theme = require(script.Parent.Theme)
local Weapon = require(script.Parent.Weapon)

local player = Players.LocalPlayer :: Player
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local state = require(script.Parent.ArenaState)
local LoadoutRemote = remotes:WaitForChild("Loadout") :: RemoteEvent

local FONT = Enum.Font.GothamBlack
local IDLE = Color3.fromRGB(28, 34, 46)
local PICKED = Config.HudThemes[1].accent -- follows the HUD theme (Theme.watch below)

local gui = Instance.new("ScreenGui")
gui.Name = "DuelMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local function panel(title: string, y: number): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.fromScale(0.5, y)
	f.Size = UDim2.fromOffset(940, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	f.BackgroundTransparency = 0.2
	f.Visible = false
	f.Parent = gui
	Instance.new("UICorner").Parent = f
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = f
	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.fromOffset(920, 30)
	heading.BackgroundTransparency = 1
	heading.Font = FONT
	heading.TextSize = 22
	heading.TextColor3 = Color3.new(1, 1, 1)
	heading.Text = title
	heading.LayoutOrder = 0
	heading.Parent = f
	return f, heading
end

type Row = { [string]: TextButton }

-- A row of buttons; clicking one calls `pick(value)`. Returns the buttons by value.
local function row(
	parent: Frame,
	order: number,
	label: string,
	options: { string },
	names: { [string]: string },
	pick: (string) -> ()
): Row
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(920, 46)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = order
	holder.Parent = parent
	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.fromOffset(110, 46)
	caption.BackgroundTransparency = 1
	caption.Font = FONT
	caption.TextSize = 14
	caption.TextColor3 = Color3.fromRGB(200, 205, 215)
	caption.Text = label
	caption.Parent = holder
	local buttons: Row = {}
	for i, value in options do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(150, 42)
		b.Position = UDim2.fromOffset(120 + (i - 1) * 160, 2)
		b.Font = FONT
		b.TextSize = 16
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = names[value] or value
		b.TextWrapped = true
		b.AutoButtonColor = true
		b.Modal = true -- frees the mouse from first-person lock while the menu is open
		b.Parent = holder
		Instance.new("UICorner").Parent = b
		b.Activated:Connect(function()
			pick(value)
		end)
		buttons[value] = b
	end
	return buttons
end

local weaponNames: { [string]: string } = {}
for id, w in Config.Weapons do
	weaponNames[id] = w.name
end
local gadgetNames: { [string]: string } = {}
for id, g in Config.Gadgets do
	gadgetNames[id :: string] = (g :: any).name
end

-- Each slot's standard options, then the shop weapons for that slot (shown only when owned).
local function options(slot: string, standard: { string }): { string }
	local list = table.clone(standard)
	for _, w in Config.ShopWeapons do
		if w.slot == slot then
			table.insert(list, w.id)
		end
	end
	return list
end

local loadoutPanel, loadoutTitle = panel("CHOOSE YOUR LOADOUT", 0.52)
Theme.watch(function(t)
	PICKED = t.accent
	loadoutPanel.BackgroundColor3 = t.primary
end)
local primaryRow = row(loadoutPanel, 1, "PRIMARY", options("Primary", Config.Loadout.Primary), weaponNames, function(v)
	LoadoutRemote:FireServer("Primary", v)
end)
local meleeRow = row(loadoutPanel, 2, "MELEE", options("Melee", { Config.Loadout.Melee }), weaponNames, function(v)
	LoadoutRemote:FireServer("Melee", v)
end)
local gadgetRow = row(loadoutPanel, 3, "GADGET", Config.Loadout.Gadget :: { string }, gadgetNames, function(v)
	LoadoutRemote:FireServer("Gadget", v)
end)
local roleRow = row(loadoutPanel, 4, "ROLE", { "Sniper", "Knife" }, { Sniper = "Sniper", Knife = "Melee" }, function(v)
	LoadoutRemote:FireServer("Role", v)
end)
local note = Instance.new("TextLabel")
note.Size = UDim2.fromOffset(920, 22)
note.BackgroundTransparency = 1
note.Font = Enum.Font.GothamMedium
note.TextSize = 14
note.TextColor3 = Color3.fromRGB(200, 205, 215)
note.LayoutOrder = 5
note.Parent = loadoutPanel

-- Hides shop weapons the player doesn't own and packs the rest left. Returns how many show.
local function showOwned(buttons: Row, order: { string }): number
	local shown = 0
	for _, id in order do
		local b = buttons[id]
		local isShop = Config.Weapons[id] ~= nil
			and table.find(Config.Loadout.Primary, id) == nil
			and id ~= Config.Loadout.Melee
		b.Visible = not isShop or Profile.owns(player, id)
		if b.Visible then
			b.Position = UDim2.fromOffset(120 + shown * 160, 2)
			shown += 1
		end
	end
	return shown
end
local primaryOrder = options("Primary", Config.Loadout.Primary)
local meleeOrder = options("Melee", { Config.Loadout.Melee })

local function highlight(buttons: Row, picked: string?)
	for value, b in buttons do
		b.BackgroundColor3 = if value == picked then PICKED else IDLE
		b.TextColor3 = if value == picked then Color3.fromRGB(20, 20, 20) else Color3.new(1, 1, 1)
	end
end

RunService.RenderStepped:Connect(function()
	local phase = state:GetAttribute("Phase")
	local now = workspace:GetServerTimeNow()
	local sudden = state:GetAttribute("SuddenDeath") == true
	local picking = phase == "Freeze" and Weapon.inCombat()
	loadoutPanel.Visible = picking
	if picking then
		local left = math.max(0, math.ceil((state:GetAttribute("FreezeEndsAt") or now) - now))
		loadoutTitle.Text = if sudden then `SUDDEN DEATH: SNIPER OR KNIFE?  {left}` else `CHOOSE YOUR LOADOUT  {left}`
		(primaryRow.AR.Parent :: Frame).Visible = not sudden
		showOwned(primaryRow, primaryOrder)
		local meleeChoices = showOwned(meleeRow, meleeOrder);
		(meleeRow[Config.Loadout.Melee].Parent :: Frame).Visible = not sudden and meleeChoices > 1
		(gadgetRow.Frag.Parent :: Frame).Visible = not sudden;
		(roleRow.Sniper.Parent :: Frame).Visible = sudden
		highlight(primaryRow, (player:GetAttribute("PickPrimary") or "AR") :: string)
		highlight(meleeRow, (player:GetAttribute("PickMelee") or Config.Loadout.Melee) :: string)
		highlight(gadgetRow, (player:GetAttribute("PickGadget") or "Frag") :: string)
		local held = player:GetAttribute("Weapon") :: string?
		local heldWeapon = if held then Config.Weapons[held] else nil
		local role = if heldWeapon and heldWeapon.kind == "melee"
			then "Knife"
			elseif heldWeapon and heldWeapon.scoped then "Sniper"
			else held
		highlight(roleRow, role)
		note.Text = if sudden
			then "One sniper and one melee fighter per team. You have: " .. (if heldWeapon
				then heldWeapon.name
				else "...")
			else "You always carry the Pistol (2) and your melee weapon (3).  G throws or uses your gadget."
	end
	Weapon.menuOpen = picking
end)

return {}
