--!strict
-- Camp More Maniar lobby screen: a bottom bar with the map picker, the 1v1/2v2 toggle, PLAY, Shop and
-- Inventory, plus the coin counter and coin toasts. Shown whenever the player isn't in a match.
-- Coins and skins live on the server (Economy); this only shows them and sends requests.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer :: Player
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local arenas = ReplicatedStorage:WaitForChild("Arenas")
local QueueRemote = remotes:WaitForChild("Queue") :: RemoteEvent
local ShopRemote = remotes:WaitForChild("Shop") :: RemoteEvent
local Toast = remotes:WaitForChild("Toast") :: RemoteEvent
local SettingsRemote = remotes:WaitForChild("Settings") :: RemoteEvent
local PracticeRemote = remotes:WaitForChild("Practice") :: RemoteEvent
local EmoteRemote = remotes:WaitForChild("Emote") :: RemoteEvent

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

-- The bar is laid out for 1340 px and the modals for ~560 px of height; smaller windows scale the whole
-- screen down so nothing overlaps or runs off the edge.
local BAR_WIDTH = 1340
local fit = Instance.new("UIScale")
fit.Parent = gui
local viewportConn: RBXScriptConnection?
local function refit()
	local camera = workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		fit.Scale = math.min(1, viewport.X / (BAR_WIDTH + 40), (viewport.Y - 40) / 560)
	end
end
local function watchCamera()
	if viewportConn then
		viewportConn:Disconnect()
	end
	local camera = workspace.CurrentCamera
	viewportConn = camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	refit()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

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
local soloHint = label(gui, UDim2.fromOffset(900, 22), UDim2.new(0.5, -450, 1, -224), 15, BODY)
soloHint.Text = `Solo? Queue 1v1, a bot joins in {Config.QueueSeconds} s.`
soloHint.TextStrokeTransparency = 0.4

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
-- Ranked: unlocked at level 50; queues against ranked players and moves Rank Points.
local rankedButton = button(bar, UDim2.fromOffset(216, 46), UDim2.fromOffset(modeX, 92), "", function()
	if player:GetAttribute("RankedUnlocked") == true then
		SettingsRemote:FireServer("Ranked", not player:GetAttribute("Ranked"))
	end
end)
rankedButton.TextSize = 15

local play = button(bar, UDim2.fromOffset(190, 126), UDim2.new(1, -332, 0, 12), "PLAY", function()
	if typeof(player:GetAttribute("Coins")) ~= "number" then
		return -- profile still loading (the button says so)
	elseif player:GetAttribute("Queued") then
		QueueRemote:FireServer("Leave")
	else
		QueueRemote:FireServer("Join", selectedMap, selectedMode)
	end
end)
play.TextSize, play.TextWrapped = 32, true

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

local levelBox = Instance.new("Frame")
levelBox.Size, levelBox.Position = UDim2.fromOffset(260, 70), UDim2.new(1, -280, 0, 146)
levelBox.BackgroundTransparency = 1
levelBox.Parent = gui
local levelText = label(levelBox, UDim2.new(1, 0, 0, 24), UDim2.new(), 18)
levelText.TextXAlignment = Enum.TextXAlignment.Right
levelText.TextStrokeTransparency = 0.4
local xpBar = frame(levelBox, UDim2.fromOffset(200, 8), UDim2.new(1, 0, 0, 28), Vector2.new(1, 0), IDLE)
local xpFill = frame(xpBar, UDim2.fromScale(0, 1), UDim2.new(), nil, PICKED)
local titleText = label(levelBox, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 40), 18)
titleText.TextXAlignment = Enum.TextXAlignment.Right
titleText.TextColor3 = Color3.fromRGB(255, 200, 60)
titleText.TextStrokeTransparency = 0.4

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
		if Profile.owns(player, id) then
			set[id] = true
		end
	end
	for _, f in Config.Finishers do
		if f.price == 0 or Profile.owns(player, "Finisher_" .. f.id) then
			set["Finisher_" .. f.id] = true
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
local finisherOf: { [string]: string } = {} -- shop card id -> finisher id
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
	label(card, UDim2.new(1, -12, 0, 20), UDim2.fromOffset(6, y), 15, BODY).Text = if item.price > 0
		then `{item.price} coins`
		else "FREE"
	prices[item.id] = item.price
	shopCards[item.id] = button(card, UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, size.Y - 44), "BUY", function()
		local finisher = finisherOf[item.id]
		if finisher and ownedSet()[item.id] then
			ShopRemote:FireServer("EquipFinisher", finisher)
		else
			ShopRemote:FireServer("Buy", item.id)
		end
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
for i, name in { "SKINS", "WEAPONS", "FINISHERS" } :: { string } do
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
for i, f in Config.Finishers do
	local id = "Finisher_" .. f.id
	finisherOf[id] = f.id
	local item = { id = id, name = f.name, price = f.price, color = f.ink }
	shopCard(tabs.FINISHERS, item, Vector2.new(190, 170), Vector2.new(16 + (i - 1) % 4 * 204, (i - 1) // 4 * 182))
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
-- Closing the first-join picker keeps the default theme, so onboarding still moves on to the starter.
local settingsClose = settingsPanel:FindFirstChildOfClass("TextButton") :: TextButton
settingsClose.Activated:Connect(function()
	if player:GetAttribute("ThemePicked") == false then
		SettingsRemote:FireServer("Theme", Theme.current().id)
	end
end)
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
local emotePanel = modal("EMOTES")
emotePanel.Size = UDim2.fromOffset(340, 64 + #Config.Emotes * 52)
local emoteButtons: { [string]: TextButton } = {}
for i, e in Config.Emotes do
	local pos = UDim2.fromOffset(16, 56 + (i - 1) * 52)
	emoteButtons[e.id] = button(emotePanel, UDim2.new(1, -32, 0, 44), pos, e.name, function()
		if e.title == nil or player:GetAttribute("Title") == e.title then
			EmoteRemote:FireServer(e.id)
			emotePanel.Visible = false
		end
	end)
end
local emotesButton = button(gui, UDim2.fromOffset(130, 34), UDim2.new(1, -290, 0, 104), "EMOTES", function()
	emotePanel.Visible = not emotePanel.Visible
	shopPanel.Visible, inventoryPanel.Visible, settingsPanel.Visible = false, false, false
	for _, e in Config.Emotes do
		local locked = e.title ~= nil and player:GetAttribute("Title") ~= e.title
		local b = emoteButtons[e.id]
		b.Text = if locked then `🔒 {e.name} (Eddie's Honor)` else e.name
		b.TextColor3 = if locked then Color3.fromRGB(120, 120, 120) else Color3.new(1, 1, 1)
	end
end)
emotesButton.TextSize = 14
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

-- First join, after the HUD colors: a starter primary and its color. No X: picking is required.
local starterPanel = modal("CHOOSE YOUR STARTER")
starterPanel.Size = UDim2.fromOffset(840, 330)
local starterClose = starterPanel:FindFirstChildOfClass("TextButton") :: TextButton
starterClose:Destroy()
local starterWeapon, starterColor = Config.Starter.Weapons[1], Config.Starter.Colors[1]
local starterSentAt = -math.huge
local starterStrokes: { [string]: UIStroke } = {}
local function starterButton(id: string, text: string, pos: UDim2, size: UDim2, pick: () -> ()): TextButton
	local b = button(starterPanel, size, pos, text, function()
		pick()
		for key, s in starterStrokes do
			s.Enabled = key == starterWeapon or key == starterColor
		end
	end)
	b.TextStrokeTransparency = 0.4
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 4
	stroke.Color = PICKED
	stroke.Enabled = id == starterWeapon or id == starterColor
	stroke.Parent = b
	table.insert(strokes, stroke)
	starterStrokes[id] = stroke
	return b
end
for i, id in Config.Starter.Weapons do
	local name = string.upper(Config.Weapons[id].name)
	starterButton(id, name, UDim2.fromOffset(16 + (i - 1) * 204, 60), UDim2.fromOffset(190, 50), function()
		starterWeapon = id
	end)
end
for i, id in Config.Starter.Colors do
	for _, skin in Config.Skins do
		if skin.id == id then
			local pos, size = UDim2.fromOffset(16 + (i - 1) * 204, 124), UDim2.fromOffset(190, 110)
			starterButton(id, string.upper(skin.name), pos, size, function()
				starterColor = id
			end).BackgroundColor3 = skin.color
				or IDLE
		end
	end
end
local confirm = button(starterPanel, UDim2.fromOffset(220, 50), UDim2.new(0.5, -230, 1, -66), "CONFIRM", function()
	-- The panel hides once the server sets StarterPicked; until then a retry is allowed every 3 s.
	if os.clock() - starterSentAt >= 3 then
		SettingsRemote:FireServer("Starter", starterWeapon, starterColor)
		starterSentAt = os.clock()
	end
end)
confirm.BackgroundColor3 = GO

-- Quick start from either first-join picker: default theme, first starter, then a 1v1 on the first map.
local function quickStart()
	if player:GetAttribute("ThemePicked") == false then
		SettingsRemote:FireServer("Theme", Theme.current().id)
	end
	SettingsRemote:FireServer("Starter", Config.Starter.Weapons[1], Config.Starter.Colors[1])
	starterSentAt = os.clock()
	settingsPanel.Visible = false
	selectedMap, selectedMode = Config.Maps[1].id, "1v1"
	QueueRemote:FireServer("Join", selectedMap, selectedMode)
end
local quickSize, quickText = UDim2.fromOffset(300, 50), "USE DEFAULTS & PLAY"
local themeDefaults = button(settingsPanel, quickSize, UDim2.new(0.5, -150, 1, -62), quickText, quickStart)
local starterDefaults = button(starterPanel, quickSize, UDim2.new(0.5, 10, 1, -66), quickText, quickStart)
themeDefaults.BackgroundColor3, starterDefaults.BackgroundColor3 = GO, GO

-- In a match: concede (a saved loss, server-side) and go back to Camp More Maniar.
local leaveBox = frame(gui, UDim2.fromOffset(260, 96), UDim2.new(1, -280, 0, 148))
leaveBox.Visible = false
label(leaveBox, UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 6), 16).Text = "Leaving counts as a loss."
local leaveMatch = button(gui, UDim2.fromOffset(150, 34), UDim2.new(1, -170, 0, 108), "LEAVE MATCH", function()
	leaveBox.Visible = not leaveBox.Visible
end)
leaveMatch.TextSize, leaveMatch.BackgroundColor3 = 14, STOP
local leaveYes = button(leaveBox, UDim2.fromOffset(114, 40), UDim2.fromOffset(10, 46), "LEAVE", function()
	leaveBox.Visible = false
	QueueRemote:FireServer("Leave")
end)
local leaveNo = button(leaveBox, UDim2.fromOffset(114, 40), UDim2.fromOffset(136, 46), "STAY", function()
	leaveBox.Visible = false
end)
leaveYes.BackgroundColor3 = STOP
leaveYes.Modal, leaveNo.Modal = true, true -- frees the first-person mouse while the confirm is up

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

local function clock(startsAt: any, now: number): string
	if type(startsAt) ~= "number" then
		return "soon"
	end
	return `in {math.max(0, math.ceil(startsAt - now))}`
end

-- Refresh -------------------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local arena = player:GetAttribute("Arena")
	local inLobby = arena == nil
	local practicing = arena == "Practice"
	local firstTheme = player:GetAttribute("ThemePicked") == false
	local inMatch = arena ~= nil and not practicing
	bar.Visible = inLobby
	status.Visible = inLobby or practicing
	soloHint.Visible = inLobby and not player:GetAttribute("Queued")
	settingsButton.Visible, emotesButton.Visible, levelBox.Visible = inLobby, inLobby, inLobby
	settingsPanel.Size = UDim2.fromOffset(840, if firstTheme then 400 else 330)
	themeDefaults.Visible = firstTheme
	starterPanel.Visible = inLobby and player:GetAttribute("StarterPicked") == false and not firstTheme
	leaveMatch.Visible = inMatch
	leaveBox.Visible = leaveBox.Visible and inMatch
	confirm.Text = if os.clock() - starterSentAt < 3 then "SAVING..." else "CONFIRM"
	leaveRange.Visible = practicing
	if practicing then
		status.Text = "PRACTICE RANGE · shoot the targets · walk off the range or press LEAVE RANGE to stop"
	end
	if not inLobby then
		shopPanel.Visible, inventoryPanel.Visible, settingsPanel.Visible = false, false, false
		emotePanel.Visible = false
	end
	toast.Visible = os.clock() < toastUntil
	coins.Text = `{player:GetAttribute("Coins") or 0} COINS`
	if not inLobby then
		return
	end
	local into, need = (player:GetAttribute("XpInto") or 0) :: number, (player:GetAttribute("XpNeed") or 1) :: number
	levelText.Text = `LEVEL {player:GetAttribute("Level") or 1} · {into}/{need} XP`
	xpFill.Size = UDim2.fromScale(math.clamp(into / math.max(need, 1), 0, 1), 1)
	xpFill.BackgroundColor3 = PICKED
	local title = player:GetAttribute("Title") :: string?
	titleText.Text = if title == "EddiesHonor" then "EDDIE'S HONOR" elseif title then string.upper(title) else ""
	local rankedOn = player:GetAttribute("Ranked") == true
	if player:GetAttribute("RankedUnlocked") == true then
		local rp = player:GetAttribute("RP") or Config.RankedStart
		rankedButton.Text = `RANKED: {if rankedOn then "ON" else "OFF"} · {rp} RP`
		rankedButton.BackgroundColor3 = if rankedOn then GO else IDLE
		rankedButton.TextColor3 = Color3.new(1, 1, 1)
	else
		rankedButton.Text, rankedButton.BackgroundColor3 = "RANKED (LV 50)", IDLE
		rankedButton.TextColor3 = Color3.fromRGB(120, 120, 120)
	end
	local now = workspace:GetServerTimeNow()
	local queued = player:GetAttribute("Queued") :: string?
	for _, m in Config.Maps do
		local card = cards[m.id]
		local a = arenas:FindFirstChild(m.id)
		local phase = a and a:GetAttribute("Phase")
		local count = (a and a:GetAttribute("Queued") or 0) :: number
		local ranked = a and count > 0 and a:GetAttribute("Ranked") == true
		local mode = (a and a:GetAttribute("Mode") or "1v1") .. (if ranked then " RANKED" else "")
		card.info.Text = if phase == "Starting"
			then `{count} queued · {mode} starts {clock((a :: Instance):GetAttribute("StartsAt"), now)}`
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
		local mode = player:GetAttribute("QueuedMode") or selectedMode
		-- The match starting there may be the other mode; then this player waits for the next one.
		local phase = if a
				and a:GetAttribute("Mode") ~= mode
				and a:GetAttribute("Phase") == "Starting"
			then "Busy"
			else a and a:GetAttribute("Phase")
		status.Text = if phase == "Starting"
			then `Queued for {mapName} ({mode}) · starting {clock((a :: Instance):GetAttribute("StartsAt"), now)}`
			elseif phase == "Waiting" then `Queued for {mapName} ({mode})`
			else `Queued for {mapName} · the current match there finishes first`
		play.Text, play.BackgroundColor3, play.TextSize = "LEAVE", STOP, 32
	else
		status.Text = "Pick a map and a mode, then press PLAY. Players on the same map play each other."
		local ready = typeof(player:GetAttribute("Coins")) == "number"
		play.Text = if ready then "PLAY" else "LOADING PROFILE..."
		play.BackgroundColor3 = if ready then GO else IDLE
		play.AutoButtonColor, play.TextSize = ready, if ready then 32 else 20
	end
	if shopPanel.Visible or inventoryPanel.Visible then
		local owned = ownedSet()
		local wallet = (player:GetAttribute("Coins") or 0) :: number
		for id, b in shopCards do
			local price = prices[id]
			local finisher = finisherOf[id]
			local equipped = finisher and finisher == (player:GetAttribute("Finisher") or Config.Finishers[1].id)
			b.Text = if owned[id] and finisher
				then (if equipped then "EQUIPPED" else "EQUIP")
				elseif owned[id] then "OWNED"
				elseif wallet < price then "NEED COINS"
				else "BUY"
			b.BackgroundColor3 = if b.Text == "EQUIP" or not (owned[id] or wallet < price) then GO else IDLE
		end
		-- Owned looks only, packed left in catalog order.
		for weapon, row in swatches do
			local equipped = Profile.skin(player, weapon) or "Standard"
			local column = 0
			for _, skin in Config.Skins do
				local b = row[skin.id]
				if b then
					b.Visible = owned[skin.id] == true or Profile.owns(player, weapon .. "_" .. skin.id)
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
