--!strict
-- Scoreboard, round timer, health, ammo, crosshair, hit markers, the HEADSHOT flash, damage
-- vignette and the big round/match banners. Everything here is read from server state.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local Weapon = require(script.Parent.Weapon)

local player = Players.LocalPlayer :: Player
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local state = require(script.Parent.ArenaState)
local HitConfirm = remotes:WaitForChild("HitConfirm") :: RemoteEvent
local Damaged = remotes:WaitForChild("Damaged") :: RemoteEvent
local Banner = remotes:WaitForChild("Banner") :: RemoteEvent
local ReportRemote = remotes:WaitForChild("Report") :: RemoteEvent

local FONT = Enum.Font.GothamBlack
local NAVY = Config.Teams.Navy
local GREY = Config.Teams.Grey

game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
local gui = Instance.new("ScreenGui")
gui.Name = "DuelHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function frame(
	size: UDim2,
	position: UDim2,
	anchor: Vector2,
	color: Color3,
	transparency: number,
	parent: Instance?
): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Parent = parent or gui
	return f
end

local function text(
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchor: Vector2,
	textSize: number,
	color: Color3?
): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.AnchorPoint = anchor
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = textSize
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.6
	l.Text = ""
	l.Parent = parent
	return l
end

local function round(f: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = f
end

-- Scoreboard: NAVY name + score | timer | score + name GREY
local board =
	frame(UDim2.fromOffset(560, 64), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0), Color3.fromRGB(12, 16, 24), 0.25)
round(board, 10)
local navyBox = frame(UDim2.fromScale(0.38, 1), UDim2.fromScale(0, 0), Vector2.zero, NAVY.hud, 0.15, board)
round(navyBox, 10)
local greyBox = frame(UDim2.fromScale(0.38, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), GREY.hud, 0.15, board)
round(greyBox, 10)
local navyName = text(navyBox, UDim2.new(1, -74, 1, -8), UDim2.fromOffset(12, 4), Vector2.zero, 16)
navyName.TextXAlignment = Enum.TextXAlignment.Left
local navyScore = text(navyBox, UDim2.new(0, 50, 1, 0), UDim2.new(1, -8, 0, 0), Vector2.new(1, 0), 34)
local greyName =
	text(greyBox, UDim2.new(1, -74, 1, -8), UDim2.new(1, -12, 0, 4), Vector2.new(1, 0), 16, Color3.fromRGB(20, 26, 36))
greyName.TextXAlignment = Enum.TextXAlignment.Right
greyName.TextStrokeTransparency = 1
-- 2v2 names ("A & B") wrap onto two lines and shrink to fit instead of running into the score.
for _, label in { navyName, greyName } do
	label.TextScaled, label.TextWrapped = true, true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 16
	limit.Parent = label
end
local greyScore =
	text(greyBox, UDim2.new(0, 50, 1, 0), UDim2.fromOffset(8, 0), Vector2.zero, 34, Color3.fromRGB(20, 26, 36))
greyScore.TextStrokeTransparency = 1
local timer = text(board, UDim2.fromScale(0.24, 0.62), UDim2.fromScale(0.5, 0.04), Vector2.new(0.5, 0), 28)
local roundLabel = text(
	board,
	UDim2.fromScale(0.24, 0.34),
	UDim2.fromScale(0.5, 0.62),
	Vector2.new(0.5, 0),
	12,
	Color3.fromRGB(235, 190, 60)
)

-- Health (bottom left) and ammo (bottom right)
local healthBack =
	frame(UDim2.fromOffset(300, 30), UDim2.new(0, 24, 1, -24), Vector2.new(0, 1), Color3.fromRGB(12, 16, 24), 0.3)
round(healthBack, 6)
local healthFill =
	frame(UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero, Color3.fromRGB(90, 200, 110), 0, healthBack)
round(healthFill, 6)
local healthText = text(healthBack, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero, 18)
local teamLabel = text(gui, UDim2.fromOffset(300, 22), UDim2.new(0, 24, 1, -58), Vector2.new(0, 1), 16)
teamLabel.TextXAlignment = Enum.TextXAlignment.Left
-- REPORT (above the team label): in a match and for a minute after it, hidden for a minute once sent.
local function button(parent: Instance, position: UDim2, label: string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size, b.Position, b.AnchorPoint = UDim2.fromOffset(80, 24), position, Vector2.new(0, 1)
	b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = Color3.fromRGB(12, 16, 24), 0.25, 0
	b.Font, b.TextSize, b.TextColor3, b.Text = FONT, 13, Color3.new(1, 1, 1), label
	b.Modal = parent ~= gui -- the confirm frees the first-person mouse while it is up
	b.Parent = parent
	round(b, 6)
	b.Activated:Connect(onClick)
	return b
end
local confirmBox =
	frame(UDim2.fromOffset(184, 72), UDim2.new(0, 24, 1, -112), Vector2.new(0, 1), Color3.fromRGB(12, 16, 24), 0.25)
round(confirmBox, 8)
confirmBox.Visible = false
local question = text(confirmBox, UDim2.new(1, -16, 0, 32), UDim2.fromOffset(8, 4), Vector2.zero, 13)
question.Text, question.TextWrapped = "Report the last round for review?", true
local reportUntil, sentUntil, wasInMatch = 0, 0, false
local foes: { [number]: boolean } = {} -- human opponents in the current or last match
local reportButton = button(gui, UDim2.new(0, 24, 1, -84), "REPORT", function()
	confirmBox.Visible = true
end)
button(confirmBox, UDim2.new(0, 8, 1, -8), "REPORT", function()
	local first = next(foes)
	ReportRemote:FireServer(if first and next(foes, first) == nil then first else nil)
	-- Hidden while the server answers; a dropped (rate-limited) request shows the button again soon.
	confirmBox.Visible, sentUntil = false, os.clock() + 10
end)
ReportRemote.OnClientEvent:Connect(function(ok: boolean)
	sentUntil = if ok then os.clock() + 60 else 0
end)
button(confirmBox, UDim2.new(0, 96, 1, -8), "CANCEL", function()
	confirmBox.Visible = false
end)
local ammoText = text(gui, UDim2.fromOffset(240, 50), UDim2.new(1, -24, 1, -40), Vector2.new(1, 1), 40)
ammoText.TextXAlignment = Enum.TextXAlignment.Right
local hint = text(
	gui,
	UDim2.fromOffset(360, 20),
	UDim2.new(1, -24, 1, -16),
	Vector2.new(1, 1),
	13,
	Color3.fromRGB(210, 210, 210)
)
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.Text = "CLICK fire  RCLICK aim  R reload  1-3 switch  G gadget  SHIFT sprint  C crouch/slide  SPACE x2 jump"
local slotsLabel = text(gui, UDim2.fromOffset(460, 20), UDim2.new(1, -24, 1, -92), Vector2.new(1, 1), 15)
slotsLabel.TextXAlignment = Enum.TextXAlignment.Right

-- Crosshair, hit marker and headshot flash
local cross = frame(UDim2.fromOffset(1, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.new(), 1)
local crossBars: { Frame } = {}
for i = 1, 4 do
	local bar = frame(
		UDim2.fromOffset(if i <= 2 then 10 else 2, if i <= 2 then 2 else 10),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5),
		Color3.new(1, 1, 1),
		0.1,
		cross
	)
	crossBars[i] = bar
end
local marker = frame(UDim2.fromOffset(28, 28), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.new(), 1)
local markerBars: { Frame } = {}
for i, angle in { 45, -45, 135, -135 } do
	local rad = math.rad(angle)
	local bar = frame(
		UDim2.fromOffset(9, 2),
		UDim2.new(0.5, math.cos(rad) * 9, 0.5, math.sin(rad) * 9),
		Vector2.new(0.5, 0.5),
		Color3.new(1, 1, 1),
		0,
		marker
	)
	bar.Rotation = angle
	markerBars[i] = bar
end
marker.Visible = false
local headshot = text(
	gui,
	UDim2.fromOffset(500, 60),
	UDim2.fromScale(0.5, 0.36),
	Vector2.new(0.5, 0.5),
	48,
	Color3.fromRGB(235, 40, 40)
)
headshot.Text = "HEADSHOT"
headshot.Visible = false
local vignette = frame(UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero, Color3.fromRGB(200, 0, 0), 1)
local gradient = Instance.new("UIGradient")
gradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.25, 1),
	NumberSequenceKeypoint.new(0.75, 1),
	NumberSequenceKeypoint.new(1, 0),
})
gradient.Parent = vignette
local shield = text(
	gui,
	UDim2.fromOffset(300, 24),
	UDim2.new(0.5, 0, 1, -80),
	Vector2.new(0.5, 1),
	18,
	Color3.fromRGB(120, 200, 255)
)
shield.Text = "SPAWN SHIELD (firing drops it)"

-- Sniper scope: black mask around a round clear view, thin crosshairs and a red dot.
local BLACK, RED = Color3.new(), Color3.fromRGB(235, 40, 40)
local scope = frame(UDim2.fromScale(0.9, 0.9), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), BLACK, 1)
scope.SizeConstraint = Enum.SizeConstraint.RelativeYY
scope.ZIndex = 0 -- under the health, ammo and banners
local scopeCorner = Instance.new("UICorner")
scopeCorner.CornerRadius = UDim.new(0.5, 0)
scopeCorner.Parent = scope
-- The ring's stroke fills the square's corners outside the circle; its width follows the screen size.
local ring = Instance.new("UIStroke")
ring.Color = BLACK
ring.Parent = scope
frame(UDim2.fromScale(5, 5), UDim2.fromScale(0, 0.5), Vector2.new(1, 0.5), BLACK, 0, scope)
frame(UDim2.fromScale(5, 5), UDim2.fromScale(1, 0.5), Vector2.new(0, 0.5), BLACK, 0, scope)
frame(UDim2.fromScale(1, 5), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 1), BLACK, 0, scope)
frame(UDim2.fromScale(1, 5), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 0), BLACK, 0, scope)
frame(UDim2.new(1, 0, 0, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), BLACK, 0, scope)
frame(UDim2.new(0, 1, 1, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), BLACK, 0, scope)
local dot = frame(UDim2.fromOffset(6, 6), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), RED, 0, scope)
round(dot, 3)

-- Big center banner
local bannerTitle = text(gui, UDim2.fromOffset(800, 90), UDim2.fromScale(0.5, 0.28), Vector2.new(0.5, 0.5), 72)
local bannerSub = text(gui, UDim2.fromOffset(800, 40), UDim2.fromScale(0.5, 0.36), Vector2.new(0.5, 0.5), 24)
local bannerUntil = 0

local function showBanner(title: string, sub: string, color: Color3, seconds: number)
	bannerTitle.Text, bannerSub.Text = title, sub
	bannerTitle.TextColor3 = color
	bannerUntil = os.clock() + seconds
end

local function myTeam(): Config.TeamId?
	return player:GetAttribute("Team") :: Config.TeamId?
end

local WIN = Color3.fromRGB(110, 220, 120)
local LOSE = Color3.fromRGB(235, 70, 60)
local GOLD = Config.HudThemes[1].accent
local DROP_NAMES: { [string]: string } = {
	Helicopter = "helicopter fast-rope",
	Truck = "army truck",
	Parachute = "parachute jump",
	ArmoredCar = "armored car",
}

-- The player's HUD theme: panel backgrounds take its primary color, gold text its accent.
Theme.watch(function(t)
	GOLD = t.accent
	board.BackgroundColor3, healthBack.BackgroundColor3 = t.primary, t.primary
	roundLabel.TextColor3 = t.accent
end)

Banner.OnClientEvent:Connect(function(kind: string, data: { [string]: any })
	local team = myTeam()
	if kind == "RoundStart" then
		local mySide = if team == "Navy" then data.navySide elseif data.navySide == "A" then "B" else "A"
		local ride = DROP_NAMES[data.drop] or "drop-in"
		local sub = if team then `Arriving by {ride} · you start on SIDE {mySide}` else ""
		if data.sudden then
			showBanner("SUDDEN DEATH", "4 - 4. Win this round to take the match.", LOSE, Config.FreezeSeconds)
		else
			showBanner(`ROUND {data.round}`, sub, Color3.new(1, 1, 1), Config.FreezeSeconds)
		end
	elseif kind == "RoundEnd" then
		-- With a cutscene coming, the result only flashes; the cutscene shows the rest.
		local seconds = if data.cutscene then 1.2 else Config.RoundEndSeconds
		if data.winner == "Draw" then
			showBanner("DRAW", `{data.detail}. No point.`, GOLD, seconds)
		elseif team then
			local won = data.winner == team
			showBanner(if won then "ROUND WON" else "ROUND LOST", data.detail, if won then WIN else LOSE, seconds)
			Weapon.sound(if won then Config.Sounds.Victory else Config.Sounds.Whoosh, gui, 0.6)
		else
			showBanner(`{Config.Teams[data.winner :: Config.TeamId].name} WINS THE ROUND`, data.detail, GOLD, seconds)
		end
	elseif kind == "MatchEnd" then
		local score = `{data.navy} - {data.grey}`
		local how = if data.forfeit then "Opponent left the match" else score
		if team then
			local won = data.winner == team
			showBanner(if won then "VICTORY" else "DEFEAT", how, if won then GOLD else LOSE, Config.MatchEndSeconds)
		else
			showBanner(`{Config.Teams[data.winner :: Config.TeamId].name} WINS`, how, GOLD, Config.MatchEndSeconds)
		end
	elseif kind == "Celebrate" then
		-- Sweep across the celebration stage, closing in, then hand the camera back.
		local camera = workspace.CurrentCamera
		local focus: Vector3 = data.focus
		local seconds: number = data.seconds
		local started = os.clock()
		camera.CameraType = Enum.CameraType.Scriptable
		local sweep: RBXScriptConnection
		sweep = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - started) / seconds
			if t >= 1 then
				sweep:Disconnect()
				camera.CameraType = Enum.CameraType.Custom
				return
			end
			-- Reasserted every frame: the stage respawn can hand the camera back to the default scripts.
			camera.CameraType = Enum.CameraType.Scriptable
			local angle = math.rad(-40 + 80 * t)
			local radius = 34 - 12 * t
			local eye = focus + Vector3.new(math.sin(angle) * radius, 7 - 3 * t, math.cos(angle) * radius)
			camera.CFrame = CFrame.lookAt(eye, focus)
		end)
	end
end)

local hitSerial, headshotSerial = 0, 0
HitConfirm.OnClientEvent:Connect(function(zone: Config.Zone, killed: boolean)
	hitSerial += 1
	local serial = hitSerial
	local color = if zone == "Head" or killed then Color3.fromRGB(240, 50, 50) else Color3.new(1, 1, 1)
	for _, bar in markerBars do
		bar.BackgroundColor3 = color
	end
	marker.Visible = true
	marker.Size = UDim2.fromOffset(36, 36)
	TweenService:Create(marker, TweenInfo.new(0.15), { Size = UDim2.fromOffset(28, 28) }):Play()
	-- Only the newest hit may hide the marker or flash, so rapid hits don't cut each other short.
	task.delay(0.18, function()
		marker.Visible = marker.Visible and serial ~= hitSerial
	end)
	if zone == "Head" then
		Weapon.sound(Config.Sounds.Headshot, gui, 0.7)
		headshotSerial += 1
		local flash = headshotSerial
		headshot.Visible = true
		headshot.TextTransparency = 0
		headshot.TextSize = 60
		TweenService:Create(headshot, TweenInfo.new(0.6), { TextTransparency = 1, TextSize = 46 }):Play()
		task.delay(0.6, function()
			headshot.Visible = headshot.Visible and flash ~= headshotSerial
		end)
	else
		Weapon.sound(Config.Sounds.Hit, gui, 0.4)
	end
end)

Damaged.OnClientEvent:Connect(function()
	vignette.BackgroundTransparency = 0.55
	TweenService:Create(vignette, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
end)

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

RunService.RenderStepped:Connect(function()
	local phase = state:GetAttribute("Phase")
	-- Only while in a match; the lobby bar replaces it at Camp More Maniar, and the range has no score.
	board.Visible = phase ~= nil and player:GetAttribute("Arena") ~= "Practice"
	local now = workspace:GetServerTimeNow()
	navyName.Text = state:GetAttribute("NavyName") or "NAVY"
	greyName.Text = state:GetAttribute("GreyName") or "GREY"
	navyScore.Text = tostring(state:GetAttribute("NavyScore") or 0)
	greyScore.Text = tostring(state:GetAttribute("GreyScore") or 0)
	if phase == "Live" then
		timer.Text = clock((state:GetAttribute("RoundEndsAt") or now) - now)
	elseif phase == "Freeze" then
		timer.Text = clock((state:GetAttribute("FreezeEndsAt") or now) - now)
	else
		timer.Text = "--:--"
	end
	roundLabel.Text = if state:GetAttribute("SuddenDeath")
		then "SUDDEN DEATH"
		else `ROUND {state:GetAttribute("Round") or 0}  ·  FIRST TO {Config.RoundsToWin}`

	local team = myTeam()
	local combat = Weapon.inCombat()
	healthBack.Visible, ammoText.Visible, hint.Visible, slotsLabel.Visible = combat, combat, combat, combat
	cross.Visible, scope.Visible = combat and not Weapon.scoped, combat and Weapon.scoped
	ring.Thickness = scope.AbsoluteSize.X * 0.25
	if team then
		teamLabel.Text = `YOU: {Config.Teams[team].name}`
		teamLabel.TextColor3 = Config.Teams[team].hud
	else
		teamLabel.Text = ""
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if combat and humanoid then
		local h = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(h, 1)
		healthFill.BackgroundColor3 = Color3.fromRGB(235, 70, 60):Lerp(Color3.fromRGB(90, 200, 110), h)
		healthText.Text = tostring(math.ceil(humanoid.Health))
		local id, w = Weapon.current()
		local parts = {}
		for i, slot in string.split((player:GetAttribute("Slots") or "") :: string, ",") do
			local entry = Config.Weapons[slot :: Config.WeaponId]
			if entry then
				local label = `{i} {string.upper(entry.name)}`
				table.insert(parts, if slot == id then `[{label}]` else label)
			end
		end
		local gadget = player:GetAttribute("Gadget") :: Config.GadgetId?
		if gadget then
			table.insert(
				parts,
				`G {string.upper(Config.Gadgets[gadget].name)} x{player:GetAttribute("GadgetLeft") or 0}`
			)
		end
		slotsLabel.Text = table.concat(parts, "   ")
		ammoText.Text = if not w
			then ""
			elseif w.kind == "melee" then string.upper(w.name)
			elseif player:GetAttribute("Reloading") then "RELOADING"
			else `{player:GetAttribute("Ammo") or 0} / {w.magazine}`
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local moving = root ~= nil
			and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 3
		local spread = if w
			then (if Weapon.aiming then w.spreadAim else w.spreadHip) + (if moving then w.spreadMoving else 0)
			else 0
		local gap = 6 + 4 * spread
		crossBars[1].Position = UDim2.new(0.5, -gap - 5, 0.5, 0)
		crossBars[2].Position = UDim2.new(0.5, gap + 5, 0.5, 0)
		crossBars[3].Position = UDim2.new(0.5, 0, 0.5, -gap - 5)
		crossBars[4].Position = UDim2.new(0.5, 0, 0.5, gap + 5)
	end
	local healing = player:GetAttribute("Healing") == true
	shield.Text = if healing then "USING MED KIT (you can't shoot)" else "SPAWN SHIELD (firing drops it)"
	shield.Visible = combat and (healing or player:GetAttribute("Shielded") == true)
	local showing = os.clock() < bannerUntil
	bannerTitle.Visible, bannerSub.Visible = showing, showing
	local arena = player:GetAttribute("Arena")
	local inMatch = arena ~= nil and arena ~= "Practice"
	if inMatch then
		reportUntil = os.clock() + 60
		if not wasInMatch then
			table.clear(foes)
		end
		for _, other in Players:GetPlayers() do
			local theirs = other:GetAttribute("Team")
			if team and theirs and theirs ~= team and other:GetAttribute("Arena") == arena then
				foes[other.UserId] = true
			end
		end
	end
	wasInMatch = inMatch
	reportButton.Visible = os.clock() < reportUntil and os.clock() > sentUntil
	confirmBox.Visible = confirmBox.Visible and reportButton.Visible
end)

return {}
