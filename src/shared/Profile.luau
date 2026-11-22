--!strict
-- Reads the economy data the server publishes on each player. Ownership and equipped skins live in
-- two child folders ("Owned": item id -> true, "Skins": weapon id -> skin id) rather than on the
-- player, because Roblox caps one instance's attributes at 1024 bytes in total.
local Profile = {}

function Profile.owns(player: Player, id: string): boolean
	local owned = player:FindFirstChild("Owned")
	return owned ~= nil and owned:GetAttribute(id) == true
end

function Profile.skin(player: Player, weapon: string): string?
	local skins = player:FindFirstChild("Skins")
	local skin = skins and skins:GetAttribute(weapon)
	return if typeof(skin) == "string" then skin else nil
end

return Profile
