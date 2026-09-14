--!nonstrict
-- ФИРМЕННАЯ МЕХАНИКА: "Дерзость".
-- Кнопкой подколки ты специально палишься перед монстром. За это:
--   + монстр звереет (быстрее, видит дальше, приманки на него не действуют)
--   + твой множитель очков растёт за каждую подколку подряд
-- Поймал - серия и весь накопленный банк сгорают.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("LocustShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Util = require(Shared:WaitForChild("Util"))

local RAGE = GameConfig.Rage
local ROUND = GameConfig.Round

local TAUNT_LINES = {
	"Эй, жирная саранча!",
	"Тут я! Догоняй!",
	"Медленный какой-то...",
	"Ну и кто тут страшный?",
	"Оп, промазал!",
}

local RageService = {}
RageService.__index = RageService

function RageService.new(monster)
	local self = setmetatable({}, RageService)
	self.monster = monster
	self.rage = 0
	self.lastTauntAt = 0
	self.players = {} :: { [Player]: { streak: number, bank: number, lastTaunt: number, cooldown: number } }
	self.onTaunt = nil :: ((Player, string, number) -> ())?
	return self
end

function RageService:register(player: Player)
	self.players[player] = { streak = 0, bank = 0, lastTaunt = 0, cooldown = 0 }
end

function RageService:unregister(player: Player)
	self.players[player] = nil
end

function RageService:getState(player: Player)
	return self.players[player] or { streak = 0, bank = 0, lastTaunt = 0, cooldown = 0 }
end

function RageService:getMultiplier(player: Player): number
	local state = self:getState(player)
	return math.min(1 + state.streak * RAGE.MultiplierStep, RAGE.MaxMultiplier)
end

-- Забрать накопленный банк дерзости (при побеге).
function RageService:cashOut(player: Player): number
	local state = self.players[player]
	if not state then
		return 0
	end
	local bank = state.bank
	state.bank = 0
	state.streak = 0
	return bank
end

-- Поймали: всё сгорает.
function RageService:wipe(player: Player)
	local state = self.players[player]
	if not state then
		return
	end
	state.bank = 0
	state.streak = 0
end

function RageService:taunt(player: Player): (boolean, string)
	local state = self.players[player]
	if not state then
		return false, "Не в игре"
	end

	local now = os.clock()
	if now < state.cooldown then
		return false, "Ещё рано"
	end

	local root = Util.getRoot(player.Character)
	if not root or not Util.isAlive(player) then
		return false, "Нельзя сейчас"
	end

	local monsterRoot = self.monster.rig.Root
	local distance = (monsterRoot.Position - root.Position).Magnitude
	if distance > RAGE.TauntRadius then
		return false, "Слишком далеко - он тебя не слышит"
	end

	-- Дразнить можно либо в открытую, либо когда он совсем рядом за стеной.
	local visible = Util.hasLineOfSight(root.Position + Vector3.new(0, 2, 0), monsterRoot.Position, { player.Character :: any })
	if not visible and distance > 15 then
		return false, "Он тебя не видит - подойди ближе"
	end

	state.cooldown = now + RAGE.TauntCooldown

	-- серия сгорает, если долго не дразнил
	if now - state.lastTaunt > RAGE.StreakTimeout then
		state.streak = 0
	end
	state.lastTaunt = now
	state.streak += 1

	self.rage = math.min(100, self.rage + RAGE.TauntRageGain)
	self.lastTauntAt = now
	self.monster:setRage(self.rage)
	self.monster:provoke(player)
	self.monster:hear(root.Position, RAGE.TauntNoise)

	local multiplier = self:getMultiplier(player)
	local reward = math.floor(ROUND.TauntScore * multiplier)
	state.bank += reward

	local line = TAUNT_LINES[math.random(1, #TAUNT_LINES)]
	if self.onTaunt then
		self.onTaunt(player, line, multiplier)
	end

	return true, line
end

function RageService:start()
	self._connection = RunService.Heartbeat:Connect(function(dt)
		if self.rage <= 0 then
			return
		end
		if os.clock() - self.lastTauntAt < RAGE.DecayDelay then
			return
		end
		self.rage = math.max(0, self.rage - RAGE.DecayRate * dt)
		self.monster:setRage(self.rage)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:unregister(player)
	end)
end

function RageService:reset()
	self.rage = 0
	self.monster:setRage(0)
	for _, state in self.players do
		state.streak = 0
		state.bank = 0
	end
end

return RageService
