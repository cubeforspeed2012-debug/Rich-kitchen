--!nonstrict
-- MapBuilder строит дом прямо из кода: стены, комнаты, лазы для подката,
-- тумбы под ключи и дверь выхода. Никаких моделей скачивать не нужно.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("LocustShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local MAP = GameConfig.Map
local WALL_H = MAP.WallHeight
local WALL_T = MAP.WallThickness
local VENT_H = MAP.VentHeight
local HALF_X = MAP.HalfX
local HALF_Z = MAP.HalfZ

local MapBuilder = {}

local model: Model

local function makePart(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Anchored = true
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local WALL_COLOR = Color3.fromRGB(58, 52, 48)
local FLOOR_COLOR = Color3.fromRGB(38, 34, 32)

-- Сплошной кусок стены вдоль оси Z (стена стоит "вертикально" на карте).
local function wallZ(x: number, zFrom: number, zTo: number)
	local length = zTo - zFrom
	local center = (zFrom + zTo) / 2
	makePart("Wall", Vector3.new(WALL_T, WALL_H, length), Vector3.new(x, WALL_H / 2, center), WALL_COLOR, Enum.Material.Concrete)
end

-- Сплошной кусок стены вдоль оси X.
local function wallX(z: number, xFrom: number, xTo: number)
	local length = xTo - xFrom
	local center = (xFrom + xTo) / 2
	makePart("Wall", Vector3.new(length, WALL_H, WALL_T), Vector3.new(center, WALL_H / 2, z), WALL_COLOR, Enum.Material.Concrete)
end

-- Лаз: снизу дырка высотой VENT_H (пролезть можно только подкатом),
-- сверху обычная стена. Монстр сюда не пойдёт - ему ставим запрет пути.
local function vent(size: Vector3, position: Vector3)
	local topHeight = WALL_H - VENT_H
	makePart(
		"VentTop",
		Vector3.new(size.X, topHeight, size.Z),
		Vector3.new(position.X, VENT_H + topHeight / 2, position.Z),
		WALL_COLOR,
		Enum.Material.Concrete
	)

	local frame = makePart(
		"VentFrame",
		Vector3.new(size.X + 0.4, 0.4, size.Z + 0.4),
		Vector3.new(position.X, VENT_H, position.Z),
		Color3.fromRGB(190, 160, 60),
		Enum.Material.Neon
	)
	frame.CanCollide = false

	-- Невидимый блокатор навигации: монстр обходит лаз через двери.
	local blocker = makePart(
		"VentBlock",
		Vector3.new(size.X + 1, VENT_H, size.Z + 1),
		Vector3.new(position.X, VENT_H / 2, position.Z),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic
	)
	blocker.Transparency = 1
	blocker.CanCollide = false
	blocker.CanQuery = false

	local modifier = Instance.new("PathfindingModifier")
	modifier.Label = "Vent"
	modifier.Parent = blocker
end

local function buildShell()
	makePart("Floor", Vector3.new(HALF_X * 2, 1, HALF_Z * 2), Vector3.new(0, -0.5, 0), FLOOR_COLOR, Enum.Material.WoodPlanks)

	-- Внешние стены. В северной оставляем проём под дверь выхода.
	wallX(-HALF_Z, -HALF_X, -6)
	wallX(-HALF_Z, 6, HALF_X)
	wallX(HALF_Z, -HALF_X, HALF_X)
	wallZ(-HALF_X, -HALF_Z, HALF_Z)
	wallZ(HALF_X, -HALF_Z, HALF_Z)
end

local function buildInterior()
	-- Стена x = -24: два дверных проёма и один лаз.
	wallZ(-24, -55, -40)
	wallZ(-24, -34, -4)
	vent(Vector3.new(WALL_T, 0, 6), Vector3.new(-24, 0, -1))
	wallZ(-24, 2, 34)
	wallZ(-24, 40, 55)

	-- Стена x = 24.
	wallZ(24, -55, -40)
	wallZ(24, -34, -10)
	vent(Vector3.new(WALL_T, 0, 6), Vector3.new(24, 0, -7))
	wallZ(24, -4, 40)
	wallZ(24, 40, 55)

	-- Стена z = -18.
	wallX(-18, -70, -52)
	wallX(-18, -46, -8)
	wallX(-18, -2, 44)
	vent(Vector3.new(6, 0, WALL_T), Vector3.new(47, 0, -18))
	wallX(-18, 50, 70)

	-- Стена z = 18.
	wallX(18, -70, -60)
	wallX(18, -54, -14)
	vent(Vector3.new(6, 0, WALL_T), Vector3.new(-11, 0, 18))
	wallX(18, -8, 30)
	wallX(18, 36, 70)
end

-- Ящики: за ними прячешься и ломаешь монстру прямую видимость.
local function buildFurniture()
	local rng = Random.new(1337)
	local roomsX = { -47, 0, 47 }
	local roomsZ = { -36.5, 0, 36.5 }

	for _, rx in roomsX do
		for _, rz in roomsZ do
			local count = rng:NextInteger(2, 4)
			for _ = 1, count do
				local sx = rng:NextNumber(4, 9)
				local sy = rng:NextNumber(3, 7)
				local sz = rng:NextNumber(4, 9)
				local px = rx + rng:NextNumber(-14, 14)
				local pz = rz + rng:NextNumber(-11, 11)
				-- не заваливаем спавн игрока и тумбы с ключами
				local spot = Vector3.new(px, 0, pz)
				if (spot - Vector3.new(0, 0, 40)).Magnitude < 14 then
					continue
				end
				if (spot - Vector3.new(rx, 0, rz)).Magnitude < 7 then
					continue
				end
				local crate = makePart(
					"Crate",
					Vector3.new(sx, sy, sz),
					Vector3.new(px, sy / 2, pz),
					Color3.fromRGB(92, 68, 44),
					Enum.Material.Wood
				)
				crate.Orientation = Vector3.new(0, rng:NextNumber(0, 360), 0)
			end
		end
	end
end

local function buildExit(): (Part, Part)
	local door = makePart("ExitDoor", Vector3.new(12, 13, WALL_T), Vector3.new(0, 6.5, -HALF_Z), Color3.fromRGB(120, 30, 30), Enum.Material.Metal)
	door:SetAttribute("Locked", true)

	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Back
	light.Color = Color3.fromRGB(255, 80, 80)
	light.Range = 22
	light.Brightness = 4
	light.Parent = door

	-- Площадка снаружи: коснулся - сбежал.
	local pad = makePart("EscapePad", Vector3.new(14, 1, 12), Vector3.new(0, 0, -HALF_Z - 8), Color3.fromRGB(60, 200, 120), Enum.Material.Neon)
	pad.Transparency = 0.45
	makePart("EscapeFloor", Vector3.new(24, 1, 24), Vector3.new(0, -0.5, -HALF_Z - 12), FLOOR_COLOR, Enum.Material.Slate)

	return door, pad
end

-- Тумбы, на которых появляются ключи.
local KEY_SPOTS = {
	Vector3.new(-47, 3, -36.5),
	Vector3.new(47, 3, -36.5),
	Vector3.new(-47, 3, 36.5),
	Vector3.new(47, 3, 36.5),
	Vector3.new(-47, 3, 0),
	Vector3.new(47, 3, 0),
	Vector3.new(0, 3, -36.5),
}

local PATROL_NODES = {
	Vector3.new(-47, 3, -36.5),
	Vector3.new(0, 3, -36.5),
	Vector3.new(47, 3, -36.5),
	Vector3.new(-47, 3, 0),
	Vector3.new(0, 3, 0),
	Vector3.new(47, 3, 0),
	Vector3.new(-47, 3, 36.5),
	Vector3.new(0, 3, 36.5),
	Vector3.new(47, 3, 36.5),
	Vector3.new(-49, 3, -18),
	Vector3.new(-5, 3, -18),
	Vector3.new(-24, 3, 37),
	Vector3.new(24, 3, -37),
}

function MapBuilder.build()
	local old = Workspace:FindFirstChild("LocustHouse")
	if old then
		old:Destroy()
	end

	model = Instance.new("Model")
	model.Name = "LocustHouse"
	model.Parent = Workspace

	buildShell()
	buildInterior()
	buildFurniture()
	local door, pad = buildExit()

	local spawnPosition = Vector3.new(0, 3, 40)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = spawnPosition - Vector3.new(0, 3, 0)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(80, 120, 200)
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.4
	spawn.Parent = model

	return {
		Model = model,
		ExitDoor = door,
		EscapePad = pad,
		SpawnPosition = spawnPosition,
		MonsterSpawn = Vector3.new(0, 3, -36.5),
		KeySpots = KEY_SPOTS,
		PatrolNodes = PATROL_NODES,
	}
end

return MapBuilder
