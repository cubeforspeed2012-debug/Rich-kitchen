--!nonstrict
-- Приманки: маленький "триггер", который шумит и уводит монстра.
-- Когда монстр подходит вплотную - он тупит несколько секунд.
-- В ЯРОСТИ приманки на него не действуют (см. MonsterAI.lureTo).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("LocustShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Util = require(Shared:WaitForChild("Util"))

local BAIT = GameConfig.Bait
local NOISE = GameConfig.Noise

local BaitService = {}
BaitService.__index = BaitService

function BaitService.new(monster, collisionGroup: string?)
	local self = setmetatable({}, BaitService)
	self.monster = monster
	self.collisionGroup = collisionGroup
	self.players = {} :: { [Player]: { charges: number, nextRecharge: number, cooldown: number } }
	self.active = {} :: { any }
	return self
end

function BaitService:register(player: Player)
	self.players[player] = { charges = BAIT.MaxCharges, nextRecharge = 0, cooldown = 0 }
end

function BaitService:unregister(player: Player)
	self.players[player] = nil
end

function BaitService:getCharges(player: Player): number
	local state = self.players[player]
	return state and state.charges or 0
end

function BaitService:refill(player: Player)
	local state = self.players[player]
	if state then
		state.charges = BAIT.MaxCharges
	end
end

function BaitService:throw(player: Player, direction: Vector3): (boolean, string)
	local state = self.players[player]
	if not state then
		return false, "Не в игре"
	end
	local now = os.clock()
	if now < state.cooldown then
		return false, "Перезарядка"
	end
	if state.charges <= 0 then
		return false, "Приманки кончились"
	end

	local root = Util.getRoot(player.Character)
	if not root or not Util.isAlive(player) then
		return false, "Нельзя сейчас"
	end

	state.charges -= 1
	state.cooldown = now + BAIT.Cooldown
	if state.nextRecharge <= now then
		state.nextRecharge = now + BAIT.RechargeTime
	end

	local dir = direction.Magnitude > 0 and direction.Unit or root.CFrame.LookVector

	local bait = Instance.new("Part")
	bait.Name = "Bait"
	bait.Shape = Enum.PartType.Ball
	bait.Size = Vector3.new(1.4, 1.4, 1.4)
	bait.Color = Color3.fromRGB(255, 200, 60)
	bait.Material = Enum.Material.Neon
	bait.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.3, 0.6)
	bait.CFrame = CFrame.new(root.Position + dir * 3 + Vector3.new(0, 2, 0))
	bait.AssemblyLinearVelocity = (dir + Vector3.new(0, 0.35, 0)).Unit * BAIT.ThrowSpeed
	if self.collisionGroup then
		bait.CollisionGroup = self.collisionGroup
	end

	local light = Instance.new("PointLight")
	light.Color = bait.Color
	light.Range = 12
	light.Brightness = 2
	light.Parent = bait

	bait.Parent = Workspace
	Debris:AddItem(bait, BAIT.LifeTime)

	table.insert(self.active, {
		part = bait,
		owner = player,
		diesAt = now + BAIT.LifeTime,
		nextPulse = now + 0.35,
		triggered = false,
	})

	return true, "Приманка брошена"
end

function BaitService:start()
	self._connection = RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()

		-- перезарядка приманок
		for _, state in self.players do
			if state.charges < BAIT.MaxCharges and now >= state.nextRecharge then
				state.charges += 1
				state.nextRecharge = now + BAIT.RechargeTime
			end
		end

		-- работа брошенных приманок
		for index = #self.active, 1, -1 do
			local bait = self.active[index]
			if not bait.part.Parent or now > bait.diesAt then
				bait.part:Destroy()
				table.remove(self.active, index)
				continue
			end

			if now >= bait.nextPulse then
				bait.nextPulse = now + NOISE.BaitInterval
				bait.part.Size = Vector3.new(1.8, 1.8, 1.8)
				task.delay(0.12, function()
					if bait.part.Parent then
						bait.part.Size = Vector3.new(1.4, 1.4, 1.4)
					end
				end)
				self.monster:hear(bait.part.Position, NOISE.BaitRadius)
				self.monster:lureTo(bait.part.Position)
			end

			local distance = (self.monster.rig.Root.Position - bait.part.Position).Magnitude
			if not bait.triggered and distance < 7 then
				bait.triggered = true
				self.monster:confuse(BAIT.ConfuseTime)
				bait.part:Destroy()
				table.remove(self.active, index)
			end
		end
	end)
end

function BaitService:clear()
	for _, bait in self.active do
		if bait.part then
			bait.part:Destroy()
		end
	end
	table.clear(self.active)
end

return BaitService
