--!nonstrict
-- HE WILL COME - точка входа сервера.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local LobbyBuilder = require(script.Parent:WaitForChild("LobbyBuilder"))
local RoomService = require(script.Parent:WaitForChild("RoomService"))
local GazeTracker = require(script.Parent:WaitForChild("GazeTracker"))

local GROUP_PLAYERS = "HWCPlayers"
local GROUP_MONSTER = "HWCMonster"

local function setupCollisionGroups()
	for _, name in { GROUP_PLAYERS, GROUP_MONSTER } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GROUP_MONSTER, GROUP_PLAYERS, false)
	end)
end

local function setupLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0.4
	Lighting.Ambient = Color3.fromRGB(10, 10, 14)
	Lighting.OutdoorAmbient = Color3.fromRGB(14, 14, 20)
	Lighting.GlobalShadows = true
	Lighting.FogColor = Color3.fromRGB(6, 6, 9)
	Lighting.FogStart = 5
	Lighting.FogEnd = 120
end

setupCollisionGroups()
setupLighting()

local lobby = LobbyBuilder.build(GameConfig.Rooms.LobbyCenter)
local roomService = RoomService.new(lobby, GROUP_MONSTER)

-- Игроки --------------------------------------------------------------------

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

local function onCharacterAdded(player: Player, character)
	applyCollisionGroup(character)

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.WalkSpeed = GameConfig.Movement.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 45

	local match = roomService:getMatchOf(player)
	if match then
		task.spawn(function()
			match:onCharacterAdded(player, character)
		end)
	end
end

local function onPlayerAdded(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local escapes = Instance.new("IntValue")
	escapes.Name = "Побеги"
	escapes.Parent = stats
	stats.Parent = player

	player.RespawnLocation = lobby.Spawn

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end

	task.delay(1, function()
		if player.Parent then
			roomService:broadcast()
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	GazeTracker.clear(player)
	roomService:playerRemoving(player)
end)

-- Ввод от клиента -----------------------------------------------------------

Remotes.get("RoomAction").OnServerEvent:Connect(function(player, payload)
	roomService:handleAction(player, payload)
end)

Remotes.get("GazeReport").OnServerEvent:Connect(function(player, cameraPosition, lookVector)
	GazeTracker.set(player, cameraPosition, lookVector)
end)

Remotes.get("Crouch").OnServerEvent:Connect(function(player, value)
	local match = roomService:getMatchOf(player)
	if match then
		match:setCrouch(player, value)
	end
end)

Remotes.get("Flashlight").OnServerEvent:Connect(function(player, value)
	local match = roomService:getMatchOf(player)
	if match then
		match:setFlashlight(player, value)
	end
end)

print("[HE WILL COME] сервер запущен. Лобби готово.")
