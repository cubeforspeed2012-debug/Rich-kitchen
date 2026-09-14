--!nonstrict
-- Мозги монстра: патруль -> шум -> погоня -> поиск.
-- Плюс реакции на приманку (тупит) и на подколку (звереет).

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("LocustShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Util = require(Shared:WaitForChild("Util"))

local MonsterModel = require(script.Parent:WaitForChild("MonsterModel"))

local M = GameConfig.Monster
local RAGE = GameConfig.Rage

local MonsterAI = {}
MonsterAI.__index = MonsterAI

export type MonsterAI = typeof(setmetatable({} :: any, MonsterAI))

function MonsterAI.new(map, collisionGroup: string?)
	local self = setmetatable({}, MonsterAI)

	self.map = map
	self.rig = MonsterModel.build(map.MonsterSpawn, collisionGroup)
	self.rig.Model.Parent = Workspace

	self.state = "Patrol"
	self.target = nil :: Player?
	self.lastKnown = nil :: Vector3?
	self.investigatePoint = nil :: Vector3?
	self.stateEnteredAt = os.clock()
	self.lastSeenAt = 0
	self.stunUntil = 0
	self.nodeIndex = 1
	self.rage = 0

	self._waypoints = {} :: { PathWaypoint }
	self._waypointIndex = 1
	self._pathGoal = Vector3.zero
	self._lastPath = 0

	self._path = PathfindingService:CreatePath({
		AgentRadius = 3,
		AgentHeight = 6,
		AgentCanJump = false,
		Costs = {
			-- Лаз для монстра непроходим: он всегда идёт в обход через двери.
			Vent = math.huge,
		},
	})

	self.onCatch = nil :: ((Player) -> ())?
	self.onStateChanged = nil :: ((string) -> ())?

	return self
end

function MonsterAI:setRage(value: number)
	self.rage = value
	local fury = value >= RAGE.FuryThreshold
	local intensity = value / 100
	self.rig.Light.Brightness = 1.2 + intensity * 4
	self.rig.Light.Range = 16 + intensity * 22
	for _, eye in self.rig.Eyes do
		eye.Color = fury and Color3.fromRGB(255, 210, 60) or Color3.fromRGB(255, 60, 40)
	end
end

function MonsterAI:_speed(base: number): number
	return base * (1 + (self.rage / 100) * RAGE.SpeedBonus)
end

function MonsterAI:_setState(state: string)
	if self.state == state then
		return
	end
	self.state = state
	self.stateEnteredAt = os.clock()
	self._waypoints = {}
	if self.onStateChanged then
		self.onStateChanged(state)
	end
end

function MonsterAI:_computePath(destination: Vector3)
	self._lastPath = os.clock()
	self._pathGoal = destination
	local ok = pcall(function()
		self._path:ComputeAsync(self.rig.Root.Position, destination)
	end)
	if ok and self._path.Status == Enum.PathStatus.Success then
		self._waypoints = self._path:GetWaypoints()
		self._waypointIndex = 2 -- первая точка - там, где монстр уже стоит
	else
		self._waypoints = {}
	end
end

function MonsterAI:_stepTowards(destination: Vector3, speed: number)
	self.rig.Humanoid.WalkSpeed = speed

	local now = os.clock()
	local needPath = #self._waypoints == 0
		or now - self._lastPath > M.RepathInterval
		or (self._pathGoal - destination).Magnitude > 6
	if needPath then
		self:_computePath(destination)
	end

	local waypoint = self._waypoints[self._waypointIndex]
	while waypoint do
		local flat = Vector3.new(waypoint.Position.X, self.rig.Root.Position.Y, waypoint.Position.Z)
		if (flat - self.rig.Root.Position).Magnitude < 4 then
			self._waypointIndex += 1
			waypoint = self._waypoints[self._waypointIndex]
		else
			break
		end
	end

	if waypoint then
		self.rig.Humanoid:MoveTo(waypoint.Position)
	else
		-- Путь не построился (или уже дошли) - идём напрямую.
		self.rig.Humanoid:MoveTo(destination)
	end
end

function MonsterAI:_sightRange(): number
	return self.rage >= RAGE.FuryThreshold and M.FurySightRange or M.SightRange
end

function MonsterAI:_findVisiblePlayer(): Player?
	local origin = self.rig.Head.Position
	local look = self.rig.Root.CFrame.LookVector
	local cosFov = math.cos(math.rad(M.FieldOfView / 2))
	local range = self:_sightRange()

	local best: Player? = nil
	local bestDist = math.huge

	for _, player in Players:GetPlayers() do
		local root = Util.getRoot(player.Character)
		if root and Util.isAlive(player) and not player:GetAttribute("Escaped") then
			local offset = root.Position - origin
			local dist = offset.Magnitude
			if dist <= range and dist < bestDist then
				local inFov = offset.Unit:Dot(look) >= cosFov
				-- вплотную монстр чует и без обзора
				if inFov or dist < 12 then
					if Util.hasLineOfSight(origin, root.Position, { self.rig.Model }) then
						best = player
						bestDist = dist
					end
				end
			end
		end
	end

	return best
end

-- Монстр услышал шум в точке. radius - насколько далеко его слышно.
function MonsterAI:hear(position: Vector3, radius: number)
	if os.clock() < self.stunUntil then
		return
	end
	if (position - self.rig.Root.Position).Magnitude > radius then
		return
	end
	if self.state == "Chase" then
		return -- уже гонится, ему не до шороха
	end
	self.investigatePoint = position
	self:_setState("Investigate")
end

-- Приманка: монстр идёт к ней и тупит рядом.
function MonsterAI:lureTo(position: Vector3)
	if self.rage >= RAGE.FuryThreshold then
		return -- в ярости приманки его не обманывают
	end
	self.investigatePoint = position
	self:_setState("Investigate")
end

function MonsterAI:confuse(duration: number)
	self.stunUntil = os.clock() + duration
	self.target = nil
	self:_setState("Confused")
end

-- Игрок дерзко крикнул: монстр точно знает где ты.
function MonsterAI:provoke(player: Player)
	local root = Util.getRoot(player.Character)
	if not root then
		return
	end
	self.stunUntil = 0
	self.target = player
	self.lastKnown = root.Position
	self.lastSeenAt = os.clock()
	self:_setState("Chase")
end

function MonsterAI:_updatePatrol()
	local nodes = self.map.PatrolNodes
	local node = nodes[self.nodeIndex]
	self:_stepTowards(node, self:_speed(M.PatrolSpeed))
	if (node - self.rig.Root.Position).Magnitude < 8 then
		self.nodeIndex = math.random(1, #nodes)
	end
end

function MonsterAI:_updateInvestigate()
	local point = self.investigatePoint
	if not point then
		self:_setState("Patrol")
		return
	end
	self:_stepTowards(point, self:_speed(M.InvestigateSpeed))
	if (point - self.rig.Root.Position).Magnitude < 8 then
		self.lastKnown = point
		self:_setState("Search")
	end
end

function MonsterAI:_updateChase()
	local player = self.target
	local root = player and Util.getRoot(player.Character)
	if not player or not root or not Util.isAlive(player) then
		self:_setState("Search")
		return
	end

	local distance = (root.Position - self.rig.Root.Position).Magnitude
	if distance <= M.CatchDistance then
		if self.onCatch then
			self.onCatch(player)
		end
		self.target = nil
		self:_setState("Search")
		return
	end

	local visible = Util.hasLineOfSight(self.rig.Head.Position, root.Position, { self.rig.Model })
		and distance <= self:_sightRange() + 20
	if visible then
		self.lastSeenAt = os.clock()
		self.lastKnown = root.Position
	elseif os.clock() - self.lastSeenAt > M.LoseSightGrace then
		self.target = nil
		self:_setState("Search")
		return
	end

	self:_stepTowards(self.lastKnown or root.Position, self:_speed(M.ChaseSpeed))
end

function MonsterAI:_updateSearch()
	local point = self.lastKnown
	if point then
		self:_stepTowards(point, self:_speed(M.InvestigateSpeed))
	end
	if os.clock() - self.stateEnteredAt > M.SearchTime then
		self.lastKnown = nil
		self:_setState("Patrol")
	end
end

function MonsterAI:_think()
	if os.clock() < self.stunUntil then
		self.rig.Humanoid.WalkSpeed = 0
		self.rig.Humanoid:MoveTo(self.rig.Root.Position)
		return
	elseif self.state == "Confused" then
		self:_setState("Patrol")
	end

	-- Увидел кого-то - любая другая задача отменяется.
	local seen = self:_findVisiblePlayer()
	if seen then
		self.target = seen
		self.lastSeenAt = os.clock()
		local root = Util.getRoot(seen.Character)
		if root then
			self.lastKnown = root.Position
		end
		self:_setState("Chase")
	end

	if self.state == "Patrol" then
		self:_updatePatrol()
	elseif self.state == "Investigate" then
		self:_updateInvestigate()
	elseif self.state == "Chase" then
		self:_updateChase()
	elseif self.state == "Search" then
		self:_updateSearch()
	end
end

function MonsterAI:teleportToSpawn()
	self.target = nil
	self.lastKnown = nil
	self.investigatePoint = nil
	self.stunUntil = 0
	self:_setState("Patrol")
	self.rig.Root.CFrame = CFrame.new(self.map.MonsterSpawn + Vector3.new(0, 4, 0))
end

function MonsterAI:start()
	local accumulator = 0
	self._connection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.15 then
			return
		end
		accumulator = 0
		local ok, err = pcall(function()
			self:_think()
		end)
		if not ok then
			warn("[Saranha] ошибка в мозгах монстра: " .. tostring(err))
		end
	end)
end

function MonsterAI:stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

return MonsterAI
