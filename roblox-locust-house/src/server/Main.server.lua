--!nonstrict
-- Точка входа сервера: строим дом, запускаем монстра и все системы.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LocustShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))

local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local MonsterAI = require(script.Parent:WaitForChild("MonsterAI"))
local RageService = require(script.Parent:WaitForChild("RageService"))
local BaitService = require(script.Parent:WaitForChild("BaitService"))
local RoundService = require(script.Parent:WaitForChild("RoundService"))

local NOISE = GameConfig.Noise
local MOVEMENT = GameConfig.Movement
local SLIDE = GameConfig.Slide

local GROUP_PLAYERS = "LocustPlayers"
local GROUP_MONSTER = "LocustMonster"
local GROUP_BAIT = "LocustBait"

-- Группы столкновений: монстр не толкает игроков, приманки никого не пинают.
local function setupCollisionGroups()
	for _, name in { GROUP_PLAYERS, GROUP_MONSTER, GROUP_BAIT } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GROUP_MONSTER, GROUP_PLAYERS, false)
		PhysicsService:CollisionGroupSetCollidable(GROUP_BAIT, GROUP_PLAYERS, false)
		PhysicsService:CollisionGroupSetCollidable(GROUP_BAIT, GROUP_MONSTER, false)
	end)
end

local function setupLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0.6
	Lighting.Ambient = Color3.fromRGB(16, 16, 22)
	Lighting.OutdoorAmbient = Color3.fromRGB(18, 18, 26)
	Lighting.GlobalShadows = true
	Lighting.FogColor = Color3.fromRGB(8, 8, 12)
	Lighting.FogStart = 10
	Lighting.FogEnd = 90
end

setupCollisionGroups()
setupLighting()

local map = MapBuilder.build()

local monster = MonsterAI.new(map, GROUP_MONSTER)
local rageService = RageService.new(monster)
local baitService = BaitService.new(monster, GROUP_BAIT)
local roundService = RoundService.new(map, monster, rageService, baitService)

monster.onCatch = function(player: Player)
	roundService:onCatch(player)
end

rageService.onTaunt = function(player: Player, line: string, multiplier: number)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		pcall(function()
			game:GetService("Chat"):Chat(head, line, Enum.ChatColor.Red)
		end)
	end
	roundService:notify(player, string.format("%s  (множитель x%.2f)", line, multiplier), "rage")
end

monster:start()
rageService:start()
baitService:start()
roundService:start()

-- Игроки --------------------------------------------------------------------

local function applyCollisionGroup(character: Model)
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

local function onCharacterAdded(player: Player, character: Model)
	applyCollisionGroup(character)
	player:SetAttribute("Escaped", false)

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = MOVEMENT.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 45
end

local function onPlayerAdded(player: Player)
	roundService:setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	rageService:unregister(player)
	baitService:unregister(player)
end)

-- Ввод от клиента -----------------------------------------------------------

local slideCooldowns: { [Player]: number } = {}

Remotes.get("Taunt").OnServerEvent:Connect(function(player)
	local ok, message = rageService:taunt(player)
	if not ok then
		roundService:notify(player, message, "bad")
	end
end)

Remotes.get("ThrowBait").OnServerEvent:Connect(function(player, direction)
	if typeof(direction) ~= "Vector3" then
		return
	end
	local ok, message = baitService:throw(player, direction)
	if not ok then
		roundService:notify(player, message, "bad")
	end
end)

Remotes.get("Slide").OnServerEvent:Connect(function(player)
	local now = os.clock()
	if (slideCooldowns[player] or 0) > now then
		return
	end
	slideCooldowns[player] = now + SLIDE.Cooldown * 0.8

	local root = Util.getRoot(player.Character)
	if root then
		monster:hear(root.Position, SLIDE.Noise)
	end
end)

-- Шум от бега: сервер сам замечает, что игрок спринтует.
task.spawn(function()
	while true do
		task.wait(NOISE.SprintInterval)
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Escaped") then
				continue
			end
			local character = player.Character
			local humanoid = Util.getHumanoid(character)
			local root = Util.getRoot(character)
			if humanoid and root and humanoid.Health > 0 then
				if humanoid.WalkSpeed >= MOVEMENT.SprintSpeed - 2 and humanoid.MoveDirection.Magnitude > 0.1 then
					monster:hear(root.Position, NOISE.SprintRadius)
				end
			end
		end
	end
end)

print("[Дом саранчи] сервер запущен. Раунд начат.")
