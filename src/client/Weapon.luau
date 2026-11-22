--!strict
-- Trigger, aim, reload, slot and gadget input; the first-person viewmodel for whatever is in hand;
-- look updates for the server's aim check; tracers and sounds for every shot the server confirms;
-- and following a teammate after you're eliminated. The client never decides hits.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Profile = require(ReplicatedStorage.Shared.Profile)

local player = Players.LocalPlayer :: Player
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local state = require(script.Parent.ArenaState)
local Fire = remotes:WaitForChild("Fire") :: RemoteEvent
local Equip = remotes:WaitForChild("Equip") :: RemoteEvent
local Gadget = remotes:WaitForChild("Gadget") :: RemoteEvent
local Reload = remotes:WaitForChild("Reload") :: RemoteEvent
local Aim = remotes:WaitForChild("Aim") :: RemoteEvent
local Look = remotes:WaitForChild("Look") :: RemoteEvent
local Stance = remotes:WaitForChild("Stance") :: RemoteEvent
local ShotFx = remotes:WaitForChild("ShotFx") :: RemoteEvent
local Banner = remotes:WaitForChild("Banner") :: RemoteEvent

local HIP = CFrame.new(0.5, -0.5, -1.1)
local ADS = CFrame.new(0, -0.42, -0.95)
local LOOK_INTERVAL = 2 / Config.AntiCheat.LookRate

local Weapon = {}
Weapon.aiming = false
Weapon.menuOpen = false -- set by Menu; keeps the cursor visible while a picker is open
Weapon.cutscene = false -- set by Cutscene; the first-person gun hides while one plays
Weapon.scoped = false -- looking through a sniper scope this frame; Hud draws the overlay

local firing = false
local aimBlend = 0
local recoil = 0
local swing = 0
local sprintBlend = 0
local lastLook = 0
local lastFire = 0

local viewmodel = Instance.new("Model")
viewmodel.Name = "Viewmodel"
local vmId: Config.WeaponId? = nil
local muzzle: Attachment? = nil

-- Reload animation: the magazine (or shotgun shells and pump) move relative to the handle.
local VM_SCALE = 0.42
local magPart: BasePart?, magHome: CFrame? = nil, nil
local pumpPart: BasePart?, pumpHome: CFrame? = nil, nil
local shell: Part? = nil
local reloadStart, reloadLength, reloadShells = 0, 1, 1
local magDropped, magClicked, lastShellSound = false, false, 0
local flash = Instance.new("PointLight")
flash.Color = Color3.fromRGB(255, 200, 120)
flash.Range = 12
flash.Brightness = 0

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalFx"
fxFolder.Parent = workspace

local function sound(id: string, parent: Instance, volume: number, speed: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume, s.PlaybackSpeed = volume, speed or 1
	s.Parent = parent
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end
Weapon.sound = sound

function Weapon.current(): (Config.WeaponId?, Config.Weapon?)
	local id = player:GetAttribute("Weapon") :: Config.WeaponId?
	return id, if id then Config.Weapons[id] else nil
end

-- The shot cue for a weapon's class: shotgun, sniper, automatic rifle or semi-automatic pistol.
local function shotCue(w: Config.Weapon?): { id: string, speed: number }
	local cues = Config.Sounds
	if not w then
		return cues.ShotRifle
	end
	return if w.pellets > 1
		then cues.ShotShotgun
		elseif w.scoped then cues.ShotSniper
		elseif w.auto then cues.ShotRifle
		else cues.ShotPistol
end

local function weaponNamed(name: string): Config.Weapon?
	for _, w in Config.Weapons do
		if w.name == name then
			return w
		end
	end
	return nil
end

-- Fighting right now: on a team, alive, not on the match-win celebration stage, and not watching a
-- cutscene.
function Weapon.inCombat(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local onStage = player:GetAttribute("Celebrating") == true
	local fighting = player:GetAttribute("Team") ~= nil and not onStage and not Weapon.cutscene
	return fighting and humanoid ~= nil and humanoid.Health > 0
end

-- Rebuilds the first-person model when the weapon in hand changes.
local function refreshViewmodel(id: Config.WeaponId)
	flash.Parent = nil -- the light is reused; detach it before the old model is destroyed
	-- A fresh model each time: ScaleTo is relative to the model's current scale, so reusing one
	-- would leave every weapon after the first at full size.
	viewmodel:Destroy()
	viewmodel = Instance.new("Model")
	viewmodel.Name = "Viewmodel"
	local handle = Gun.build(viewmodel, id, Profile.skin(player, id))
	viewmodel.PrimaryPart = handle
	viewmodel:ScaleTo(0.42)
	-- Cosmetic only: anchored, or gravity builds velocity between PivotTo calls until the parts are destroyed.
	for _, d in viewmodel:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	muzzle = handle:FindFirstChild("Muzzle") :: Attachment
	flash.Parent = muzzle
	vmId = id
	magPart = viewmodel:FindFirstChild("Mag") :: BasePart?
	magHome = if magPart then handle.CFrame:ToObjectSpace(magPart.CFrame) else nil
	pumpPart = viewmodel:FindFirstChild("Pump") :: BasePart?
	pumpHome = if pumpPart then handle.CFrame:ToObjectSpace(pumpPart.CFrame) else nil
	shell = nil
	if id == "Shotgun" then
		local s = Instance.new("Part")
		s.Shape = Enum.PartType.Cylinder
		s.Size = Vector3.new(0.5, 0.2, 0.2) * VM_SCALE
		s.Color = Color3.fromRGB(170, 30, 30)
		s.Material = Enum.Material.SmoothPlastic
		s.Anchored, s.CanCollide, s.CanQuery, s.CanTouch, s.CastShadow = true, false, false, false, false
		s.Transparency = 1
		s.Parent = viewmodel
		shell = s
	end
end

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The empty magazine falls out of the gun as a real (local-only) physics object.
local function dropMagazine(from: BasePart)
	local camera = workspace.CurrentCamera
	local m = Instance.new("Part")
	m.Size = from.Size / VM_SCALE
	m.CFrame = from.CFrame
	m.Color, m.Material = from.Color, from.Material
	m.CanQuery, m.CanTouch = false, false
	m.Parent = fxFolder
	m.AssemblyLinearVelocity = camera.CFrame.RightVector * 3 - Vector3.new(0, 6, 0)
	m.AssemblyAngularVelocity = Vector3.new(math.random() * 6 - 3, math.random() * 6 - 3, math.random() * 6 - 3)
	task.delay(6, m.Destroy, m)
end

-- Places the magazine, shell and pump for reload progress `t` (0..1), or `nil` when not reloading.
-- Magazines: out (15-35%), hand away (35-55%), new one in (55-80%), click and rack. Shotguns: one
-- shell per missing round, then a pump. The pump also cycles after every shotgun blast.
local function animateParts(handle: BasePart, id: Config.WeaponId, t: number?, sinceShot: number)
	local s = VM_SCALE
	if magPart and magHome then
		local off, visible = Vector3.zero, true
		if t then
			if t >= 0.15 and t < 0.35 then
				off = Vector3.new(0, -1.4 * ease((t - 0.15) / 0.2), 0)
			elseif t >= 0.35 and t < 0.55 then
				visible = false
				if not magDropped then
					magDropped = true
					dropMagazine(magPart)
				end
			elseif t >= 0.55 and t < 0.8 then
				local k = 1 - ease((t - 0.55) / 0.25)
				off = Vector3.new(0, -1.6 * k, 0.25 * k)
			elseif t >= 0.8 and not magClicked then
				magClicked = true
				sound(Config.Sounds.Reload, workspace.CurrentCamera, 0.6)
			end
		end
		magPart.CFrame = handle.CFrame * magHome * CFrame.new(off * s)
		magPart.Transparency = if visible then 0 else 1
	end
	if shell then
		local loading = t ~= nil and t >= 0.1 and t < 0.82
		shell.Transparency = if loading then 0 else 1
		if loading then
			local seg = ((t :: number) - 0.1) / 0.72 * reloadShells
			local k = ease((seg % 1) / 0.8)
			local from, to = Vector3.new(0.1, -1.0, -0.4), Vector3.new(0, 0.25, -0.6)
			shell.CFrame = handle.CFrame * CFrame.new(from:Lerp(to, k) * s) * CFrame.Angles(0, math.pi / 2, 0)
			if math.floor(seg) ~= lastShellSound and seg % 1 > 0.8 then
				lastShellSound = math.floor(seg)
				sound(Config.Sounds.Reload, workspace.CurrentCamera, 0.4)
			end
		end
	end
	if pumpPart and pumpHome then
		local pump = 0
		if t and t >= 0.84 then
			pump = math.sin(math.clamp((t - 0.84) / 0.16, 0, 1) * math.pi)
		elseif id == "Shotgun" and sinceShot > 0.15 and sinceShot < 0.6 then
			pump = math.sin((sinceShot - 0.15) / 0.45 * math.pi)
		end
		pumpPart.CFrame = handle.CFrame * pumpHome * CFrame.new(0, 0, 0.5 * pump * s)
	end
end

local function setAiming(on: boolean)
	if Weapon.aiming ~= on then
		Weapon.aiming = on
		Aim:FireServer(on)
	end
end

-- The server drops aim on equip and round start; while the button is still held, aim again.
local aimHeld = false
local function resyncAim()
	if aimHeld and Weapon.inCombat() then
		Weapon.aiming = true
		Aim:FireServer(true)
	end
end

-- Shows a blade's swing trail (Double Trouble) for the length of one swing.
local function flashTrail(handle: Instance?)
	local trail = handle and handle:FindFirstChild("SwingTrail")
	if trail and trail:IsA("Trail") then
		trail.Enabled = true
		task.delay(0.3, function()
			trail.Enabled = false
		end)
	end
end

local function tryFire()
	local _, w = Weapon.current()
	local now = os.clock()
	if not w or now - lastFire < w.fireInterval then
		return
	end
	if not w.auto then
		firing = false -- semi-automatic: one shot per click
	end
	local live = Weapon.inCombat() and state:GetAttribute("Phase") == "Live"
	if not live or player:GetAttribute("Reloading") or player:GetAttribute("Healing") then
		return
	end
	if w.kind == "gun" and (player:GetAttribute("Ammo") or 0) <= 0 then
		sound(Config.Sounds.Empty, workspace.CurrentCamera, 0.4)
		firing = false
		return
	end
	lastFire = now
	local camera = workspace.CurrentCamera
	Look:FireServer(camera.CFrame.LookVector)
	lastLook = now
	Fire:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
	if w.kind == "melee" then
		swing = 1
		flashTrail(viewmodel:FindFirstChild("Handle"))
		sound(Config.Sounds.Slash, camera, 0.5)
	else
		recoil = math.min(recoil + (if w.pellets > 1 or not w.auto then 1 else 0.35), 1.6)
		flash.Brightness = 4
		local cue = shotCue(w)
		sound(cue.id, camera, 0.5, cue.speed)
	end
end

local function hideTool()
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d:FindFirstAncestorOfClass("Tool") then
			d.LocalTransparencyModifier = 1
		end
	end
end

-- `color` comes from a special weapon's "Tracer" attribute (A Mother's Wrath fires blue shots).
local function tracer(from: Vector3, to: Vector3, hitWall: boolean, color: any)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = if typeof(color) == "Color3" then color else Color3.fromRGB(255, 214, 120)
	p.Size = if typeof(color) == "Color3" then Vector3.new(0.14, 0.14, length) else Vector3.new(0.07, 0.07, length)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.08), { Transparency = 1 }):Play()
	task.delay(0.1, p.Destroy, p)
	if hitWall then
		local puff = Instance.new("Part")
		puff.Anchored, puff.CanCollide, puff.CanQuery, puff.CanTouch = true, false, false, false
		puff.Shape = Enum.PartType.Ball
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = Color3.fromRGB(150, 140, 120)
		puff.Size = Vector3.new(0.4, 0.4, 0.4)
		puff.Position = to
		puff.Parent = fxFolder
		TweenService:Create(puff, TweenInfo.new(0.35), { Size = Vector3.new(1.6, 1.6, 1.6), Transparency = 1 }):Play()
		task.delay(0.4, puff.Destroy, puff)
	end
end

-- The camera keeps its orientation across respawns; face it the way the new spawn faces.
Banner.OnClientEvent:Connect(function(kind: string)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if kind == "RoundStart" and root then
		local camera = workspace.CurrentCamera
		camera.CFrame = CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + root.CFrame.LookVector)
	end
	if kind == "RoundStart" then
		resyncAim()
	end
end)

ShotFx.OnClientEvent:Connect(
	function(shooter: Model, origin: Vector3, hitPos: Vector3, hitWall: boolean, melee: boolean, cue: boolean)
		local tool = shooter and shooter:FindFirstChildOfClass("Tool")
		local handle = tool and tool:FindFirstChild("Handle")
		if shooter == player.Character then
			if not melee and muzzle then
				tracer(muzzle.WorldPosition, hitPos, hitWall, (muzzle.Parent :: Instance):GetAttribute("Tracer"))
			end
			return
		end
		if handle and tool then
			if cue and melee then
				sound(Config.Sounds.Slash, handle, 0.8)
			elseif cue then
				local c = shotCue(weaponNamed(tool.Name))
				sound(c.id, handle, 0.8, c.speed)
			end
			if melee then
				flashTrail(handle)
			end
		end
		local m = handle and handle:FindFirstChild("Muzzle")
		if not melee then
			local from = if m and m:IsA("Attachment") then m.WorldPosition else origin
			tracer(from, hitPos, hitWall, handle and handle:GetAttribute("Tracer"))
		end
	end
)

local function equipSlot(index: number)
	local slots = string.split((player:GetAttribute("Slots") or "") :: string, ",")
	if Weapon.inCombat() and slots[index] and slots[index] ~= "" then
		firing = false
		Equip:FireServer(index)
	end
end

local function slotIndex(): (number, number)
	local slots = string.split((player:GetAttribute("Slots") or "") :: string, ",")
	return table.find(slots, player:GetAttribute("Weapon") :: string) or 1, #slots
end

local KEY_SLOTS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 }

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		tryFire()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		aimHeld = true
		setAiming(true)
	elseif KEY_SLOTS[input.KeyCode] then
		equipSlot(KEY_SLOTS[input.KeyCode])
	elseif input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.Four then
		if Weapon.inCombat() and (player:GetAttribute("GadgetLeft") or 0) > 0 then
			Gadget:FireServer(workspace.CurrentCamera.CFrame.LookVector)
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		local id, w = Weapon.current()
		if Weapon.inCombat() and id and w and w.kind == "gun" and (player:GetAttribute("Ammo") or 0) < w.magazine then
			Reload:FireServer()
		end
	elseif input.KeyCode == Enum.KeyCode.LeftShift and Weapon.inCombat() then
		Stance:FireServer("Sprint")
	elseif input.KeyCode == Enum.KeyCode.C and Weapon.inCombat() then
		-- C while sprinting slides; otherwise it toggles crouch.
		local stance = player:GetAttribute("Stance")
		Stance:FireServer(if stance == "Sprint" then "Slide" elseif stance == "Crouch" then "Stand" else "Crouch")
	elseif input.KeyCode == Enum.KeyCode.Space and Weapon.inCombat() then
		-- A second press in mid-air is the double jump (the server allows one per landing).
		local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
			Stance:FireServer("DoubleJump")
			sound(Config.Sounds.Whoosh, workspace.CurrentCamera, 0.4)
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
		local index, count = slotIndex()
		if count > 1 then
			equipSlot((index - 1 + (if input.Position.Z < 0 then 1 else -1)) % count + 1)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		aimHeld = false
		setAiming(false)
	elseif input.KeyCode == Enum.KeyCode.LeftShift and player:GetAttribute("Stance") == "Sprint" then
		Stance:FireServer("Stand")
	end
end)

player:GetAttributeChangedSignal("Reloading"):Connect(function()
	if player:GetAttribute("Reloading") then
		local _, w = Weapon.current()
		reloadStart, reloadLength = os.clock(), if w then w.reloadTime else 2
		local ammo = (player:GetAttribute("Ammo") or 0) :: number
		reloadShells = if w then math.clamp(w.magazine - ammo, 1, 6) else 1
		magDropped, magClicked, lastShellSound = false, false, -1
		sound(Config.Sounds.Reload, workspace.CurrentCamera, 0.5)
	end
end)

-- After you're eliminated, watch a teammate who is still fighting.
local function followTeammate(camera: Camera)
	local team = player:GetAttribute("Team")
	if not team or state:GetAttribute("Phase") ~= "Live" then
		return
	end
	local current = camera.CameraSubject
	if current and current:IsA("Humanoid") and current.Health > 0 and current.Parent ~= player.Character then
		return
	end
	local candidates: { Instance } = {}
	local arena = player:GetAttribute("Arena")
	for _, other in Players:GetPlayers() do
		-- Teammates only from this match: every arena's characters carry a Team attribute.
		if other:GetAttribute("Arena") == arena then
			table.insert(candidates, other.Character :: any)
		end
	end
	-- Bots live in a folder per arena (Bots/<ArenaId>).
	local bots = workspace:FindFirstChild("Bots")
	local mine = if bots and typeof(arena) == "string" then bots:FindFirstChild(arena) else nil
	for _, bot in (if mine then mine:GetChildren() else {}) :: { Instance } do
		table.insert(candidates, bot)
	end
	for _, model in candidates do
		if model:GetAttribute("Team") == team and model ~= player.Character then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				camera.CameraSubject = humanoid
				return
			end
		end
	end
end

local nextFollowCheck = 0
RunService.RenderStepped:Connect(function(dt: number)
	Weapon.scoped = false
	local camera = workspace.CurrentCamera
	if not Weapon.inCombat() then
		viewmodel.Parent = nil
		vmId = nil -- rebuild next match, so a skin equipped in the lobby shows
		firing = false
		setAiming(false)
		camera.FieldOfView = 70
		UserInputService.MouseIconEnabled = true
		if os.clock() > nextFollowCheck then
			nextFollowCheck = os.clock() + 0.5
			followTeammate(camera)
		end
		return
	end
	local id, w = Weapon.current()
	if not id or not w then
		viewmodel.Parent = nil
		return
	end
	if id ~= vmId then
		refreshViewmodel(id)
		aimBlend = 0 -- a new weapon starts unaimed, so a sniper never flashes its scope on the swap
		resyncAim()
	end
	UserInputService.MouseIconEnabled = Weapon.menuOpen
	hideTool()
	if firing then
		tryFire()
	end
	local now = os.clock()
	if now - lastLook >= LOOK_INTERVAL then
		lastLook = now
		Look:FireServer(camera.CFrame.LookVector)
	end

	Weapon.scoped = w.scoped and Weapon.aiming and aimBlend > 0.9
	local reloading = player:GetAttribute("Reloading") == true
	local healing = player:GetAttribute("Healing") == true
	aimBlend += ((if Weapon.aiming and w.kind == "gun" and not reloading then 1 else 0) - aimBlend) * math.min(
		dt * 14,
		1
	)
	recoil = math.max(recoil - dt * 6, 0)
	swing = math.max(swing - dt * 5, 0)
	flash.Brightness = math.max(flash.Brightness - dt * 60, 0)
	camera.FieldOfView = 70 - (if w.scoped then 50 else 20) * aimBlend
	local offset = HIP:Lerp(ADS, aimBlend)
	local kick = CFrame.new(0, 0, recoil * 0.25) * CFrame.Angles(recoil * 0.08, 0, 0)
	local stab = CFrame.new(-0.3 * swing, 0.1 * swing, -0.9 * swing) * CFrame.Angles(0, 0, -0.6 * swing)
	-- Reload: roll the gun to show the magazine well, slap the new one home, roll back.
	local t = if reloading then math.clamp((now - reloadStart) / reloadLength, 0, 1) else nil
	local tilt = if t then ease(t / 0.15) * (1 - ease((t - 0.85) / 0.15)) else 0
	local slap = if t and t > 0.78 and t < 0.86 then math.sin((t - 0.78) / 0.08 * math.pi) * 0.05 else 0
	local pose = CFrame.new(-0.08 * tilt, -0.1 * tilt + slap, 0.06 * tilt)
		* CFrame.Angles(0.3 * tilt, 0.2 * tilt, 0.75 * tilt)
	local dip = if healing then CFrame.new(0, -0.5, 0) * CFrame.Angles(-0.6, 0, 0.3) else CFrame.identity
	-- Sprinting carries the gun low and angled across the body.
	sprintBlend += ((if player:GetAttribute("Stance") == "Sprint" then 1 else 0) - sprintBlend) * math.min(dt * 10, 1)
	dip *= CFrame.new(-0.15 * sprintBlend, -0.15 * sprintBlend, 0.05 * sprintBlend) * CFrame.Angles(
		-0.35 * sprintBlend,
		0.5 * sprintBlend,
		0.2 * sprintBlend
	)
	viewmodel.Parent = if Weapon.scoped then nil else camera
	viewmodel:PivotTo(camera.CFrame * offset * kick * stab * pose * dip)
	if viewmodel.PrimaryPart then
		animateParts(viewmodel.PrimaryPart, id, t, now - lastFire)
	end
end)

return Weapon
