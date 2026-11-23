--!strict
-- Loading screen with the game's dedication. Runs from ReplicatedFirst, so it shows before anything
-- else loads, and fades once the game has loaded and the player's character exists.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false

local back = Instance.new("Frame")
back.Size = UDim2.fromScale(1, 1)
back.BackgroundColor3 = Color3.fromRGB(22, 28, 20)
back.Parent = gui

local function text(content: string, y: number, size: number, color: Color3, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, y)
	label.Size = UDim2.new(0.9, 0, 0, size + 12)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = content
	label.Parent = back
	return label
end

local gold = Color3.fromRGB(235, 190, 60)
local title = text("MILITARY DUELS", 0.4, 64, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
local line = text("dedicated to Joanna & Eddie Moore", 0.5, 28, gold, Enum.Font.GothamMedium)
local loading = text("LOADING", 0.62, 16, Color3.fromRGB(170, 180, 160), Enum.Font.GothamBold)

gui.Parent = player:WaitForChild("PlayerGui")

local pulse = TweenService:Create(
	loading,
	TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ TextTransparency = 0.7 }
)
pulse:Play()

if not game:IsLoaded() then
	game.Loaded:Wait()
end
-- Fade after 30 s even if the character never arrives, so the screen can't hang forever.
local deadline = os.clock() + 30
while not player.Character and os.clock() < deadline do
	task.wait(0.25)
end
task.wait(1)
pulse:Cancel()

local fade = TweenInfo.new(0.8)
TweenService:Create(back, fade, { BackgroundTransparency = 1 }):Play()
for _, label in { title, line, loading } do
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
end
task.wait(0.9)
gui:Destroy()
