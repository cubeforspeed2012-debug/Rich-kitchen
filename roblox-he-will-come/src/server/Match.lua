--!nonstrict
-- Матч одной комнаты: 20 секунд тишины -> ОН просыпается -> обыскать парты,
-- найти 5 ключей -> открыть ворота -> убежать. Шкафчики, крик, падение и подъём.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))

local MATCH = GameConfig.Match
local NOISE = GameConfig.Noise
local MOVE = GameConfig.Movement
local MON = GameConfig.Monster

local syncEvent = Remotes.get("MatchSync")
local notifyEvent = Remotes.get("Notify")
local effectEvent = Remotes.get("Effect")

local Match = {}
Match.__index = Match

function Match.new(arena, monster, players, lobbyPosition, onFinished)
	local self = setmetatable({}, Match)
	self.arena = arena
	self.monster = monster
	self.players = players
	self.lobbyPosition = lobbyPosition
	self.onFinished = onFinished

	self.phase = "prep"
	self.phaseEnds = os.clock() + MATCH.PrepTime
	self.startedAt = os.clock()
	self.keysFound = 0
	self.finished = false
	self.state = {}
	self.connections = {}
	self.sprintAccumulator = 0
	self.syncAccumulator = 0
	self.flickerAccumulator = 0

	monster.onCatch = function(player)
		self:onCaught(player)
	end
	monster.onScream = function(player)
		self:_onMonsterScream(player)
	end
	monster.isPlayerHidden = function(player)
		local s = self.state[player]
		return s ~= nil and s.locker ~= nil
	end
	monster.isPlayerTargetable = function(player)
		local s = self.state[player]
		return s ~= nil and not s.downed and not s.escaped and not s.out
	end
	monster.hasFlashlight = function(player)
		local s = self.state[player]
		return s ~= nil and s.flashlight
	end
	monster.getLockerOf = function(player)
		local s = self.state[player]
		return s and s.locker or nil
	end

	return self
end

-- ---------------- сообщения ----------------

function Match:notify(text, color)
	for _, player in self.players do
		if player.Parent then
			notifyEvent:FireClient(player, text, color)
		end
	end
end

function Match:effect(kind, data)
	for _, player in self.players do
		if player.Parent then
			effectEvent:FireClient(player, kind, data)
		end
	end
end

-- ---------------- телепорты ----------------

function Match:_teleportToArena(player, index)
	local root = Util.getRoot(player.Character)
	if not root then
		return
	end
	local spawns = self.arena.SpawnPositions
	root.Anchored = false
	root.CFrame = CFrame.new(spawns[((index - 1) % #spawns) + 1])
end

function Match:_teleportToLobby(player)
	local root = Util.getRoot(player.Character)
	if root then
		root.Anchored = false
		root.CFrame = CFrame.new(self.lobbyPosition + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8)))
	end
end

function Match:onCharacterAdded(player, character)
	local s = self.state[player]
	if not s or self.finished then
		return
	end
	task.wait(0.3)
	self:_leaveLocker(player)
	s.downed = false
	player:SetAttribute("Downed", false)
	player:SetAttribute("Hidden", false)
	if s.out or s.escaped then
		self:_teleportToLobby(player)
	else
		self:_teleportToArena(player, table.find(self.players, player) or 1)
	end
end

-- ---------------- свет ----------------

function Match:_setLights(brightness)
	for _, lamp in self.arena.Lights do
		lamp.Light.Brightness = brightness
		lamp.Part.Color = brightness > 0.6 and Color3.fromRGB(255, 240, 210) or Color3.fromRGB(120, 100, 80)
	end
end

-- лампы рядом с монстром мигают: слышишь не только шаги, но и видишь
function Match:_flicker()
	local monsterPosition = self.monster.rig.Root.Position
	for _, lamp in self.arena.Lights do
		local distance = (lamp.Position - monsterPosition).Magnitude
		if distance < 26 then
			local on = math.random() > 0.35
			lamp.Light.Brightness = on and MATCH.DimLights or 0
			lamp.Part.Color = on and Color3.fromRGB(120, 100, 80) or Color3.fromRGB(40, 36, 34)
		elseif lamp.Light.Brightness ~= MATCH.DimLights then
			lamp.Light.Brightness = MATCH.DimLights
			lamp.Part.Color = Color3.fromRGB(120, 100, 80)
		end
	end
end

-- ---------------- ключи и парты ----------------

function Match:_setupSearchables()
	local shuffled = Util.shuffle(self.arena.Searchables)
	for index = 1, math.min(MATCH.KeysRequired, #shuffled) do
		shuffled[index].HasKey = true
	end

	for _, item in self.arena.Searchables do
		table.insert(self.connections, item.Prompt.Triggered:Connect(function(player)
			self:_onSearch(player, item)
		end))
	end
end

function Match:_onSearch(player, item)
	local s = self.state[player]
	if not s or s.downed or s.out or s.escaped or s.locker then
		return
	end
	if item.Searched then
		notifyEvent:FireClient(player, "Тут уже смотрели. Пусто.", "info")
		return
	end

	item.Searched = true
	item.Prompt.ActionText = "Пусто"
	item.Prompt.Enabled = false
	item.Bag.Color = Color3.fromRGB(70, 70, 74)

	-- шаришь по рюкзаку - шумно
	self.monster:hear(item.Position, NOISE.Search)

	if item.HasKey then
		self.keysFound += 1
		self:_onKeyFound(player)
	else
		notifyEvent:FireClient(player, "Пусто. Ищи дальше.", "info")
	end
end

function Match:_onKeyFound(player)
	local stats = player:FindFirstChild("leaderstats")
	local keys = stats and stats:FindFirstChild("Ключи")
	if keys then
		keys.Value += 1
	end

	-- с каждым ключом он злее и быстрее
	self.monster:addSpeed(MON.SpeedPerKey)
	effectEvent:FireClient(player, "key")

	if self.keysFound >= MATCH.KeysRequired then
		self.arena.Gate:SetAttribute("Locked", false)
		self.arena.Gate.CanCollide = false
		self.arena.Gate.Transparency = 0.6
		self.arena.Gate.Color = Color3.fromRGB(40, 180, 90)
		self:notify("ВСЕ КЛЮЧИ НАЙДЕНЫ. Ворота во дворе открыты - через главный вход и на юг!", "good")
	else
		self:notify(string.format("%s нашёл ключ! %d/%d. ОН стал быстрее.", player.DisplayName, self.keysFound, MATCH.KeysRequired), "good")
	end
end

-- ---------------- шкафчики ----------------

function Match:_setupLockers()
	for _, locker in self.arena.Lockers do
		table.insert(self.connections, locker.Prompt.Triggered:Connect(function(player)
			self:_onLocker(player, locker)
		end))
	end
end

function Match:_onLocker(player, locker)
	local s = self.state[player]
	if not s or s.downed or s.out or s.escaped then
		return
	end
	local root = Util.getRoot(player.Character)
	if not root then
		return
	end

	if s.locker == locker then
		-- выходим
		s.locker = nil
		locker.Occupant = nil
		locker.Prompt.ActionText = "Спрятаться"
		player:SetAttribute("Hidden", false)
		root.Anchored = false
		root.CFrame = CFrame.new(locker.Outside)
		self.monster:hear(locker.Outside, NOISE.Locker)
		return
	end

	if s.locker or locker.Occupant then
		notifyEvent:FireClient(player, "Занято", "bad")
		return
	end

	s.locker = locker
	locker.Occupant = player
	locker.Prompt.ActionText = "Выйти"
	player:SetAttribute("Hidden", true)
	root.CFrame = CFrame.new(locker.Inside, locker.Inside + (locker.Outside - locker.Inside))
	root.Anchored = true
	self.monster:hear(locker.Outside, NOISE.Locker)
	notifyEvent:FireClient(player, "Ты спрятался. Не выходи, пока не стихнут шаги.", "info")
end

function Match:_leaveLocker(player)
	local s = self.state[player]
	if not s or not s.locker then
		return
	end
	local locker = s.locker
	s.locker = nil
	locker.Occupant = nil
	locker.Prompt.ActionText = "Спрятаться"
	player:SetAttribute("Hidden", false)
	local root = Util.getRoot(player.Character)
	if root then
		root.Anchored = false
		root.CFrame = CFrame.new(locker.Outside)
	end
end

-- ---------------- монстр орёт ----------------

function Match:_onMonsterScream(player)
	self:effect("scream", { position = self.monster.rig.Root.Position })
	self:notify(string.format("ОН УВИДЕЛ %s!", string.upper(player.DisplayName)), "bad")
end

-- ---------------- падение / подъём / выбывание ----------------

function Match:onCaught(player)
	local s = self.state[player]
	if not s or s.downed or s.escaped or s.out then
		return
	end

	self:_leaveLocker(player)
	s.downed = true
	s.bleed = MATCH.BleedOutTime
	player:SetAttribute("Downed", true)

	local humanoid = Util.getHumanoid(player.Character)
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	effectEvent:FireClient(player, "down")
	self:notify(string.format("%s упал! Поднимите его (E), пока не поздно.", player.DisplayName), "bad")

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
		s.revivePrompt = prompt
		prompt.Triggered:Connect(function(reviver)
			local r = self.state[reviver]
			if reviver ~= player and r and not r.downed and not r.out and not r.escaped then
				self:_revive(player)
			end
		end)
	end

	-- один в комнате - поднимать некому
	local others = 0
	for _, other in self.players do
		local o = self.state[other]
		if other ~= player and o and not o.downed and not o.out and not o.escaped then
			others += 1
		end
	end
	if others == 0 then
		task.delay(2.5, function()
			if s.downed then
				self:_playerOut(player, "никто не пришёл на помощь")
			end
		end)
	end
end

function Match:_revive(player)
	local s = self.state[player]
	if not s or not s.downed then
		return
	end
	s.downed = false
	s.bleed = 0
	player:SetAttribute("Downed", false)
	if s.revivePrompt then
		s.revivePrompt:Destroy()
		s.revivePrompt = nil
	end
	local humanoid = Util.getHumanoid(player.Character)
	if humanoid then
		humanoid.WalkSpeed = MOVE.WalkSpeed
		humanoid.JumpPower = 45
	end
	effectEvent:FireClient(player, "revived")
	self:notify(string.format("%s снова на ногах.", player.DisplayName), "good")
end

function Match:_playerOut(player, reason)
	local s = self.state[player]
	if not s or s.out then
		return
	end
	self:_leaveLocker(player)
	s.out = true
	s.downed = false
	player:SetAttribute("Downed", false)
	if s.revivePrompt then
		s.revivePrompt:Destroy()
		s.revivePrompt = nil
	end
	local humanoid = Util.getHumanoid(player.Character)
	if humanoid then
		humanoid.WalkSpeed = MOVE.WalkSpeed
		humanoid.JumpPower = 45
	end
	self:_teleportToLobby(player)
	effectEvent:FireClient(player, "out")
	self:notify(string.format("%s: %s", player.DisplayName, reason), "bad")
	s.syncStopped = true
	syncEvent:FireClient(player, { inMatch = false })
end

function Match:_escape(player)
	local s = self.state[player]
	if not s or s.escaped or s.downed or s.out then
		return
	end
	if self.arena.Gate:GetAttribute("Locked") then
		notifyEvent:FireClient(player, "Ворота заперты. Нужны все ключи.", "bad")
		return
	end
	s.escaped = true
	self:_teleportToLobby(player)
	effectEvent:FireClient(player, "escaped")
	self:notify(string.format("%s выбрался!", player.DisplayName), "good")
	s.syncStopped = true
	syncEvent:FireClient(player, { inMatch = false })

	local stats = player:FindFirstChild("leaderstats")
	local escapes = stats and stats:FindFirstChild("Побеги")
	if escapes then
		escapes.Value += 1
	end
end

-- ---------------- действия игрока ----------------

function Match:playerAction(player, action, value)
	local s = self.state[player]
	if not s or s.out or s.escaped then
		return
	end
	local root = Util.getRoot(player.Character)

	if action == "crouch" then
		s.crouching = value == true
		player:SetAttribute("Crouching", s.crouching)
	elseif action == "flashlight" then
		s.flashlight = value == true
		player:SetAttribute("Flashlight", s.flashlight)
	elseif action == "slide" then
		if root and not s.downed and not s.locker then
			self.monster:hear(root.Position, NOISE.Slide)
		end
	elseif action == "shout" then
		if s.downed or s.locker then
			return
		end
		if os.clock() - (s.lastShout or -100) < NOISE.ShoutCooldown then
			return
		end
		s.lastShout = os.clock()
		if root then
			self.monster:hear(root.Position, NOISE.Shout, true)
			self:effect("shout", { name = player.DisplayName })
			self:notify(string.format("%s кричит - ОН идёт к нему!", player.DisplayName), "info")
		end
	end
end

-- ---------------- цикл ----------------

function Match:_sprintNoise()
	for _, player in self.players do
		local s = self.state[player]
		if not s or s.downed or s.out or s.escaped or s.locker then
			continue
		end
		local humanoid = Util.getHumanoid(player.Character)
		local root = Util.getRoot(player.Character)
		if not humanoid or not root or humanoid.Health <= 0 then
			continue
		end
		if humanoid.MoveDirection.Magnitude < 0.1 then
			continue
		end
		local radius
		if s.crouching then
			radius = NOISE.Crouch
		elseif humanoid.WalkSpeed >= MOVE.SprintSpeed - 2 then
			radius = NOISE.Sprint
		else
			radius = NOISE.Walk
		end
		if radius > 0 then
			self.monster:hear(root.Position, radius)
		end
	end
end

function Match:_checkEnd()
	local anyActive, anyEscaped = false, false
	for _, player in self.players do
		local s = self.state[player]
		if s then
			if s.escaped then
				anyEscaped = true
			elseif not s.out and player.Parent then
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

function Match:_sync()
	local teammates = {}
	for _, player in self.players do
		local s = self.state[player]
		if s then
			table.insert(teammates, { name = player.DisplayName, downed = s.downed, escaped = s.escaped, out = s.out, hidden = s.locker ~= nil })
		end
	end

	local monsterPosition = self.monster.rig.Root.Position
	for _, player in self.players do
		local s = self.state[player]
		if not s or not player.Parent or s.syncStopped then
			continue
		end
		local root = Util.getRoot(player.Character)
		local distance = root and (root.Position - monsterPosition).Magnitude or 999
		syncEvent:FireClient(player, {
			inMatch = true,
			phase = self.phase,
			timeLeft = math.max(0, self.phaseEnds - os.clock()),
			keys = self.keysFound,
			keysRequired = MATCH.KeysRequired,
			gateOpen = not self.arena.Gate:GetAttribute("Locked"),
			downed = s.downed,
			bleed = s.bleed,
			bleedMax = MATCH.BleedOutTime,
			hidden = s.locker ~= nil,
			escaped = s.escaped,
			out = s.out,
			hunted = self.monster.target == player,
			monsterState = self.monster.state,
			distance = distance,
			teammates = teammates,
		})
	end
end

function Match:_step(dt)
	if self.finished then
		return
	end

	if self.phase == "prep" and os.clock() >= self.phaseEnds then
		self.phase = "hunt"
		self.phaseEnds = os.clock() + MATCH.MaxMatchTime
		self:_setLights(MATCH.DimLights)
		self.monster:wake()
		self:effect("arrival")
		self:notify("СВЕТ МИГНУЛ. ОН ПРОСНУЛСЯ.", "bad")
	end

	if self.phase == "hunt" then
		self.sprintAccumulator += dt
		if self.sprintAccumulator >= NOISE.SprintInterval then
			self.sprintAccumulator = 0
			self:_sprintNoise()
		end

		self.monster:step(self.players)

		self.flickerAccumulator += dt
		if self.flickerAccumulator >= 0.12 then
			self.flickerAccumulator = 0
			self:_flicker()
		end
	end

	for _, player in self.players do
		local s = self.state[player]
		if s and s.downed then
			s.bleed -= dt
			if s.bleed <= 0 then
				self:_playerOut(player, "не дождался помощи")
			end
		end
	end

	self.syncAccumulator += dt
	if self.syncAccumulator >= 0.25 then
		self.syncAccumulator = 0
		self:_sync()
	end

	self:_checkEnd()
end

function Match:start()
	for index, player in self.players do
		self.state[player] = {
			downed = false,
			bleed = 0,
			escaped = false,
			out = false,
			locker = nil,
			crouching = false,
			flashlight = false,
			lastShout = -100,
		}
		player:SetAttribute("InMatch", true)
		player:SetAttribute("Downed", false)
		player:SetAttribute("Hidden", false)
		self:_teleportToArena(player, index)
	end

	self:_setLights(1.1)
	self:_setupSearchables()
	self:_setupLockers()

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

	self:notify(string.format("%d секунд тишины. Ищите ключи в рюкзаках на партах. Их %d.", MATCH.PrepTime, MATCH.KeysRequired), "info")
end

function Match:playerLeft(player)
	local s = self.state[player]
	if not s then
		return
	end
	self:_leaveLocker(player)
	if s.revivePrompt then
		s.revivePrompt:Destroy()
	end
	self.state[player] = nil
	player:SetAttribute("InMatch", false)
	player:SetAttribute("Downed", false)
	player:SetAttribute("Hidden", false)
	if player.Parent then
		syncEvent:FireClient(player, { inMatch = false })
	end
	local index = table.find(self.players, player)
	if index then
		table.remove(self.players, index)
	end
end

function Match:finish(result)
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
		text = "Время вышло. Школа не отпустила."
	end

	for _, player in self.players do
		local s = self.state[player]
		if s then
			self:_leaveLocker(player)
			if s.revivePrompt then
				s.revivePrompt:Destroy()
			end
		end
		if player.Parent then
			player:SetAttribute("InMatch", false)
			player:SetAttribute("Downed", false)
			player:SetAttribute("Hidden", false)
			local humanoid = Util.getHumanoid(player.Character)
			if humanoid then
				humanoid.WalkSpeed = MOVE.WalkSpeed
				humanoid.JumpPower = 45
			end
			notifyEvent:FireClient(player, text, result == "win" and "good" or "bad")
			syncEvent:FireClient(player, { inMatch = false, result = result })
			self:_teleportToLobby(player)
		end
	end

	if self.onFinished then
		self.onFinished(result)
	end
end

return Match
