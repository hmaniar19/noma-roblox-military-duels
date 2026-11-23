--!strict
-- The player's HUD color theme (Config.HudThemes). The server saves the pick and publishes it as the
-- "HudTheme" player attribute; screens call Theme.watch to recolor whenever it changes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Theme = { id: string, name: string, primary: Color3, accent: Color3 }

local player = Players.LocalPlayer :: Player
local Theme = {}

function Theme.current(): Theme
	local id = player:GetAttribute("HudTheme")
	for _, t in Config.HudThemes do
		if t.id == id then
			return t
		end
	end
	return Config.HudThemes[1]
end

-- Calls `apply` now and again every time the theme changes.
function Theme.watch(apply: (Theme) -> ())
	apply(Theme.current())
	player:GetAttributeChangedSignal("HudTheme"):Connect(function()
		apply(Theme.current())
	end)
end

return Theme
