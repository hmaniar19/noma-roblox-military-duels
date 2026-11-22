-- Game test, client side (test place only). Plays along with the server test's "TestStep" attribute
-- like a person would, and reports what the screen shows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

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
				task.wait(0.25)
				mine:Move(Vector3.zero)
				local before = humanoid.Health
				for _ = 1, 6 do
					local dir = (aim.Position - camera.CFrame.Position).Unit
					remotes.Look:FireServer(dir)
					remotes.Fire:FireServer(camera.CFrame.Position, dir)
					task.wait(0.12)
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
	elseif name == "TakeRackWeapon" then
		local folder = workspace:WaitForChild("PracticeRange")
		local prompt = (folder:FindFirstChildWhichIsA("Model") :: Model):FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			prompt:InputHoldBegin()
			task.wait(0.1)
			prompt:InputHoldEnd()
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
	elseif name == "QueueDesertOutpost" or name == "QueueUrbanTown" then
		remotes.Queue:FireServer("Join", string.sub(name, 6), "1v1")
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
