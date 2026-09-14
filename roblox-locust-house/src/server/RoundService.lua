--!nonstrict
-- Раунд: ключи -> открыть выход -> сбежать. Плюс поимка, очки и синхронизация с клиентом.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("LocustShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))

local ROUND = GameConfig.Round
local NOISE = GameConfig.Noise

local notifyEvent = Remotes.get("Notify")
local syncEvent = Remotes.get("StateSync")
local jumpscareEvent = Remotes.get("Jumpscare")

local RoundService = {}
RoundService.__index = RoundService

function RoundService.new(map, monster, rageService, baitService)
	local self = setmetatable({}, RoundService)
	self.map = map
	self.monster = monster
	self.rage = rageService
	self.bait = baitService
	self.keysCollected = 0
	self.keysTotal = ROUND.KeysToEscape
	self.keyFolder = Instance.new("Folder")
	self.keyFolder.Name = "Keys"
	self.keyFolder.Parent = Workspace
	self.resetting = false
	return self
end

function RoundService:notify(player: Player?, text: string, color: string?)
	if player then
		notifyEvent:FireClient(player, text, color)
	else
		notifyEvent:FireAllClients(text, color)
	end
end

function RoundService:setupPlayer(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"

	local escapes = Instance.new("IntValue")
	escapes.Name = "Побеги"
	escapes.Parent = stats

	local score = Instance.new("IntValue")
	score.Name = "Дерзость"
	score.Parent = stats

	stats.Parent = player

	self.rage:register(player)
	self.bait:register(player)
	player:SetAttribute("Escaped", false)
end

function RoundService:addScore(player: Player, amount: number)
	local stats = player:FindFirstChild("leaderstats")
	local score = stats and stats:FindFirstChild("Дерзость")
	if score and score:IsA("IntValue") then
		score.Value += amount
	end
end

function RoundService:_spawnKeys()
	self.keyFolder:ClearAllChildren()
	self.keysCollected = 0

	local spots = table.clone(self.map.KeySpots)
	for i = #spots, 2, -1 do
		local j = math.random(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end

	for index = 1, math.min(self.keysTotal, #spots) do
		local position = spots[index]

		local pedestal = Instance.new("Part")
		pedestal.Name = "Pedestal"
		pedestal.Size = Vector3.new(3, 3, 3)
		pedestal.Position = position - Vector3.new(0, 1.5, 0)
		pedestal.Anchored = true
		pedestal.Color = Color3.fromRGB(40, 40, 46)
		pedestal.Material = Enum.Material.Slate
		pedestal.Parent = self.keyFolder

		local key = Instance.new("Part")
		key.Name = "Key"
		key.Size = Vector3.new(1, 2, 1)
		key.Position = position + Vector3.new(0, 1.5, 0)
		key.Anchored = true
		key.CanCollide = false
		key.Color = Color3.fromRGB(255, 214, 90)
		key.Material = Enum.Material.Neon
		key.Parent = self.keyFolder

		local light = Instance.new("PointLight")
		light.Color = key.Color
		light.Range = 18
		light.Brightness = 2
		light.Parent = key

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Забрать ключ"
		prompt.ObjectText = "Ключ"
		prompt.HoldDuration = 0.6
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = key

		prompt.Triggered:Connect(function(player)
			if not key.Parent then
				return
			end
			key:Destroy()
			self:_onKeyTaken(player, position)
		end)
	end

	self:_updateDoor()
end

function RoundService:_onKeyTaken(player: Player, position: Vector3)
	self.keysCollected += 1
	-- Ключ шумит: монстр слышит, что кто-то шарится.
	self.monster:hear(position, NOISE.DoorRadius)
	self:addScore(player, ROUND.KeyScore)

	if self.keysCollected >= self.keysTotal then
		self:notify(nil, "Все ключи собраны! Выход открыт - бегом на север!", "good")
	else
		self:notify(nil, string.format("Ключ %d/%d", self.keysCollected, self.keysTotal), "good")
	end
	self:_updateDoor()
end

function RoundService:_updateDoor()
	local door = self.map.ExitDoor
	local locked = self.keysCollected < self.keysTotal
	door:SetAttribute("Locked", locked)
	door.CanCollide = locked
	door.Transparency = locked and 0 or 0.75
	door.Color = locked and Color3.fromRGB(120, 30, 30) or Color3.fromRGB(40, 170, 90)
end

function RoundService:onCatch(player: Player)
	if player:GetAttribute("Escaped") then
		return
	end
	local humanoid = Util.getHumanoid(player.Character)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local state = self.rage:getState(player)
	local lost = state.bank
	self.rage:wipe(player)

	jumpscareEvent:FireClient(player)
	if lost > 0 then
		self:notify(player, string.format("Саранча тебя схватила. Сгорело дерзости: %d", lost), "bad")
	else
		self:notify(player, "Саранча тебя схватила!", "bad")
	end

	task.delay(0.7, function()
		local hum = Util.getHumanoid(player.Character)
		if hum then
			hum.Health = 0
		end
	end)
end

function RoundService:onEscape(player: Player)
	if player:GetAttribute("Escaped") then
		return
	end
	if self.map.ExitDoor:GetAttribute("Locked") then
		self:notify(player, "Дверь заперта - нужны все ключи", "bad")
		return
	end

	player:SetAttribute("Escaped", true)

	local bank = self.rage:cashOut(player)
	local total = ROUND.EscapeScore + bank
	self:addScore(player, total)

	local stats = player:FindFirstChild("leaderstats")
	local escapes = stats and stats:FindFirstChild("Побеги")
	if escapes and escapes:IsA("IntValue") then
		escapes.Value += 1
	end

	self:notify(nil, string.format("%s сбежал(а)! +%d дерзости", player.DisplayName, total), "good")
	self:_scheduleReset()
end

function RoundService:_scheduleReset()
	if self.resetting then
		return
	end
	self.resetting = true
	task.delay(ROUND.IntermissionTime, function()
		self:startRound()
		self.resetting = false
	end)
end

function RoundService:startRound()
	self:_spawnKeys()
	self.rage:reset()
	self.bait:clear()
	self.monster:teleportToSpawn()

	for _, player in Players:GetPlayers() do
		player:SetAttribute("Escaped", false)
		self.bait:refill(player)
		local root = Util.getRoot(player.Character)
		if root then
			root.CFrame = CFrame.new(self.map.SpawnPosition + Vector3.new(math.random(-6, 6), 3, math.random(-6, 6)))
		end
	end

	self:notify(nil, string.format("НОВЫЙ ЗАХОД. Найди %d ключа(ей) и беги к выходу.", self.keysTotal), "info")
end

function RoundService:_bindEscapePad()
	local pad = self.map.EscapePad
	pad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			self:onEscape(player)
		end
	end)
end

function RoundService:start()
	self:_bindEscapePad()
	self:startRound()

	-- Синхронизация HUD.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.2 then
			return
		end
		accumulator = 0

		local monsterRoot = self.monster.rig.Root
		for _, player in Players:GetPlayers() do
			local root = Util.getRoot(player.Character)
			local distance = root and (monsterRoot.Position - root.Position).Magnitude or 999
			local state = self.rage:getState(player)
			syncEvent:FireClient(player, {
				rage = self.rage.rage,
				multiplier = self.rage:getMultiplier(player),
				streak = state.streak,
				bank = state.bank,
				baits = self.bait:getCharges(player),
				keys = self.keysCollected,
				keysTotal = self.keysTotal,
				locked = self.map.ExitDoor:GetAttribute("Locked"),
				monsterState = self.monster.state,
				distance = distance,
				escaped = player:GetAttribute("Escaped"),
			})
		end
	end)
end

return RoundService
