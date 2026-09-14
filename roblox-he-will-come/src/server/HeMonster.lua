--!nonstrict
-- ОН.
-- Не патрулирует и не высматривает: ОН слеп. Идёт на того, кто громче шумит.
-- Пока хотя бы один игрок смотрит ему в лицо - почти стоит на месте.
-- Как только все отвернулись - разгоняется, и чем дольше никто не смотрит, тем быстрее.

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Util = require(Shared:WaitForChild("Util"))

local GazeTracker = require(script.Parent:WaitForChild("GazeTracker"))

local HE = GameConfig.He
local NOISE = GameConfig.Noise

local HeMonster = {}
HeMonster.__index = HeMonster

local BODY_COLOR = Color3.fromRGB(38, 38, 44)
local SKIN_COLOR = Color3.fromRGB(196, 190, 178)

local function limb(model: Model, name: string, size: Vector3, color: Color3, collide: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Sand
	part.CanCollide = collide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function weld(a: BasePart, b: BasePart, offset: Vector3)
	b.CFrame = a.CFrame * CFrame.new(offset)
	local joint = Instance.new("Weld")
	joint.Part0 = a
	joint.Part1 = b
	joint.C0 = CFrame.new(offset)
	joint.Parent = a
end

local function buildRig(spawnPosition: Vector3, collisionGroup: string?)
	local model = Instance.new("Model")
	model.Name = "HE"

	local root = limb(model, "HumanoidRootPart", Vector3.new(2, 2, 1), BODY_COLOR, false)
	root.Transparency = 1
	root.CFrame = CFrame.new(spawnPosition + Vector3.new(0, 5.5, 0))
	model.PrimaryPart = root

	local torso = limb(model, "Torso", Vector3.new(2.2, 4, 1.2), BODY_COLOR, true)
	weld(root, torso, Vector3.new(0, 0, 0))

	-- лицо без лица
	local head = limb(model, "Head", Vector3.new(1.5, 1.9, 1.5), SKIN_COLOR, true)
	weld(torso, head, Vector3.new(0, 2.8, 0))

	weld(torso, limb(model, "Right Arm", Vector3.new(0.9, 5, 0.9), BODY_COLOR, false), Vector3.new(1.6, -0.6, 0))
	weld(torso, limb(model, "Left Arm", Vector3.new(0.9, 5, 0.9), BODY_COLOR, false), Vector3.new(-1.6, -0.6, 0))
	weld(torso, limb(model, "Right Leg", Vector3.new(1, 4, 1), BODY_COLOR, true), Vector3.new(0.6, -3.5, 0))
	weld(torso, limb(model, "Left Leg", Vector3.new(1, 4, 1), BODY_COLOR, true), Vector3.new(-0.6, -3.5, 0))

	-- еле заметный контур: в темноте видно только силуэт
	local rim = Instance.new("PointLight")
	rim.Color = Color3.fromRGB(190, 190, 200)
	rim.Range = 11
	rim.Brightness = 0.5
	rim.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.MaxHealth = 100000
	humanoid.Health = 100000
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 0
	humanoid.Parent = model

	if collisionGroup then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = collisionGroup
			end
		end
	end

	return { Model = model, Humanoid = humanoid, Root = root, Head = head, Rim = rim }
end

function HeMonster.new(arena, collisionGroup: string?)
	local self = setmetatable({}, HeMonster)

	self.arena = arena
	self.rig = buildRig(arena.MonsterSpawn, collisionGroup)
	self.rig.Model.Parent = Workspace

	self.momentum = 0
	self.gazed = false
	self.gazers = {}
	self.targetPlayer = nil
	self.wanderIndex = 1
	self.lastCatch = 0
	self.active = false

	self._waypoints = {}
	self._waypointIndex = 1
	self._pathGoal = Vector3.zero
	self._lastPath = 0

	self._path = PathfindingService:CreatePath({
		AgentRadius = 3,
		AgentHeight = 10,
		AgentCanJump = false,
	})

	self.onCatch = nil
	return self
end

function HeMonster:destroy()
	self.active = false
	if self.rig.Model then
		self.rig.Model:Destroy()
	end
end

function HeMonster:_computePath(destination: Vector3)
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

function HeMonster:_moveTo(destination: Vector3, speed: number)
	self.rig.Humanoid.WalkSpeed = speed

	local now = os.clock()
	if #self._waypoints == 0 or now - self._lastPath > HE.RepathInterval or (self._pathGoal - destination).Magnitude > 8 then
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
		self.rig.Humanoid:MoveTo(destination)
	end
end

-- Кто сейчас смотрит ему в лицо.
function HeMonster:_updateGaze(players)
	local cosLimit = math.cos(math.rad(HE.GazeAngle))
	local headPosition = self.rig.Head.Position

	table.clear(self.gazers)
	local gazed = false

	for _, player in players do
		local entry = GazeTracker.get(player)
		local root = Util.getRoot(player.Character)
		if entry and root and Util.isAlive(player) then
			local offset = headPosition - entry.position
			local distance = offset.Magnitude
			if distance <= HE.GazeRange and distance > 1 then
				if offset.Unit:Dot(entry.look) >= cosLimit then
					if Util.hasLineOfSight(entry.position, headPosition, { self.rig.Model, player.Character }) then
						gazed = true
						table.insert(self.gazers, player)
					end
				end
			end
		end
	end

	self.gazed = gazed
	return gazed
end

-- Куда идти: на самый громкий источник.
function HeMonster:_pickTarget(heat)
	local bestPlayer = nil
	local bestHeat = 1

	for player, value in heat do
		local root = Util.getRoot(player.Character)
		if root and Util.isAlive(player) and value > bestHeat then
			bestPlayer = player
			bestHeat = value
		end
	end

	if bestPlayer then
		return bestPlayer
	end

	-- никто не шумит - но вплотную он чует и молчащего
	local closest = nil
	local closestDistance = NOISE.SenseRadius
	for player in heat do
		local root = Util.getRoot(player.Character)
		if root and Util.isAlive(player) then
			local distance = (root.Position - self.rig.Root.Position).Magnitude
			if distance < closestDistance then
				closest = player
				closestDistance = distance
			end
		end
	end

	return closest
end

function HeMonster:step(dt: number, players, heat)
	if not self.active then
		return
	end

	local gazed = self:_updateGaze(players)

	if gazed then
		self.momentum = math.max(0, self.momentum - HE.MomentumLossOnGaze * dt)
		-- поворачивается лицом к тому, кто смотрит
		local watcher = self.gazers[1]
		local watcherRoot = watcher and Util.getRoot(watcher.Character)
		if watcherRoot then
			local flat = Vector3.new(watcherRoot.Position.X, self.rig.Root.Position.Y, watcherRoot.Position.Z)
			self.rig.Root.CFrame = CFrame.lookAt(self.rig.Root.Position, flat)
		end
	else
		self.momentum = math.min(HE.MaxSpeed - HE.BaseSpeed, self.momentum + HE.Momentum * dt)
	end

	local speed = gazed and HE.BaseSpeed * HE.GazeSpeedFactor or (HE.BaseSpeed + self.momentum)

	local target = self:_pickTarget(heat)
	self.targetPlayer = target

	local destination
	if target then
		local root = Util.getRoot(target.Character)
		destination = root and root.Position
	end

	if not destination then
		local node = self.arena.WanderNodes[self.wanderIndex]
		destination = node
		if (node - self.rig.Root.Position).Magnitude < 10 then
			self.wanderIndex = math.random(1, #self.arena.WanderNodes)
		end
		speed = math.min(speed, HE.BaseSpeed)
	end

	self:_moveTo(destination, speed)

	-- поймал?
	if target and os.clock() - self.lastCatch > HE.CatchCooldown then
		local root = Util.getRoot(target.Character)
		if root and (root.Position - self.rig.Root.Position).Magnitude <= HE.CatchDistance then
			self.lastCatch = os.clock()
			if self.onCatch then
				self.onCatch(target)
			end
		end
	end
end

function HeMonster:arrive()
	self.active = true
	self.momentum = 0
	self.rig.Root.CFrame = CFrame.new(self.arena.MonsterSpawn + Vector3.new(0, 5.5, 0))
end

function HeMonster:getSpeed(): number
	return self.rig.Humanoid.WalkSpeed
end

return HeMonster
