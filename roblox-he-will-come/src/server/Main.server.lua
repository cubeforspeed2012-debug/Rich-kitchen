--!nonstrict
-- HE WILL COME v2 - точка входа сервера.
-- Порядок важен: сначала Remotes (иначе клиент не дождётся), потом всё остальное.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

print("[HE WILL COME] remotes созданы")

local LobbyBuilder = require(script.Parent:WaitForChild("LobbyBuilder"))
local Rooms = require(script.Parent:WaitForChild("Rooms"))

local GROUP_PLAYERS = "HWCPlayers"
local GROUP_MONSTER = "HWCMonster"

-- монстр не толкает игроков и не даёт себя толкать
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP_PLAYERS)
end)
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP_MONSTER)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(GROUP_MONSTER, GROUP_PLAYERS, false)
end)

-- ночь
Lighting.ClockTime = 0
Lighting.Brightness = 0.5
Lighting.Ambient = Color3.fromRGB(14, 14, 18)
Lighting.OutdoorAmbient = Color3.fromRGB(22, 22, 30)
Lighting.GlobalShadows = true
Lighting.FogColor = Color3.fromRGB(8, 8, 12)
Lighting.FogStart = 20
Lighting.FogEnd = 160

local lobby = LobbyBuilder.build(GameConfig.Rooms.LobbyCenter)
local rooms = Rooms.new(lobby, GROUP_MONSTER)
print("[HE WILL COME] лобби построено")

-- ---------------- игроки ----------------

local function applyCollisionGroup(character)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = GROUP_PLAYERS
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = GROUP_PLAYERS
		end
	end)
end

local function onCharacterAdded(player, character)
	applyCollisionGroup(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.WalkSpeed = GameConfig.Movement.WalkSpeed
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 45
	end
	local match = rooms:getMatchOf(player)
	if match then
		task.spawn(function()
			match:onCharacterAdded(player, character)
		end)
	end
end

local function onPlayerAdded(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local escapes = Instance.new("IntValue")
	escapes.Name = "Побеги"
	escapes.Parent = stats
	local keys = Instance.new("IntValue")
	keys.Name = "Ключи"
	keys.Parent = stats
	stats.Parent = player

	player.RespawnLocation = lobby.Spawn
	player:SetAttribute("InMatch", false)
	player:SetAttribute("Downed", false)
	player:SetAttribute("Hidden", false)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end

	task.delay(1, function()
		if player.Parent then
			rooms:broadcast()
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	rooms:leave(player)
end)

-- ---------------- ввод от клиента ----------------

Remotes.get("RoomAction").OnServerEvent:Connect(function(player, payload)
	local ok, err = pcall(function()
		rooms:handleAction(player, payload)
	end)
	if not ok then
		warn("[HE WILL COME] ошибка RoomAction: " .. tostring(err))
	end
end)

Remotes.get("PlayerAction").OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" or typeof(payload.action) ~= "string" then
		return
	end
	local match = rooms:getMatchOf(player)
	if not match then
		return
	end
	local ok, err = pcall(function()
		match:playerAction(player, payload.action, payload.value)
	end)
	if not ok then
		warn("[HE WILL COME] ошибка PlayerAction: " .. tostring(err))
	end
end)

print("[HE WILL COME] сервер запущен")
