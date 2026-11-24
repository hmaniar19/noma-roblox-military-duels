--!strict
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Weapon: any = require(script.Parent.Weapon)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CutsceneEvent = Remotes:WaitForChild("Cutscene") :: RemoteEvent
local CutsceneDone = Remotes:WaitForChild("CutsceneDone") :: RemoteEvent

local player = Players.LocalPlayer

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local INK_RED = Color3.fromRGB(205, 18, 32)
local BRASS = Color3.fromRGB(214, 170, 72)
local CENTER = Vector2.new(0.5, 0.5)
local HEAVY = Enum.Font.GothamBlack
local HIT_TEXT = "HEADSHOT — CRITICAL HIT"
local FREEZE = 0.35 -- the finisher's opening freeze frame, in seconds
local MAX_SHIFT = 4 -- the finisher camera never strays further than this from the server's cleared spot

-- Each finisher (Config.Finishers id) gets its own camera move on top of its ink.
local FINISHER_STYLES: { [string]: string } = {
	Crimson = "default",
	Midnight = "low",
	Gold = "split",
	Sakura = "orbit",
	Thunder = "slam",
}

type Session = {
	token: any,
	done: boolean,
	instances: { Instance },
	tweens: { Tween },
	bind: string,
}
type CameraFn = (t: number) -> (CFrame, number)
type Builder = (s: Session, data: { [string]: any }, length: number) -> CameraFn

local gui = Instance.new("ScreenGui")
gui.Name = "Cutscene"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

local rng = Random.new()
local active: Session? = nil
local playCount = 0

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst: any = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

type Props = { [string]: any }
local function tween(s: Session, inst: Instance, props: Props, time: number, d: number?, style: any, rep: number?)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out, rep or 0, false, d or 0)
	local t = TweenService:Create(inst, info, props)
	table.insert(s.tweens, t)
	t:Play()
end

local function inkFrame(position: UDim2, rotation: number, color: Color3): Frame
	local frame = make("Frame", {
		AnchorPoint = CENTER,
		Position = position,
		Size = UDim2.fromOffset(0, 0),
		Rotation = rotation,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
	return frame
end

local function label(parent: Instance, text: string, font: Enum.Font, position: UDim2, size: UDim2): TextLabel
	return make("TextLabel", {
		AnchorPoint = CENTER,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Font = font,
		TextScaled = true,
		Text = text,
		TextColor3 = WHITE,
		TextStrokeColor3 = BLACK,
		TextStrokeTransparency = 0.3,
		ZIndex = 5,
	}, parent)
end

local function flatSide(axis: Vector3): Vector3
	local flat = Vector3.new(axis.X, 0, axis.Z)
	if flat.Magnitude < 0.1 then
		return Vector3.xAxis
	end
	return flat.Unit:Cross(Vector3.yAxis).Unit
end

-- The server sends the finisher's ink, which maps back to its id; the winner's attribute covers a missing ink.
local function finisherStyle(data: { [string]: any }): string
	local id: any = data.finisher
	if typeof(id) ~= "string" then
		for _, f in Config.Finishers do
			if f.ink == data.ink then
				id = f.id
			end
		end
	end
	if typeof(id) ~= "string" then
		for _, other in Players:GetPlayers() do
			if other.DisplayName == data.winnerName then
				id = other:GetAttribute("Finisher")
			end
		end
	end
	return if typeof(id) == "string" then FINISHER_STYLES[id] or "default" else "default"
end

local builders: { [string]: Builder } = {}

builders.BulletCam = function(s, data)
	local from: Vector3 = data.from
	local to: Vector3 = data.to
	local travel = 2.0
	local offset = to - from
	local dir = if offset.Magnitude > 0.01 then offset.Unit else Vector3.zAxis
	local side = dir:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
	local up = side:Cross(dir).Unit

	local bullet = make("Part", {
		Size = Vector3.new(0.14, 0.14, 0.45),
		Material = Enum.Material.Neon,
		Color = BRASS,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		CFrame = CFrame.lookAt(from, from + dir),
	}, workspace.CurrentCamera)
	table.insert(s.instances, bullet)
	make("Trail", {
		Attachment0 = make("Attachment", { Position = Vector3.new(0.05, 0, 0) }, bullet),
		Attachment1 = make("Attachment", { Position = Vector3.new(-0.05, 0, 0) }, bullet),
		Lifetime = 0.5,
		Color = ColorSequence.new(BRASS),
		Transparency = NumberSequence.new(0.6, 1),
		LightEmission = 1,
		FaceCamera = true,
	}, bullet)

	local names = string.upper(`{tostring(data.shooterName)}  >>  {tostring(data.victimName)}`)
	local caption = label(gui, names, Enum.Font.GothamBold, UDim2.fromScale(0.5, 0.09), UDim2.fromScale(0.6, 0.05))

	local impacted = false
	return function(t)
		local a = math.clamp(t / travel, 0, 1)
		local pos = from:Lerp(to, a)
		bullet.CFrame = CFrame.lookAt(pos, pos + dir)
		if a >= 1 and not impacted then
			impacted = true
			bullet.Transparency = 1
			caption.Visible = false
			local hit = label(gui, HIT_TEXT, HEAVY, UDim2.fromScale(0.5, 0.45), UDim2.fromScale(1.3, 0.24))
			hit.TextColor3 = INK_RED
			hit.TextStrokeColor3 = WHITE
			hit.TextStrokeTransparency = 0
			tween(s, hit, { Size = UDim2.fromScale(0.8, 0.14) }, 0.22, 0, Enum.EasingStyle.Back)
		end
		local close = a * a
		local camPos = pos - dir * (3.2 - 1.7 * close) + side * (1.2 - 0.5 * close) + up * 0.35
		return CFrame.lookAt(camPos, pos + dir * 8, up), 60
	end
end

-- The server stages the shot clear of cover: `camera` is its start, `focus` the point it frames, and
-- `overhead` marks the fallback that looks straight down on the pair.
builders.Finisher = function(s, data, length)
	local camera: Vector3 = data.camera
	local target: Vector3 = data.focus
	local lost: Vector3, won: Vector3 = data.defeatedPos, data.winnerPos
	local axis = (lost - won) * Vector3.new(1, 0, 1)
	-- Looking straight down, the top of the screen points from the victor toward the defeated player.
	local up = if not data.overhead then Vector3.yAxis elseif axis.Magnitude > 0.1 then axis.Unit else Vector3.zAxis
	local offset = target - camera
	local push = if offset.Magnitude > 1 then offset.Unit * 0.8 else Vector3.zero
	local ink: Color3 = if typeof(data.ink) == "Color3" then data.ink else INK_RED
	local style = finisherStyle(data)
	local dir = if offset.Magnitude > 1 then offset.Unit else Vector3.zAxis
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zero
	local head = won + Vector3.new(0, 1.5, 0)
	-- A 90° arc on a circle this small keeps the orbit inside MAX_SHIFT of the cleared spot.
	local pivot = camera + flat * 2.8

	-- Freeze frame: a white flash over a drained, punchy grade that eases back as the zoom starts.
	local grade = make("ColorCorrectionEffect", { Saturation = -1, Contrast = 0.3 }, Lighting)
	table.insert(s.instances, grade)
	tween(s, grade, { Saturation = 0, Contrast = 0 }, 0.45, FREEZE)
	local flash = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, gui)
	tween(s, flash, { BackgroundTransparency = 1 }, FREEZE)

	for i = 1, 36 do
		local angle = (i / 36) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local cos, sin = math.cos(angle), math.sin(angle)
		local r0 = rng:NextInteger(140, 260)
		local line = make("Frame", {
			AnchorPoint = CENTER,
			Position = UDim2.new(0.5, cos * r0, 0.5, sin * r0),
			Size = UDim2.fromOffset(rng:NextInteger(120, 260), 2),
			Rotation = math.deg(angle),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, gui)
		local goal = { Position = UDim2.new(0.5, cos * (r0 + 750), 0.5, sin * (r0 + 750)), BackgroundTransparency = 1 }
		tween(s, line, goal, 0.45, FREEZE + rng:NextNumber(0, 0.3), Enum.EasingStyle.Quad, -1)
	end

	local slashes: { { number } } = { { 0.36, 0.3, -32, 20 }, { 0.62, 0.42, -22, 14 }, { 0.5, 0.22, 26, 10 } }
	for i, sd in slashes do
		local slash = inkFrame(UDim2.fromScale(sd[1], sd[2]), sd[3], ink)
		slash.Size = UDim2.fromOffset(0, sd[4])
		tween(s, slash, { Size = UDim2.new(1.1, 0, 0, sd[4]) }, 0.14, FREEZE + 0.1 + i * 0.18)
		tween(s, slash, { BackgroundTransparency = 1 }, 0.6, length - 1.1)
	end

	for _ = 1, 8 do
		local size = rng:NextInteger(18, 80)
		local dot = inkFrame(UDim2.fromScale(rng:NextNumber(0.2, 0.8), rng:NextNumber(0.12, 0.55)), 0, ink)
		local delay = FREEZE + 0.3 + rng:NextNumber(0, 0.6)
		tween(s, dot, { Size = UDim2.fromOffset(size, size) }, 0.18, delay, Enum.EasingStyle.Back)
		tween(s, dot, { BackgroundTransparency = 1 }, 0.7, delay + 1.1)
	end

	local team = Config.Teams[data.winnerTeam] or Config.Teams.Navy
	local banner = make("Frame", {
		AnchorPoint = CENTER,
		Position = UDim2.fromScale(-0.7, 0.74),
		Size = UDim2.new(1.3, 0, 0, 150),
		Rotation = -6,
		BackgroundColor3 = team.hud,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, gui)
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, banner)
	local winner = string.upper(tostring(data.winnerName))
	label(banner, winner, Enum.Font.GothamBlack, UDim2.new(0.5, 0, 0, 56), UDim2.new(0.6, 0, 0, 80))
	label(banner, "WINS THE ROUND", Enum.Font.GothamBold, UDim2.new(0.5, 0, 0, 118), UDim2.new(0.6, 0, 0, 40))
	tween(s, banner, { Position = UDim2.fromScale(0.5, 0.74) }, 0.35, FREEZE + 0.25, Enum.EasingStyle.Back)

	return function(t)
		if t < FREEZE then
			return CFrame.lookAt(camera, target, up), 70
		end
		local z = t - FREEZE
		local e = 1 - (1 - math.clamp(z / 0.45, 0, 1)) ^ 3
		local p = math.clamp(z / math.max(length - FREEZE, 0.1), 0, 1)
		local pos, look, frameUp, fov, roll = camera + push * p, target, up, 70 - 32 * e, -10 * e
		if style == "orbit" then
			local turn = CFrame.Angles(0, math.rad(90) * (1 - (1 - p) ^ 2), 0)
			if data.overhead then
				frameUp = turn:VectorToWorldSpace(up)
			else
				pos = pivot + turn:VectorToWorldSpace(camera - pivot)
			end
			look, fov, roll = head, 70 - 25 * e, 0
		elseif style == "slam" then
			local hit = 1 - (1 - math.clamp(z / 0.2, 0, 1)) ^ 4
			local shake = 0.35 * math.max(1 - z / 0.7, 0)
			pos = camera + dir * (MAX_SHIFT * 0.85 * hit) + rng:NextUnitVector() * shake
			fov, roll = 70 - 36 * hit, -6 * hit + rng:NextNumber(-20, 20) * shake
		elseif style == "low" and not data.overhead then
			pos = camera + (flat * 2.5 - Vector3.new(0, 0.8, 0)) * e + push * p
			look, fov, roll = won + Vector3.new(0, 2.6, 0), 70 - 28 * e, 8 * e
		elseif style == "split" then
			if p < 0.45 then
				pos, look, fov, roll = camera + (head - camera).Unit * MAX_SHIFT, head, 32, -6
			else
				fov, roll = 80 - 8 * (p - 0.45) / 0.55, 0
			end
		end
		local shift = pos - camera
		if shift.Magnitude > MAX_SHIFT then
			pos = camera + shift.Unit * MAX_SHIFT
		end
		return CFrame.lookAt(pos, look, frameUp) * CFrame.Angles(0, 0, math.rad(roll)), fov
	end
end

builders.Handshake = function(s, data, length)
	local center: Vector3 = data.center
	local roots: { Vector3 } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - center).Magnitude < 40 then
			table.insert(roots, root.Position)
		end
	end
	local side = if #roots >= 2 then flatSide(roots[1] - roots[2]) else Vector3.xAxis
	local target = center + Vector3.new(0, 2.5, 0)

	local text = label(gui, "DRAW — GOOD GAME", HEAVY, UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.8, 0.14))
	text.TextColor3 = Color3.fromRGB(240, 220, 150)
	text.TextTransparency = 1
	text.TextStrokeTransparency = 1
	tween(s, text, { TextTransparency = 0, TextStrokeTransparency = 0.2 }, 0.6, 1.5)

	return function(t)
		local dist = 14 - 3 * math.clamp(t / length, 0, 1)
		return CFrame.lookAt(center + side * dist + Vector3.new(0, 3, 0), target), 55
	end
end

local function finish(s: Session)
	if s.done then
		return
	end
	s.done = true
	RunService:UnbindFromRenderStep(s.bind)
	for _, t in s.tweens do
		t:Cancel()
	end
	for _, inst in s.instances do
		inst:Destroy()
	end
	gui:ClearAllChildren()
	if active == s then
		active = nil
		Weapon.cutscene = false
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
	end
	CutsceneDone:FireServer(s.token)
end

CutsceneEvent.OnClientEvent:Connect(function(kind: string, data: { [string]: any })
	if typeof(data) ~= "table" then
		return
	end
	if active then
		finish(active)
	end
	playCount += 1
	local s: Session = {
		token = data.token,
		done = false,
		instances = {},
		tweens = {},
		bind = `Cutscene{playCount}`,
	}
	active = s
	Weapon.cutscene = true
	local length = tonumber(data.seconds) or 3

	local ok, err = pcall(function()
		local build = builders[kind]
		assert(build, `unknown cutscene kind {tostring(kind)}`)
		local cameraFn = build(s, data, length)
		local start = os.clock()
		RunService:BindToRenderStep(s.bind, Enum.RenderPriority.Camera.Value + 1, function()
			local camera = workspace.CurrentCamera
			camera.CameraType = Enum.CameraType.Scriptable
			local fine, cf, fov = pcall(cameraFn, os.clock() - start)
			if fine then
				camera.CFrame = cf
				camera.FieldOfView = fov
			end
		end)
		while not s.done and os.clock() - start < length do
			task.wait()
		end
	end)
	if not ok then
		warn("Cutscene failed:", err)
	end
	finish(s)
end)

return {}
