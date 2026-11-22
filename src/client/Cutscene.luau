--!strict
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

local function inkFrame(position: UDim2, rotation: number): Frame
	local frame = make("Frame", {
		AnchorPoint = CENTER,
		Position = position,
		Size = UDim2.fromOffset(0, 0),
		Rotation = rotation,
		BackgroundColor3 = INK_RED,
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

builders.Finisher = function(s, data, length)
	local winnerPos: Vector3 = data.winnerPos
	local defeatedPos: Vector3 = data.defeatedPos
	local focus: Vector3 = data.focus
	local side = flatSide(defeatedPos - winnerPos)
	local base = focus + side * 10 + Vector3.new(0, -1.3, 0)
	local target = focus + Vector3.new(0, 1.2, 0)

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
		tween(s, line, goal, 0.45, rng:NextNumber(0, 0.3), Enum.EasingStyle.Quad, -1)
	end

	local slashes: { { number } } = { { 0.36, 0.3, -32, 20 }, { 0.62, 0.42, -22, 14 }, { 0.5, 0.22, 26, 10 } }
	for i, sd in slashes do
		local slash = inkFrame(UDim2.fromScale(sd[1], sd[2]), sd[3])
		slash.Size = UDim2.fromOffset(0, sd[4])
		tween(s, slash, { Size = UDim2.new(1.1, 0, 0, sd[4]) }, 0.14, 0.1 + i * 0.18)
		tween(s, slash, { BackgroundTransparency = 1 }, 0.6, length - 1.1)
	end

	for _ = 1, 8 do
		local size = rng:NextInteger(18, 80)
		local dot = inkFrame(UDim2.fromScale(rng:NextNumber(0.2, 0.8), rng:NextNumber(0.12, 0.55)), 0)
		local delay = 0.3 + rng:NextNumber(0, 0.6)
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
	tween(s, banner, { Position = UDim2.fromScale(0.5, 0.74) }, 0.35, 0.25, Enum.EasingStyle.Back)

	return function(t)
		local e = 1 - (1 - math.clamp(t / 0.45, 0, 1)) ^ 3
		local pos = base - side * 0.8 * math.clamp(t / length, 0, 1)
		return CFrame.lookAt(pos, target) * CFrame.Angles(0, 0, math.rad(-10 * e)), 70 - 32 * e
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
