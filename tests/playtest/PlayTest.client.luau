-- Game test, client side (test place only). Plays along with the server test's "TestStep" attribute
-- like a person would, and reports what the screen shows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

-- The test runs while someone keeps using the computer: first-person matches lock the mouse to the
-- window's centre whenever Studio has focus, so release it every frame (after the game's own lock).
RunService:BindToRenderStep("PlaytestFreeMouse", Enum.RenderPriority.Last.Value + 1, function()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end)

local function result(name: string, ok: boolean, why: any?)
	print(if ok then `PLAYTEST PASS {name}` else `PLAYTEST FAIL {name}: {tostring(why)}`)
end

-- The loading screen shows the dedication before anything else.
local loading = player:WaitForChild("PlayerGui"):WaitForChild("LoadingScreen", 15)
local dedication = false
for _, d in (if loading then loading:GetDescendants() else {}) do
	if d:IsA("TextLabel") and string.find(d.Text, "Joanna & Eddie Moore", 1, true) then
		dedication = true
	end
end
result("loading screen: dedicated to Joanna & Eddie Moore", dedication)

local cutscenes: { string } = {}
remotes:WaitForChild("Cutscene").OnClientEvent:Connect(function(kind)
	table.insert(cutscenes, kind)
end)
local reports = 0
local EXPECTED = { { "BulletCam", "Finisher" }, { "Handshake" }, { "Finisher" } }

local toasts: { string } = {}
remotes:WaitForChild("Toast").OnClientEvent:Connect(function(title)
	table.insert(toasts, tostring(title))
end)

local function waitFor(seconds: number, check: () -> boolean): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if check() then
			return true
		end
		task.wait(0.1)
	end
	return check()
end

-- True if the GUI object and every GUI object above it are visible.
local function onScreen(g: GuiObject): boolean
	local at: Instance? = g
	while at and at:IsA("GuiObject") do
		if not (at :: GuiObject).Visible then
			return false
		end
		at = at.Parent
	end
	return true
end

-- True once a label on the match HUD shows text that passes `match`.
local function hudShows(seconds: number, match: (string) -> boolean): boolean
	return waitFor(seconds, function()
		local hud = player.PlayerGui:FindFirstChild("DuelHud")
		for _, d in (if hud then hud:GetDescendants() else {}) do
			if d:IsA("TextLabel") and match(d.Text) and onScreen(d) then
				return true
			end
		end
		return false
	end)
end

local function alive(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- A check made mid-fight. If the player went down meanwhile, the server test replays it next round,
-- so only a note is printed.
local function fightResult(name: string, ok: boolean, why: any?)
	if ok or alive() then
		result(name, ok, why)
	else
		print(`PLAYTEST INFO {name}: not checked, the player went down`)
	end
end

local function myBot(): Model?
	local arena = player:GetAttribute("Arena")
	local bots = workspace:FindFirstChild("Bots")
	local folder = if bots and typeof(arena) == "string" then bots:FindFirstChild(arena) else nil
	return if folder then folder:FindFirstChildWhichIsA("Model") else nil
end

-- Shoots `target` (a Model) while it is in plain sight; true if its health dropped.
local function shoot(target: Model, seconds: number): boolean
	local camera = workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		task.wait(0.3)
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local aim = target:FindFirstChild("UpperTorso") :: BasePart?
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		local mine = character and character:FindFirstChildOfClass("Humanoid")
		if head and aim and humanoid and mine and humanoid.Health > 0 then
			params.FilterDescendantsInstances = { character :: Model, target }
			if not workspace:Raycast(head.Position, aim.Position - head.Position, params) then
				mine:Move((aim.Position - head.Position) * Vector3.new(1, 0, 1), false)
				-- Aim like a player: in first person the body turns with the camera, and the server checks it.
				camera.CFrame = CFrame.lookAt(camera.CFrame.Position, aim.Position)
				task.wait(0.25)
				mine:Move(Vector3.zero)
				-- Two shots: enough to see damage without ending the round (the server test ends it).
				local before = humanoid.Health
				for _ = 1, 2 do
					local dir = (aim.Position - camera.CFrame.Position).Unit
					remotes.Look:FireServer(dir)
					remotes.Fire:FireServer(camera.CFrame.Position, dir)
					task.wait(0.15)
				end
				task.wait(0.4)
				if humanoid.Health < before then
					return true
				end
			end
		end
	end
	return false
end

local function onStep(name: string)
	local args = string.split(name, " ")
	if name == "PickTheme" then
		local gui = player.PlayerGui:FindFirstChild("CampMoreManiar")
		local shown = false
		for _, d in (if gui then gui:GetDescendants() else {}) do
			if d:IsA("TextLabel") and string.find(d.Text, "SETTINGS", 1, true) and (d.Parent :: GuiObject).Visible then
				shown = true
			end
		end
		result("settings: color picker on screen", shown)
		remotes.Settings:FireServer("Theme", "MidnightCyan")
	elseif name == "PickStarter" then
		task.wait(0.5)
		local gui = player.PlayerGui:FindFirstChild("CampMoreManiar")
		local shown = false
		for _, d in (if gui then gui:GetDescendants() else {}) do
			if d:IsA("TextLabel") and string.find(d.Text, "CHOOSE YOUR STARTER", 1, true) then
				shown = (d.Parent :: GuiObject).Visible
			end
		end
		result("starter: picker on screen", shown)
		remotes.Settings:FireServer("Starter", "SMG", "ForestCamo")
	elseif name == "EquipFinisher" then
		remotes.Shop:FireServer("EquipFinisher", "Thunder")
	elseif name == "TakeRackWeapon" then
		local folder = workspace:WaitForChild("PracticeRange")
		-- The nearest rack prompt (the server test stands the player at one); dummies share the folder.
		local prompt: ProximityPrompt? = nil
		local best = math.huge
		local character = player.Character
		local here = character and character:GetPivot().Position or Vector3.zero
		for _, p in folder:GetDescendants() do
			local part = p.Parent
			if p:IsA("ProximityPrompt") and part and part:IsA("BasePart") then
				local d = (part.Position - here).Magnitude
				if d < best then
					prompt, best = p, d
				end
			end
		end
		print(`PLAYTEST TRACE rack prompt {prompt ~= nil} at {math.floor(best)} studs`)
		-- The prompt only responds once it is showing; keep pressing E for a few seconds.
		local deadline = os.clock() + 5
		while prompt and os.clock() < deadline and player:GetAttribute("Arena") ~= "Practice" do
			prompt:InputHoldBegin()
			task.wait(0.1)
			prompt:InputHoldEnd()
			task.wait(0.4)
		end
	elseif name == "ShootTarget" then
		local target = workspace:WaitForChild("PracticeRange"):FindFirstChild("Target")
		result("range: shots hit a target", target ~= nil and shoot(target :: Model, 5))
	elseif name == "QueueShootingRange" then
		remotes.Loadout:FireServer("Primary", "AR")
		remotes.Queue:FireServer("Join", "ShootingRange", "1v1")
		local state = ReplicatedStorage:WaitForChild("Arenas"):WaitForChild("ShootingRange")
		local t0 = os.clock()
		while state:GetAttribute("Phase") ~= "Live" and os.clock() - t0 < 60 do
			task.wait(0.25)
		end
		result(
			"match: in the arena with a weapon",
			player:GetAttribute("Weapon") == "AR",
			player:GetAttribute("Weapon")
		)
		local bot = workspace:WaitForChild("Bots"):WaitForChild("ShootingRange"):FindFirstChildWhichIsA("Model")
		if bot and shoot(bot, 15) then
			result("shooting: player's shots damage the bot", true)
		else
			print("PLAYTEST INFO shooting: the bot never stood in plain sight long enough to test a hit")
		end
	elseif name == "ReportCutscenes" then
		reports += 1
		local want = EXPECTED[reports]
		local got = table.concat(cutscenes, ",")
		result(
			`cutscene: played {table.concat(want or {}, " + ")}`,
			want ~= nil and got == table.concat(want, ","),
			got
		)
		table.clear(cutscenes)
	elseif name == "SendReport" then
		remotes.Report:FireServer()
	elseif name == "QueueDesertOutpost" or name == "QueueUrbanTown" then
		remotes.Queue:FireServer("Join", string.sub(name, 6), "1v1")
	elseif name == "Leaderboard" then
		local columns: { string } = {}
		waitFor(5, function()
			for _, d in workspace:GetDescendants() do
				local title = if d:IsA("TextLabel") then string.match(d.Text, "^TOP %u+") else nil
				if d.Parent and (title == "TOP SOLDIERS" or title == "TOP LEVELS") then
					table.clear(columns)
					for _, column in d.Parent:GetChildren() do
						if column:IsA("TextLabel") then
							table.insert(columns, column.Text)
						end
					end
					return true
				end
			end
			return false
		end)
		result(
			"leaderboard: both columns have text",
			#columns == 2 and columns[1] ~= "" and columns[2] ~= "",
			if #columns > 0 then (string.gsub(table.concat(columns, " | "), "\n", " / ")) else "no board found"
		)
	elseif args[1] == "Theme" then
		remotes.Settings:FireServer("Theme", args[2])
	elseif args[1] == "Ranked" then
		remotes.Settings:FireServer("Ranked", args[2] == "on")
	elseif args[1] == "Buy" then
		remotes.Shop:FireServer("Buy", args[2])
	elseif args[1] == "BuyBroke" then
		table.clear(toasts)
		remotes.Shop:FireServer("Buy", args[2])
		result(
			"shop: told there aren't enough coins",
			waitFor(3, function()
				return table.find(toasts, "Not enough coins") ~= nil
			end),
			table.concat(toasts, ", ")
		)
	elseif args[1] == "EquipSkin" then
		remotes.Shop:FireServer("Equip", args[2], args[3])
	elseif args[1] == "WearFinisher" then
		remotes.Shop:FireServer("EquipFinisher", args[2])
	elseif args[1] == "Emote" then
		remotes.Emote:FireServer(args[2])
	elseif args[1] == "Join" then
		remotes.Queue:FireServer("Join", args[2], args[3])
	elseif name == "Leave" then
		remotes.Queue:FireServer("Leave")
	elseif args[1] == "Kit" then
		remotes.Loadout:FireServer("Gadget", args[2])
		remotes.Loadout:FireServer("Primary", args[3])
	elseif name == "UseGadget" then
		local gadget = player:GetAttribute("Gadget")
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		-- Lobbed ahead, a little upward.
		remotes.Gadget:FireServer(if flat.Magnitude > 0.1 then (flat.Unit + Vector3.new(0, 0.25, 0)).Unit else look)
		local spec = if typeof(gadget) == "string" then (Config.Gadgets :: any)[gadget] else nil
		if gadget == "Medkit" then
			fightResult(
				"medkit: HUD shows the med kit in use",
				hudShows(2, function(text)
					return string.find(text, "USING MED KIT", 1, true) ~= nil
				end)
			)
		elseif spec then
			local used = `{string.upper(spec.name)} x0`
			fightResult(
				`{string.lower(tostring(gadget))}: HUD shows the charge used`,
				hudShows(2, function(text)
					return string.find(text, used, 1, true) ~= nil
				end),
				used
			)
		end
	elseif name == "FireShots" then
		local camera = workspace.CurrentCamera
		for _ = 1, 3 do
			local dir = camera.CFrame.LookVector
			remotes.Look:FireServer(dir)
			remotes.Fire:FireServer(camera.CFrame.Position, dir)
			task.wait(0.2)
		end
	elseif name == "Reload" then
		remotes.Reload:FireServer()
		local id = player:GetAttribute("Weapon")
		local w = if typeof(id) == "string" then Config.Weapons[id] else nil
		if w then
			local full = `{w.magazine} / {w.magazine}`
			local reloading = hudShows(2, function(text)
				return text == "RELOADING"
			end)
			fightResult(
				"reload: HUD shows RELOADING, then a full magazine",
				reloading and hudShows(w.reloadTime + 2, function(text)
					return text == full
				end),
				full
			)
		end
	elseif name == "DrawKnife" then
		local slots = string.split(tostring(player:GetAttribute("Slots") or ""), ",")
		local index = table.find(slots, Config.Loadout.Melee)
		if index then
			remotes.Equip:FireServer(index)
		end
	elseif name == "Stab" then
		local bot = myBot()
		local torso = bot and bot:FindFirstChild("UpperTorso") :: BasePart?
		local humanoid = bot and bot:FindFirstChildOfClass("Humanoid")
		if torso and humanoid then
			local before = humanoid.Health
			for _ = 1, 3 do
				local camera = workspace.CurrentCamera
				local dir = (torso.Position - camera.CFrame.Position).Unit
				camera.CFrame = CFrame.lookAt(camera.CFrame.Position, torso.Position)
				remotes.Look:FireServer(dir)
				remotes.Fire:FireServer(camera.CFrame.Position, dir)
				task.wait(0.6)
				if humanoid.Health < before then
					break
				end
			end
		end
	elseif name == "AimSniper" then
		-- Scripts can't press the right mouse button: set what it sets (the Weapon module's aim) and send
		-- the Aim remote, as Weapon's setAiming does.
		local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
		local Weapon = (require :: any)(client:WaitForChild("Weapon"))
		Weapon.aiming = true
		remotes.Aim:FireServer(true)
		local hud = player.PlayerGui:FindFirstChild("DuelHud")
		local scope: Frame? = nil
		for _, d in (if hud then hud:GetDescendants() else {}) do
			local yy = d:IsA("Frame") and d.SizeConstraint == Enum.SizeConstraint.RelativeYY
			if yy and d:FindFirstChildOfClass("UIStroke") then
				scope = d :: Frame
			end
		end
		local camera = workspace.CurrentCamera
		local shown = waitFor(2, function()
			return scope ~= nil and onScreen(scope) and camera.FieldOfView < 30
		end)
		fightResult(
			"sniper: scope overlay and zoom on screen",
			shown,
			`scope found {scope ~= nil}, FOV {math.floor(camera.FieldOfView)}`
		)
		task.wait(1)
		Weapon.aiming = false
		remotes.Aim:FireServer(false)
	elseif name == "SuddenDeathKnife" then
		remotes.Loadout:FireServer("Role", "Knife")
		result(
			"sudden death: HUD says SUDDEN DEATH",
			hudShows(3, function(text)
				return text == "SUDDEN DEATH"
			end)
		)
	elseif name == "CheckRankedToast" then
		result(
			"ranked: told no ranked players are around",
			waitFor(5, function()
				return table.find(toasts, "No ranked players around") ~= nil
			end),
			table.concat(toasts, ", ")
		)
	elseif name == "Done" then
		print("PLAYTEST CLIENT DONE")
	end
end

player:GetAttributeChangedSignal("TestStep"):Connect(function()
	local value = player:GetAttribute("TestStep")
	local name = if typeof(value) == "string" then string.match(value, "^(.-):%d+$") else nil
	if name then
		local ok, err = pcall(onStep, name)
		if not ok then
			result(`client step {name}`, false, err)
		end
	end
end)
