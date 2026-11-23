--!strict
-- Bots look like the players' Roblox friends, so a duel against a bot feels like playing someone
-- real. Friend lists come from Players:GetFriendsAsync (first page, cached per player for the
-- session); any failure just leaves the bot with its standard look.
local Players = game:GetService("Players")

export type Friend = { userId: number, name: string }

local Friends = {}

local cache: { [number]: { Friend } } = {}
local random = Random.new()

local function listOf(userId: number): { Friend }
	local cached = cache[userId]
	if cached then
		return cached
	end
	local list: { Friend } = {}
	pcall(function()
		local pages = Players:GetFriendsAsync(userId)
		for _, f in pages:GetCurrentPage() do
			table.insert(list, { userId = f.Id, name = f.DisplayName })
		end
	end)
	cache[userId] = list
	return list
end

-- Up to `count` different friends of `players`, never anyone who is in this server.
function Friends.pick(players: { Player }, count: number): { Friend }
	local here: { [number]: boolean } = {}
	for _, p in Players:GetPlayers() do
		here[p.UserId] = true
	end
	local pool: { Friend } = {}
	local seen: { [number]: boolean } = {}
	for _, p in players do
		for _, f in listOf(p.UserId) do
			if not here[f.userId] and not seen[f.userId] then
				seen[f.userId] = true
				table.insert(pool, f)
			end
		end
	end
	local picked = {}
	while #picked < count and #pool > 0 do
		table.insert(picked, table.remove(pool, random:NextInteger(1, #pool)) :: Friend)
	end
	return picked
end

Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
end)

return Friends
