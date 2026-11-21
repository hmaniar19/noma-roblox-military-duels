--!strict
-- Builds the whole world from code: the Camp More Maniar lobby and one arena per map, far enough apart
-- that each feels like its own place, plus the shared lighting and terrain colors.
local Lighting = game:GetService("Lighting")

local CampMoreManiar = require(script.Parent.Maps.CampMoreManiar)
local DesertOutpost = require(script.Parent.Maps.DesertOutpost)
local MapKit = require(script.Parent.Maps.MapKit)
local ShootingRange = require(script.Parent.Maps.ShootingRange)
local UrbanTown = require(script.Parent.Maps.UrbanTown)

export type World = { maps: { [string]: MapKit.MapInfo }, lobby: CampMoreManiar.LobbyInfo }

local World = {}

local SPACING = 1500

-- Grass with animated 3D blades (Decoration and GrassLength are set in default.project.json; scripts
-- can't change them at runtime) and natural material colors.
local function terrain()
	local t = workspace.Terrain
	t:Clear()
	pcall(function()
		t:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(92, 120, 54))
		t:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(78, 104, 46))
		t:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(104, 88, 66))
		t:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(74, 60, 46))
		t:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(196, 178, 136))
	end)
end

-- Late-afternoon sun with soft shadows, haze, volumetric clouds and light color grading.
local function lighting()
	Lighting.ClockTime = 15.2
	Lighting.Brightness = 3
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 122)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ShadowSoftness = 0.15
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Haze = 1.4
	atmosphere.Glare = 0.3
	atmosphere.Color = Color3.fromRGB(205, 212, 208)
	atmosphere.Decay = Color3.fromRGB(108, 118, 110)
	atmosphere.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Contrast, grade.Saturation = 0.08, 0.06
	grade.TintColor = Color3.fromRGB(255, 250, 240)
	grade.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.35, 24, 1.6
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity, rays.Spread = 0.06, 0.6
	rays.Parent = Lighting
	local clouds = Instance.new("Clouds")
	clouds.Cover, clouds.Density = 0.55, 0.65
	clouds.Parent = workspace.Terrain
end

function World.build(): World
	terrain()
	lighting()
	local lobby = CampMoreManiar(Vector3.new(0, 0, -SPACING))
	local maps = {}
	for i, build in { ShootingRange, DesertOutpost, UrbanTown } do
		local info = build(Vector3.new(0, 0, (i - 1) * SPACING))
		maps[info.id] = info
	end
	return { maps = maps, lobby = lobby }
end

return World
