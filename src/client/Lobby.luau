--!strict
-- Camp More Maniar lobby screen: a bottom bar with the map picker, the 1v1/2v2 toggle, PLAY, Shop and
-- Inventory, plus the coin counter and coin toasts. Shown whenever the player isn't in a match.
-- Coins and skins live on the server (Economy); this only shows them and sends requests.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer :: Player
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local arenas = ReplicatedStorage:WaitForChild("Arenas")
local QueueRemote = remotes:WaitForChild("Queue") :: RemoteEvent
local ShopRemote = remotes:WaitForChild("Shop") :: RemoteEvent
local Toast = remotes:WaitForChild("Toast") :: RemoteEvent
local SettingsRemote = remotes:WaitForChild("Settings") :: RemoteEvent
local PracticeRemote = remotes:WaitForChild("Practice") :: RemoteEvent

local FONT, BODY = Enum.Font.GothamBlack, Enum.Font.GothamMedium
-- PANEL and PICKED follow the player's HUD theme (set in Theme.watch at the bottom).
local PANEL = Config.HudThemes[1].primary
local IDLE = Color3.fromRGB(32, 40, 54)
local PICKED = Config.HudThemes[1].accent
local GO = Color3.fromRGB(60, 170, 80)
local STOP = Color3.fromRGB(190, 60, 50)
local WEAPON_ORDER = { "AR", "SMG", "Shotgun", "Pistol", "Sniper", "Knife" }

local gui = Instance.new("ScreenGui")
gui.Name = "CampMoreManiar"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- The bar is laid out for 1340 px; narrower windows scale the whole screen down so nothing overlaps.
local BAR_WIDTH = 1340
local fit = Instance.new("UIScale")
fit.Parent = gui
local function refit()
	fit.Scale = math.min(1, workspace.CurrentCamera.ViewportSize.X / (BAR_WIDTH + 40))
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
refit()

local panels: { Frame } = {} -- frames painted with the theme's panel color
local function frame(parent: Instance, size: UDim2, pos: UDim2, anchor: Vector2?, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Size, f.Position = size, pos
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = color or PANEL
	f.BackgroundTransparency = if color then 0 else 0.15
	f.Parent = parent
	Instance.new("UICorner").Parent = f
	if not color then
		table.insert(panels, f)
	end
	return f
end

local function label(parent: Instance, size: UDim2, pos: UDim2, textSize: number, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size, l.Position = size, pos
	l.BackgroundTransparency = 1
	l.Font = font or FONT
	l.TextSize = textSize
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function button(parent: Instance, size: UDim2, pos: UDim2, text: string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size, b.Position = size, pos
	b.BackgroundColor3 = IDLE
	b.Font = FONT
	b.TextSize = 18
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = parent
	Instance.new("UICorner").Parent = b
	b.Activated:Connect(onClick)
	return b
end

-- Bottom bar ----------------------------------------------------------------------------------------
local bar = frame(gui, UDim2.fromOffset(BAR_WIDTH, 150), UDim2.new(0.5, 0, 1, -16), Vector2.new(0.5, 1))
local status = label(gui, UDim2.fromOffset(900, 30), UDim2.new(0.5, -450, 1, -200), 20)
status.TextStrokeTransparency = 0.4

local selectedMap = Config.Maps[1].id
local selectedMode = "1v1"
local cards: { [string]: { button: TextButton, info: TextLabel } } = {}
for i, m in Config.Maps do
	local card = button(bar, UDim2.fromOffset(240, 126), UDim2.fromOffset(12 + (i - 1) * 252, 12), "", function()
		selectedMap = m.id
	end)
	label(card, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 6), 19).Text = string.upper(m.name)
	label(card, UDim2.new(1, -16, 0, 44), UDim2.fromOffset(8, 36), 13, BODY).Text = m.blurb
	local info = label(card, UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 88), 14, BODY)
	cards[m.id] = { button = card, info = info }
end

local modeX = 12 + #Config.Maps * 252 + 8
label(bar, UDim2.fromOffset(150, 24), UDim2.fromOffset(modeX, 12), 14).Text = "MODE"
local modeButtons: { [string]: TextButton } = {}
for i, mode in { "1v1", "2v2" } do
	modeButtons[mode] = button(
		bar,
		UDim2.fromOffset(72, 44),
		UDim2.fromOffset(modeX + (i - 1) * 78, 40),
		mode,
		function()
			selectedMode = mode
		end
	)
end

local play = button(bar, UDim2.fromOffset(190, 126), UDim2.new(1, -332, 0, 12), "PLAY", function()
	if player:GetAttribute("Queued") then
		QueueRemote:FireServer("Leave")
	else
		QueueRemote:FireServer("Join", selectedMap, selectedMode)
	end
end)
play.TextSize = 32

local shopPanel: Frame, inventoryPanel: Frame
local shopButton = button(bar, UDim2.fromOffset(120, 59), UDim2.new(1, -132, 0, 12), "SHOP", function()
	shopPanel.Visible = not shopPanel.Visible
	inventoryPanel.Visible = false
end)
local inventoryButton = button(bar, UDim2.fromOffset(120, 59), UDim2.new(1, -132, 0, 79), "INVENTORY", function()
	inventoryPanel.Visible = not inventoryPanel.Visible
	shopPanel.Visible = false
end)
inventoryButton.TextSize, shopButton.TextSize = 16, 16

local coins = label(gui, UDim2.fromOffset(260, 40), UDim2.new(1, -280, 0, 60), 26)
coins.TextXAlignment = Enum.TextXAlignment.Right
coins.TextColor3 = PICKED
coins.TextStrokeTransparency = 0.4

-- Shop and inventory ------------------------------------------------------------------------------
local function ownedSet(): { [string]: boolean }
	local set = { Standard = true }
	local ids = {}
	for _, skin in Config.Skins do
		table.insert(ids, skin.id)
	end
	for _, w in Config.ShopWeapons do
		table.insert(ids, w.id)
	end
	for _, id in ids do
		if player:GetAttribute("Owns_" .. id) == true then
			set[id] = true
		end
	end
	return set
end

local function modal(title: string): Frame
	local f = frame(gui, UDim2.fromOffset(840, 480), UDim2.fromScale(0.5, 0.42), Vector2.new(0.5, 0.5))
	f.Visible = false
	label(f, UDim2.new(1, -60, 0, 40), UDim2.fromOffset(16, 8), 24).Text = title
	button(f, UDim2.fromOffset(36, 36), UDim2.new(1, -46, 0, 10), "X", function()
		f.Visible = false
	end)
	return f
end

-- One shop card: swatch, name, optional description, price and a BUY button.
local shopCards: { [string]: TextButton } = {}
local prices: { [string]: number } = {}
local function shopCard(parent: Instance, item: { [string]: any }, size: Vector2, pos: Vector2)
	local card = frame(parent, UDim2.fromOffset(size.X, size.Y), UDim2.fromOffset(pos.X, pos.Y))
	card.BackgroundColor3 = IDLE
	card.BackgroundTransparency = 0
	frame(card, UDim2.new(1, -20, 0, 60), UDim2.fromOffset(10, 10), nil, item.color)
	label(card, UDim2.new(1, -12, 0, 26), UDim2.fromOffset(6, 76), 16).Text = string.upper(item.name)
	local y = 102
	if item.about then
		label(card, UDim2.new(1, -20, 0, 92), UDim2.fromOffset(10, y), 15, BODY).Text = item.about
		y += 100
	end
	label(card, UDim2.new(1, -12, 0, 20), UDim2.fromOffset(6, y), 15, BODY).Text = `{item.price} coins`
	prices[item.id] = item.price
	shopCards[item.id] = button(card, UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, size.Y - 44), "BUY", function()
		ShopRemote:FireServer("Buy", item.id)
	end)
end

shopPanel = modal("SHOP  ·  earned with coins, looks only")
local tabs: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}
local currentTab = "SKINS"
local function showTab(name: string)
	currentTab = name
	for id, f in tabs do
		f.Visible = id == name
		tabButtons[id].BackgroundColor3 = if id == name then PICKED else IDLE
		tabButtons[id].TextColor3 = if id == name then Color3.fromRGB(20, 20, 20) else Color3.new(1, 1, 1)
	end
end
for i, name in { "SKINS", "WEAPONS" } do
	local tab = Instance.new("Frame")
	tab.Size, tab.Position = UDim2.new(1, 0, 1, -100), UDim2.fromOffset(0, 100)
	tab.BackgroundTransparency = 1
	tab.Parent = shopPanel
	tabs[name] = tab
	tabButtons[name] = button(
		shopPanel,
		UDim2.fromOffset(140, 36),
		UDim2.fromOffset(16 + (i - 1) * 150, 54),
		name,
		function()
			showTab(name)
		end
	)
end
showTab("SKINS")
local skinCount = 0
for _, skin in Config.Skins do
	if skin.price > 0 then
		local x, y = skinCount % 4, skinCount // 4
		shopCard(tabs.SKINS, skin, Vector2.new(190, 170), Vector2.new(16 + x * 204, y * 182))
		skinCount += 1
	end
end
for i, w in Config.ShopWeapons do
	local base = Config.Weapons[w.base].name
	local slot = string.lower(w.slot)
	shopCard(tabs.WEAPONS, {
		id = w.id,
		name = Config.Weapons[w.id].name,
		price = w.price,
		color = w.color,
		about = `{w.blurb}\nA {slot} weapon: pick it on the loadout screen. Same stats as the {base}.`,
	}, Vector2.new(394, 320), Vector2.new(16 + (i - 1) * 408, 0))
end

inventoryPanel = modal("INVENTORY  ·  pick a look for each weapon")
local swatches: { [string]: { [string]: TextButton } } = {}
local strokes: { UIStroke } = {} -- equipped-skin outlines, in the theme's accent color
for row, weapon in WEAPON_ORDER do
	local y = 56 + (row - 1) * 60
	local name = label(inventoryPanel, UDim2.fromOffset(150, 50), UDim2.fromOffset(16, y), 16)
	name.Text = string.upper(Config.Weapons[weapon].name)
	name.TextXAlignment = Enum.TextXAlignment.Left
	swatches[weapon] = {}
	for _, skin in Config.Skins do
		local b = button(inventoryPanel, UDim2.fromOffset(62, 46), UDim2.fromOffset(170, y + 2), "", function()
			ShopRemote:FireServer("Equip", weapon, skin.id)
		end)
		b.BackgroundColor3 = skin.color or Color3.fromRGB(70, 72, 70)
		b.TextSize = 11
		b.Text = if skin.id == "Standard" then "STD" else ""
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = PICKED
		stroke.Parent = b
		table.insert(strokes, stroke)
		swatches[weapon][skin.id] = b
	end
end

-- Settings: the HUD color theme (also opens by itself on a player's first join).
local settingsPanel = modal("SETTINGS  ·  HUD colors")
settingsPanel.Size = UDim2.fromOffset(840, 330)
for i, t in Config.HudThemes do
	local x, y = (i - 1) % 3, (i - 1) // 3
	local card = button(
		settingsPanel,
		UDim2.fromOffset(260, 110),
		UDim2.fromOffset(16 + x * 272, 60 + y * 124),
		"",
		function()
			SettingsRemote:FireServer("Theme", t.id)
			settingsPanel.Visible = false
		end
	)
	card.BackgroundColor3 = t.primary
	frame(card, UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 12), nil, t.accent)
	label(card, UDim2.new(1, -20, 0, 40), UDim2.fromOffset(10, 44), 20).Text = string.upper(t.name)
end
local settingsButton = button(gui, UDim2.fromOffset(130, 34), UDim2.new(1, -150, 0, 104), "SETTINGS", function()
	settingsPanel.Visible = not settingsPanel.Visible
	shopPanel.Visible, inventoryPanel.Visible = false, false
end)
settingsButton.TextSize = 14
-- On the practice range: a way back to the lobby (walking off the range also works).
local leaveRange = button(gui, UDim2.fromOffset(220, 48), UDim2.new(0.5, -110, 1, -80), "LEAVE RANGE", function()
	PracticeRemote:FireServer("Leave")
end)
leaveRange.BackgroundColor3 = STOP
leaveRange.Visible = false
local function firstJoin()
	if player:GetAttribute("ThemePicked") == false then
		settingsPanel.Visible = true -- first join: pick your HUD colors (Navy & Gold until you do)
	end
end
player:GetAttributeChangedSignal("ThemePicked"):Connect(firstJoin)
firstJoin()

-- Toasts --------------------------------------------------------------------------------------------
local toast = frame(gui, UDim2.fromOffset(520, 70), UDim2.new(0.5, 0, 0, 70), Vector2.new(0.5, 0))
toast.Visible = false
local toastTitle = label(toast, UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 4), 26)
toastTitle.TextColor3 = PICKED
local toastSub = label(toast, UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 40), 16, BODY)
local toastUntil = 0
Toast.OnClientEvent:Connect(function(title: string, sub: string)
	toastTitle.Text = if title == "beginnersluck" then "BEGINNER'S LUCK!" else title
	toastSub.Text = sub
	toastUntil = os.clock() + 4
end)

Theme.watch(function(t)
	PANEL, PICKED = t.primary, t.accent
	for _, f in panels do
		f.BackgroundColor3 = PANEL
	end
	for _, s in strokes do
		s.Color = PICKED
	end
	coins.TextColor3, toastTitle.TextColor3 = PICKED, PICKED
	showTab(currentTab)
end)

local function clock(seconds: number): string
	return tostring(math.max(0, math.ceil(seconds)))
end

-- Refresh -------------------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local arena = player:GetAttribute("Arena")
	local inLobby = arena == nil
	local practicing = arena == "Practice"
	bar.Visible = inLobby
	status.Visible = inLobby or practicing
	settingsButton.Visible = inLobby
	leaveRange.Visible = practicing
	if practicing then
		status.Text = "PRACTICE RANGE · shoot the targets · walk off the range or press LEAVE RANGE to stop"
	end
	if not inLobby then
		shopPanel.Visible, inventoryPanel.Visible, settingsPanel.Visible = false, false, false
	end
	toast.Visible = os.clock() < toastUntil
	coins.Text = `{player:GetAttribute("Coins") or 0} COINS`
	if not inLobby then
		return
	end
	local now = workspace:GetServerTimeNow()
	local queued = player:GetAttribute("Queued") :: string?
	for _, m in Config.Maps do
		local card = cards[m.id]
		local a = arenas:FindFirstChild(m.id)
		local phase = a and a:GetAttribute("Phase")
		local count = (a and a:GetAttribute("Queued") or 0) :: number
		local mode = a and a:GetAttribute("Mode") or "1v1"
		card.info.Text = if phase == "Starting"
			then `{count} queued · {mode} starts in {clock((a :: Instance):GetAttribute("StartsAt") - now)}`
			elseif phase and phase ~= "Waiting" then `Match in progress · {count} waiting`
			else (if count > 0 then `{count} queued · {mode}` else "Nobody queued yet")
		local picked = m.id == (queued or selectedMap)
		card.button.BackgroundColor3 = if picked then Color3.fromRGB(70, 60, 24) else IDLE
	end
	for mode, b in modeButtons do
		b.BackgroundColor3 = if mode == selectedMode then PICKED else IDLE
		b.TextColor3 = if mode == selectedMode then Color3.fromRGB(20, 20, 20) else Color3.new(1, 1, 1)
	end
	if queued then
		local a = arenas:FindFirstChild(queued)
		local mapName = a and a:GetAttribute("Name") or queued
		local mode = a and a:GetAttribute("Mode") or selectedMode
		local phase = a and a:GetAttribute("Phase")
		status.Text = if phase == "Starting"
			then `Queued for {mapName} ({mode}) · starting in {clock((a :: Instance):GetAttribute("StartsAt") - now)}`
			elseif phase == "Waiting" then `Queued for {mapName} ({mode})`
			else `Queued for {mapName} · the current match there finishes first`
		play.Text, play.BackgroundColor3 = "LEAVE", STOP
	else
		status.Text = "Pick a map and a mode, then press PLAY. Players on the same map play each other."
		play.Text, play.BackgroundColor3 = "PLAY", GO
	end
	if shopPanel.Visible or inventoryPanel.Visible then
		local owned = ownedSet()
		local wallet = (player:GetAttribute("Coins") or 0) :: number
		for id, b in shopCards do
			local price = prices[id]
			b.Text = if owned[id] then "OWNED" elseif wallet < price then "NEED COINS" else "BUY"
			b.BackgroundColor3 = if owned[id] or wallet < price then IDLE else GO
		end
		-- Owned looks only, packed left in catalog order.
		for weapon, row in swatches do
			local equipped = player:GetAttribute("Skin_" .. weapon) or "Standard"
			local column = 0
			for _, skin in Config.Skins do
				local b = row[skin.id]
				if b then
					b.Visible = owned[skin.id] == true
					if b.Visible then
						b.Position = UDim2.fromOffset(170 + column * 70, b.Position.Y.Offset)
						column += 1
					end
					(b:FindFirstChildOfClass("UIStroke") :: UIStroke).Enabled = skin.id == equipped
				end
			end
		end
	end
end)

return {}
