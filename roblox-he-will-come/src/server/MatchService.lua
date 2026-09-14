--!nonstrict
-- Матч одной комнаты: тихая фаза -> ОН приходит -> предохранители -> генератор -> побег.
-- Плюс рассудок, поднятие напарников и синхронизация HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))

local MATCH = GameConfig.Match
local NOISE = GameConfig.Noise
local SANITY = GameConfig.Sanity
local MOVEMENT = GameConfig.Movement

local syncEvent = Remotes.get("MatchSync")
local notifyEvent = Remotes.get("Notify")
local scareEvent = Remotes.get("Scare")

local MatchService = {}
MatchService.__index = MatchService

function MatchService.new(arena, monster, players, lobbyPosition: Vector3, onFinished)
	local self = setmetatable({}, MatchService)

	self.arena = arena
	self.monster = monster
	self.players = players
	self.lobbyPosition = lobbyPosition
	self.onFinished = onFinished

	self.phase = "prep"
	self.phaseEnds = os.clock() + MATCH.PrepTime
	self.startedAt = os.clock()
	self.fusesPlaced = 0
	self.generatorOn = false
	self.finished = false
	self.state = {}
	self.fuseParts = {}
	self.connections = {}
	self.noiseAccumulator = 0
	self.syncAccumulator = 0

	monster.onCatch = function(player)
		self:onCaught(player)
	end

	return self
end

function MatchService:notify(text: string, color: string?)
	for _, player in self.players do
		if player.Parent then
			notifyEvent:FireClient(player, text, color)
		end
	end
end

function MatchService:_playerState(player: Player)
	return self.state[player]
end

function MatchService:_spawnFuses()
	local spots = Util.shuffle(self.arena.FuseSpots)
	for index = 1, math.min(MATCH.FusesRequired, #spots) do
		local position = spots[index]

		local fuse = Util.makePart(
			self.arena.Model,
			"Fuse",
			Vector3.new(2, 3, 2),
			position,
			Color3.fromRGB(255, 190, 70),
			Enum.Material.Neon
		)
		fuse.CanCollide = false

		local light = Instance.new("PointLight")
		light.Color = fuse.Color
		light.Range = 14
		light.Brightness = 1.5
		light.Parent = fuse

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Забрать предохранитель"
		prompt.ObjectText = "Предохранитель"
		prompt.HoldDuration = MATCH.FuseHoldTime
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = fuse

		prompt.Triggered:Connect(function(player)
			if not fuse.Parent or not self.state[player] then
				return
			end
			fuse:Destroy()
			self:_onFuseTaken(player, position)
		end)

		table.insert(self.fuseParts, fuse)
	end
end

function MatchService:_onFuseTaken(player: Player, position: Vector3)
	self.fusesPlaced += 1

	-- вынул предохранитель - щиток взвыл, ОН услышал
	local playerState = self.state[player]
	if playerState then
		playerState.heat = math.min(NOISE.MaxHeat, playerState.heat + NOISE.Fuse)
	end

	if self.fusesPlaced >= MATCH.FusesRequired then
		self.generatorPrompt.Enabled = true
		self:notify("Все предохранители у вас. Запускайте генератор в центре!", "good")
	else
		self:notify(string.format("Предохранитель %d/%d. ОН это слышал.", self.fusesPlaced, MATCH.FusesRequired), "info")
	end
end

function MatchService:_setupGenerator()
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Запустить генератор"
	prompt.ObjectText = "Генератор"
	prompt.HoldDuration = 5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = self.arena.Generator
	self.generatorPrompt = prompt

	prompt.Triggered:Connect(function(player)
		if self.generatorOn or not self.state[player] then
			return
		end
		self.generatorOn = true
		prompt.Enabled = false

		local playerState = self.state[player]
		playerState.heat = NOISE.MaxHeat

		self.arena.Gate:SetAttribute("Locked", false)
		self.arena.Gate.CanCollide = false
		self.arena.Gate.Transparency = 0.7
		self.arena.Gate.Color = Color3.fromRGB(40, 180, 90)
		self.arena.GeneratorLight.Color = Color3.fromRGB(60, 255, 120)

		-- аварийный свет: видно чуть больше, но и вас видно
		for _, lamp in self.arena.Lights do
			lamp.Light.Enabled = true
			lamp.Light.Brightness = 0.35
			lamp.Light.Color = Color3.fromRGB(255, 80, 60)
			lamp.Part.Color = Color3.fromRGB(120, 30, 30)
		end

		self:notify("ГЕНЕРАТОР ЗАПУЩЕН. Ворота на юге открыты. БЕГИТЕ.", "good")
	end)
end

function MatchService:_setLights(enabled: boolean)
	for _, lamp in self.arena.Lights do
		lamp.Light.Enabled = enabled
		lamp.Part.Color = enabled and Color3.fromRGB(255, 240, 210) or Color3.fromRGB(40, 40, 40)
		lamp.Part.Material = enabled and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
end

function MatchService:_teleportToArena(player: Player, index: number)
	local root = Util.getRoot(player.Character)
	if not root then
		return
	end
	local spawns = self.arena.SpawnPositions
	local position = spawns[((index - 1) % #spawns) + 1]
	root.CFrame = CFrame.new(position)
end

function MatchService:_teleportToLobby(player: Player)
	local root = Util.getRoot(player.Character)
	if root then
		root.CFrame = CFrame.new(self.lobbyPosition + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8)))
	end
end

function MatchService:onCharacterAdded(player: Player, character)
	local playerState = self.state[player]
	if not playerState or self.finished then
		return
	end
	task.wait(0.2)
	if playerState.out or playerState.escaped then
		self:_teleportToLobby(player)
		return
	end
	-- умер от чего-то ещё - возвращаем в дом целым
	playerState.downed = false
	playerState.bleed = 0
	playerState.sanity = SANITY.Max * 0.5
	local index = table.find(self.players, player) or 1
	self:_teleportToArena(player, index)
end

-- ОН достал игрока: не убивает сразу, роняет. Напарник может поднять.
function MatchService:onCaught(player: Player)
	local playerState = self.state[player]
	if not playerState or playerState.downed or playerState.escaped or playerState.out then
		return
	end

	playerState.downed = true
	playerState.bleed = MATCH.BleedOutTime
	playerState.heat = 0

	local humanoid = Util.getHumanoid(player.Character)
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	scareEvent:FireClient(player, "down")
	self:notify(string.format("%s упал! Поднимите его, пока не поздно.", player.DisplayName), "bad")

	local root = Util.getRoot(player.Character)
	if root then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RevivePrompt"
		prompt.ActionText = "Поднять"
		prompt.ObjectText = player.DisplayName
		prompt.HoldDuration = MATCH.ReviveTime
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
		playerState.revivePrompt = prompt

		prompt.Triggered:Connect(function(reviver)
			local reviverState = self.state[reviver]
			if not reviverState or reviverState.downed or reviverState.out then
				return
			end
			self:_revive(player)
		end)
	end
end

function MatchService:_revive(player: Player)
	local playerState = self.state[player]
	if not playerState or not playerState.downed then
		return
	end
	playerState.downed = false
	playerState.bleed = 0
	playerState.sanity = math.max(playerState.sanity, 50)

	if playerState.revivePrompt then
		playerState.revivePrompt:Destroy()
		playerState.revivePrompt = nil
	end

	local humanoid = Util.getHumanoid(player.Character)
	if humanoid then
		humanoid.WalkSpeed = MOVEMENT.WalkSpeed
		humanoid.JumpPower = 45
	end

	scareEvent:FireClient(player, "revived")
	self:notify(string.format("%s снова на ногах.", player.DisplayName), "good")
end

function MatchService:_playerOut(player: Player, reason: string)
	local playerState = self.state[player]
	if not playerState or playerState.out then
		return
	end
	playerState.out = true
	playerState.downed = false

	if playerState.revivePrompt then
		playerState.revivePrompt:Destroy()
		playerState.revivePrompt = nil
	end

	local humanoid = Util.getHumanoid(player.Character)
	if humanoid then
		humanoid.WalkSpeed = MOVEMENT.WalkSpeed
		humanoid.JumpPower = 45
	end

	self:_teleportToLobby(player)
	scareEvent:FireClient(player, "out")
	self:notify(string.format("%s: %s", player.DisplayName, reason), "bad")
end

function MatchService:_escape(player: Player)
	local playerState = self.state[player]
	if not playerState or playerState.escaped or playerState.downed or playerState.out then
		return
	end
	if self.arena.Gate:GetAttribute("Locked") then
		notifyEvent:FireClient(player, "Ворота заперты - нужен генератор", "bad")
		return
	end

	playerState.escaped = true
	self:_teleportToLobby(player)
	self:notify(string.format("%s выбрался!", player.DisplayName), "good")

	local stats = player:FindFirstChild("leaderstats")
	local escapes = stats and stats:FindFirstChild("Побеги")
	if escapes then
		escapes.Value += 1
	end
end

function MatchService:_loudnessOf(player: Player): number
	local playerState = self.state[player]
	if not playerState or playerState.downed or playerState.escaped or playerState.out then
		return 0
	end

	local humanoid = Util.getHumanoid(player.Character)
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	local loud = 0
	if humanoid.MoveDirection.Magnitude > 0.1 then
		if playerState.crouching then
			loud += NOISE.Crouch
		elseif humanoid.WalkSpeed >= MOVEMENT.SprintSpeed - 2 then
			loud += NOISE.Sprint
		else
			loud += NOISE.Walk
		end
	end
	if playerState.flashlight then
		loud += NOISE.Flashlight
	end
	return loud
end

function MatchService:_updateSanity(dt: number)
	local now = os.clock()
	local monsterRoot = self.monster.rig.Root

	local gazing = {}
	for _, player in self.monster.gazers do
		gazing[player] = true
	end

	for _, player in self.players do
		local playerState = self.state[player]
		if not playerState or playerState.out or playerState.escaped then
			continue
		end

		local root = Util.getRoot(player.Character)
		local distance = root and (root.Position - monsterRoot.Position).Magnitude or 999
		playerState.gazing = gazing[player] == true
		playerState.monsterDistance = distance

		if self.phase ~= "hunt" then
			continue
		end

		if gazing[player] then
			playerState.sanity -= SANITY.GazeDrain * dt
			playerState.lastDrain = now
		elseif distance < SANITY.NearDistance then
			playerState.sanity -= SANITY.NearDrain * dt
			playerState.lastDrain = now
		elseif now - (playerState.lastDrain or 0) > SANITY.RegenDelay then
			playerState.sanity = math.min(SANITY.Max, playerState.sanity + SANITY.Regen * dt)
		end

		if playerState.sanity <= 0 then
			playerState.sanity = SANITY.PanicRefill
			playerState.panicUntil = now + SANITY.PanicLockTime
			playerState.heat = math.min(NOISE.MaxHeat, playerState.heat + NOISE.Scream)
			scareEvent:FireClient(player, "panic")
			self:notify(string.format("%s сорвался на крик!", player.DisplayName), "bad")
		end
	end
end

function MatchService:_checkEnd()
	local anyActive = false
	local anyEscaped = false
	for _, player in self.players do
		local playerState = self.state[player]
		if playerState then
			if playerState.escaped then
				anyEscaped = true
			elseif not playerState.out and player.Parent then
				anyActive = true
			end
		end
	end

	if not anyActive then
		self:finish(anyEscaped and "win" or "lose")
	elseif os.clock() - self.startedAt > MATCH.MaxMatchTime then
		self:finish("timeout")
	end
end

function MatchService:_sync()
	local teammates = {}
	for _, player in self.players do
		local playerState = self.state[player]
		if playerState then
			table.insert(teammates, {
				name = player.DisplayName,
				downed = playerState.downed,
				escaped = playerState.escaped,
				out = playerState.out,
			})
		end
	end

	local timeLeft = math.max(0, self.phaseEnds - os.clock())

	for _, player in self.players do
		local playerState = self.state[player]
		if not playerState or not player.Parent then
			continue
		end
		syncEvent:FireClient(player, {
			inMatch = true,
			phase = self.phase,
			timeLeft = timeLeft,
			fuses = self.fusesPlaced,
			fusesRequired = MATCH.FusesRequired,
			generatorOn = self.generatorOn,
			gateOpen = not self.arena.Gate:GetAttribute("Locked"),
			sanity = playerState.sanity,
			sanityMax = SANITY.Max,
			heat = playerState.heat,
			heatMax = NOISE.MaxHeat,
			downed = playerState.downed,
			bleed = playerState.bleed,
			bleedMax = MATCH.BleedOutTime,
			escaped = playerState.escaped,
			out = playerState.out,
			gazing = playerState.gazing,
			hunted = self.monster.targetPlayer == player,
			distance = playerState.monsterDistance or 999,
			panic = playerState.panicUntil and os.clock() < playerState.panicUntil,
			teammates = teammates,
		})
	end
end

function MatchService:_step(dt: number)
	if self.finished then
		return
	end

	-- фазы
	if self.phase == "prep" and os.clock() >= self.phaseEnds then
		self.phase = "hunt"
		self.phaseEnds = os.clock() + MATCH.MaxMatchTime
		self:_setLights(false)
		self.monster:arrive()
		self:notify("СВЕТ ПОГАС. ОН ПРИШЁЛ.", "bad")
		for _, player in self.players do
			scareEvent:FireClient(player, "arrival")
		end
	end

	-- шум
	self.noiseAccumulator += dt
	if self.noiseAccumulator >= NOISE.TickInterval then
		self.noiseAccumulator = 0
		for _, player in self.players do
			local playerState = self.state[player]
			if playerState then
				playerState.heat = math.min(NOISE.MaxHeat, playerState.heat + self:_loudnessOf(player))
			end
		end
	end

	local heat = {}
	for _, player in self.players do
		local playerState = self.state[player]
		if playerState and not playerState.out and not playerState.escaped and not playerState.downed then
			playerState.heat = math.max(0, playerState.heat - NOISE.Decay * dt)
			heat[player] = playerState.heat
		end
	end

	-- истекающий кровью
	for _, player in self.players do
		local playerState = self.state[player]
		if playerState and playerState.downed then
			playerState.bleed -= dt
			if playerState.bleed <= 0 then
				self:_playerOut(player, "не дождался помощи")
			end
		end
	end

	self:_updateSanity(dt)

	if self.phase == "hunt" then
		self.monster:step(dt, self.players, heat)
	end

	self.syncAccumulator += dt
	if self.syncAccumulator >= 0.25 then
		self.syncAccumulator = 0
		self:_sync()
	end

	self:_checkEnd()
end

function MatchService:start()
	for index, player in self.players do
		self.state[player] = {
			sanity = SANITY.Max,
			heat = 0,
			downed = false,
			bleed = 0,
			escaped = false,
			out = false,
			crouching = false,
			flashlight = false,
			panicUntil = 0,
			lastDrain = 0,
		}
		self:_teleportToArena(player, index)
	end

	self:_setLights(true)
	self:_spawnFuses()
	self:_setupGenerator()

	table.insert(self.connections, self.arena.ExitPad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and self.state[player] then
			self:_escape(player)
		end
	end))

	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(function()
			self:_step(dt)
		end)
		if not ok then
			warn("[HE WILL COME] ошибка матча: " .. tostring(err))
		end
	end))

	self:notify(string.format("У вас %d секунд тишины. Потом ОН придёт.", MATCH.PrepTime), "info")
end

function MatchService:setCrouch(player: Player, value: boolean)
	local playerState = self.state[player]
	if playerState then
		playerState.crouching = value == true
	end
end

function MatchService:setFlashlight(player: Player, value: boolean)
	local playerState = self.state[player]
	if playerState then
		playerState.flashlight = value == true
	end
end

function MatchService:playerLeft(player: Player)
	local playerState = self.state[player]
	if not playerState then
		return
	end
	if playerState.revivePrompt then
		playerState.revivePrompt:Destroy()
	end
	playerState.out = true
	self.state[player] = nil
	local index = table.find(self.players, player)
	if index then
		table.remove(self.players, index)
	end
end

function MatchService:finish(result: string)
	if self.finished then
		return
	end
	self.finished = true

	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)

	local text = "ОН забрал всех."
	if result == "win" then
		text = "Вы выбрались. На этот раз."
	elseif result == "timeout" then
		text = "Время вышло."
	end

	for _, player in self.players do
		local playerState = self.state[player]
		if playerState and playerState.revivePrompt then
			playerState.revivePrompt:Destroy()
		end
		if player.Parent then
			notifyEvent:FireClient(player, text, result == "win" and "good" or "bad")
			syncEvent:FireClient(player, { inMatch = false })
			self:_teleportToLobby(player)
		end
	end

	if self.onFinished then
		self.onFinished(result)
	end
end

return MatchService
