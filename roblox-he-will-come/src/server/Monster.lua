--!nonstrict
-- ОН. Патрулирует школу, идёт на шум, видит в конусе обзора (фонарь выдаёт издалека),
-- заметив - орёт на всю школу и БЕЖИТ. Потерял из виду - ищет, потом снова патруль.
-- В шкафчик за тобой не полезет, если не видел, как ты в него прыгнул.

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Util = require(Shared:WaitForChild("Util"))

local M = GameConfig.Monster

local Monster = {}
Monster.__index = Monster

local BODY = Color3.fromRGB(34, 34, 40)
local SKIN = Color3.fromRGB(200, 194, 182)

local function limb(model, name, size, color, collide)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Fabric
	part.CanCollide = collide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function weld(a, b, offset)
	b.CFrame = a.CFrame * CFrame.new(offset)
	local joint = Instance.new("Weld")
	joint.Part0 = a
	joint.Part1 = b
	joint.C0 = CFrame.new(offset)
	joint.Parent = a
end

local ROOT_HEIGHT = 5.5

local function buildRig(spawnPosition, collisionGroup)
	local model = Instance.new("Model")
	model.Name = "HE"

	local root = limb(model, "HumanoidRootPart", Vector3.new(2, 2, 1), BODY, false)
	root.Transparency = 1
	root.CFrame = CFrame.new(spawnPosition + Vector3.new(0, ROOT_HEIGHT, 0))
	model.PrimaryPart = root

	local torso = limb(model, "Torso", Vector3.new(2.4, 4, 1.3), BODY, true)
	weld(root, torso, Vector3.new(0, 0, 0))

	local head = limb(model, "Head", Vector3.new(1.6, 1.9, 1.6), SKIN, true)
	head.Material = Enum.Material.Sand
	weld(torso, head, Vector3.new(0, 2.9, 0))

	-- рот: тёмная щель, видно, когда орёт
	local mouth = limb(model, "Mouth", Vector3.new(1.0, 0.25, 0.2), Color3.fromRGB(20, 5, 5), false)
	mouth.Material = Enum.Material.Neon
	weld(head, mouth, Vector3.new(0, -0.45, -0.85))

	weld(torso, limb(model, "Right Arm", Vector3.new(1, 5.2, 1), BODY, false), Vector3.new(1.7, -0.7, 0))
	weld(torso, limb(model, "Left Arm", Vector3.new(1, 5.2, 1), BODY, false), Vector3.new(-1.7, -0.7, 0))
	weld(torso, limb(model, "Right Leg", Vector3.new(1.1, 4, 1.1), BODY, true), Vector3.new(0.65, -3.5, 0))
	weld(torso, limb(model, "Left Leg", Vector3.new(1.1, 4, 1.1), BODY, true), Vector3.new(-0.65, -3.5, 0))

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 70, 50)
	glow.Range = 14
	glow.Brightness = 0.8
	glow.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.MaxHealth = 100000
	humanoid.Health = 100000
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 0
	humanoid.Parent = model

	if collisionGroup then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = collisionGroup
			end
		end
	end

	return { Model = model, Humanoid = humanoid, Root = root, Head = head, Mouth = mouth, Glow = glow }
end

function Monster.new(arena, collisionGroup)
	local self = setmetatable({}, Monster)
	self.arena = arena
	self.rig = buildRig(arena.MonsterSpawn, collisionGroup)
	self.rig.Model.Parent = Workspace

	self.state = "Sleep"
	self.target = nil
	self.lastKnown = nil
	self.lastSeenAt = 0
	self.stateEnteredAt = os.clock()
	self.investigatePoint = nil
	self.nodeIndex = math.random(1, #arena.PatrolNodes)
	self.speedBonus = 0
	self.lastScream = -100
	self.lastCatch = -100

	self._waypoints = {}
	self._waypointIndex = 1
	self._pathGoal = Vector3.zero
	self._lastPath = 0
	self._path = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 9,
		AgentCanJump = false,
	})

	-- колбэки задаёт Match
	self.onCatch = nil
	self.onScream = nil
	self.onStateChanged = nil
	self.isPlayerHidden = function()
		return false
	end
	self.isPlayerTargetable = function()
		return true
	end
	self.hasFlashlight = function()
		return false
	end
	self.getLockerOf = function()
		return nil
	end

	return self
end

function Monster:destroy()
	self.state = "Dead"
	self.rig.Model:Destroy()
end

function Monster:_setState(state)
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

function Monster:_speed(base)
	return base + self.speedBonus
end

function Monster:_computePath(destination)
	self._lastPath = os.clock()
	self._pathGoal = destination
	local ok = pcall(function()
		self._path:ComputeAsync(self.rig.Root.Position, destination)
	end)
	if ok and self._path.Status == Enum.PathStatus.Success then
		self._waypoints = self._path:GetWaypoints()
		self._waypointIndex = 2
	else
		self._waypoints = {}
	end
end

function Monster:_moveTo(destination, speed)
	self.rig.Humanoid.WalkSpeed = speed
	local now = os.clock()
	if #self._waypoints == 0 or now - self._lastPath > M.RepathInterval or (self._pathGoal - destination).Magnitude > 6 then
		self:_computePath(destination)
	end

	local waypoint = self._waypoints[self._waypointIndex]
	while waypoint do
		local flat = Vector3.new(waypoint.Position.X, self.rig.Root.Position.Y, waypoint.Position.Z)
		if (flat - self.rig.Root.Position).Magnitude < 3.5 then
			self._waypointIndex += 1
			waypoint = self._waypoints[self._waypointIndex]
		else
			break
		end
	end

	if waypoint then
		self.rig.Humanoid:MoveTo(waypoint.Position)
	else
		self.rig.Humanoid:MoveTo(destination)
	end
end

function Monster:_canSee(player)
	if not self.isPlayerTargetable(player) or self.isPlayerHidden(player) then
		return false, nil
	end
	local root = Util.getRoot(player.Character)
	if not root or not Util.isAlive(player) then
		return false, nil
	end

	local origin = self.rig.Head.Position
	local offset = root.Position - origin
	local distance = offset.Magnitude
	local range = self.hasFlashlight(player) and M.SightRangeFlashlight or M.SightRange
	if distance > range then
		return false, nil
	end

	local inFov = offset.Unit:Dot(self.rig.Root.CFrame.LookVector) >= math.cos(math.rad(M.FieldOfView / 2))
	if not inFov and distance > M.CloseSense then
		return false, nil
	end

	if not Util.hasLineOfSight(origin, root.Position, { self.rig.Model }) then
		return false, nil
	end
	return true, root
end

function Monster:_findVisible(players)
	local best, bestDistance = nil, math.huge
	for _, player in players do
		local visible, root = self:_canSee(player)
		if visible then
			local distance = (root.Position - self.rig.Root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

-- Шум в точке. Если далеко - не слышит.
function Monster:hear(position, radius, force)
	if self.state == "Sleep" or self.state == "Dead" then
		return
	end
	if not force and (position - self.rig.Root.Position).Magnitude > radius then
		return
	end
	if self.state == "Chase" and not force then
		return
	end
	self.investigatePoint = position
	if self.state == "Chase" then
		self.target = nil
	end
	self:_setState("Investigate")
end

function Monster:_scream(player)
	if os.clock() - self.lastScream < M.ScreamCooldown then
		return
	end
	self.lastScream = os.clock()
	self.rig.Mouth.Size = Vector3.new(1.0, 0.9, 0.2)
	task.delay(1.2, function()
		if self.rig.Mouth.Parent then
			self.rig.Mouth.Size = Vector3.new(1.0, 0.25, 0.2)
		end
	end)
	if self.onScream then
		self.onScream(player)
	end
end

function Monster:_tryCatch(player)
	local root = Util.getRoot(player.Character)
	if not root then
		return false
	end
	if (root.Position - self.rig.Root.Position).Magnitude > M.CatchDistance then
		return false
	end
	if os.clock() - self.lastCatch < M.CatchCooldown then
		return false
	end
	self.lastCatch = os.clock()
	if self.onCatch then
		self.onCatch(player)
	end
	return true
end

function Monster:_updatePatrol()
	local nodes = self.arena.PatrolNodes
	local node = nodes[self.nodeIndex]
	self:_moveTo(node, self:_speed(M.PatrolSpeed))
	if (Util.flat(node) - Util.flat(self.rig.Root.Position)).Magnitude < 6 then
		self.nodeIndex = math.random(1, #nodes)
	end
end

function Monster:_updateInvestigate()
	local point = self.investigatePoint
	if not point then
		self:_setState("Patrol")
		return
	end
	self:_moveTo(point, self:_speed(M.InvestigateSpeed))
	if (Util.flat(point) - Util.flat(self.rig.Root.Position)).Magnitude < 6 then
		self.lastKnown = point
		self:_setState("Search")
	end
end

function Monster:_updateChase()
	local player = self.target
	if not player or not player.Parent or not self.isPlayerTargetable(player) then
		self.target = nil
		self:_setState("Search")
		return
	end

	local root = Util.getRoot(player.Character)
	if not root or not Util.isAlive(player) then
		self.target = nil
		self:_setState("Search")
		return
	end

	-- игрок прыгнул в шкаф у него на глазах - вытащит
	if self.isPlayerHidden(player) then
		if os.clock() - self.lastSeenAt < M.LockerPullGrace + 2 then
			local locker = self.getLockerOf(player)
			if locker then
				self:_moveTo(locker.Outside, self:_speed(M.ChaseSpeed))
				if (Util.flat(locker.Outside) - Util.flat(self.rig.Root.Position)).Magnitude < 4 then
					self.lastCatch = os.clock()
					if self.onCatch then
						self.onCatch(player)
					end
					self.target = nil
					self:_setState("Search")
				end
				return
			end
		end
		self.target = nil
		self:_setState("Search")
		return
	end

	if self:_tryCatch(player) then
		self.target = nil
		self:_setState("Search")
		return
	end

	local visible = self:_canSee(player)
	if visible then
		self.lastSeenAt = os.clock()
		self.lastKnown = root.Position
	elseif os.clock() - self.lastSeenAt > M.LoseSightGrace then
		self.target = nil
		self:_setState("Search")
		return
	end

	self:_moveTo(self.lastKnown or root.Position, self:_speed(M.ChaseSpeed))
end

function Monster:_updateSearch()
	if self.lastKnown then
		self:_moveTo(self.lastKnown, self:_speed(M.InvestigateSpeed))
		if (Util.flat(self.lastKnown) - Util.flat(self.rig.Root.Position)).Magnitude < 5 then
			-- дошёл: потоптаться вокруг
			self.lastKnown = self.lastKnown + Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
		end
	end
	if os.clock() - self.stateEnteredAt > M.SearchTime then
		self.lastKnown = nil
		self:_setState("Patrol")
	end
end

function Monster:step(players)
	if self.state == "Sleep" or self.state == "Dead" then
		return
	end

	local seen = self:_findVisible(players)
	if seen then
		if self.state ~= "Chase" then
			self:_scream(seen)
		end
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

function Monster:wake()
	self.rig.Root.CFrame = CFrame.new(self.arena.MonsterSpawn + Vector3.new(0, ROOT_HEIGHT, 0))
	self:_setState("Patrol")
end

function Monster:addSpeed(amount)
	self.speedBonus += amount
	self.rig.Glow.Brightness = 0.8 + self.speedBonus * 0.6
	self.rig.Glow.Range = 14 + self.speedBonus * 4
end

return Monster
