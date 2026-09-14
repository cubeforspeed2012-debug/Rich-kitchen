--!nonstrict
-- Арена одной комнаты: дом, куда телепортируются 4 игрока.
-- Строится по смещению origin, поэтому несколько комнат живут параллельно.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Util = require(Shared:WaitForChild("Util"))

local ARENA = GameConfig.Arena
local WALL_H = ARENA.WallHeight
local WALL_T = ARENA.WallThickness
local HALF_X = ARENA.HalfX
local HALF_Z = ARENA.HalfZ

local WALL_COLOR = Color3.fromRGB(52, 48, 46)
local FLOOR_COLOR = Color3.fromRGB(28, 26, 25)

local ArenaBuilder = {}

function ArenaBuilder.build(origin: Vector3, index: number)
	local model = Instance.new("Model")
	model.Name = "HWC_Arena_" .. index
	model.Parent = Workspace

	local lights = {}

	local function pos(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end

	local function wallZ(x: number, zFrom: number, zTo: number)
		local length = zTo - zFrom
		Util.makePart(model, "Wall", Vector3.new(WALL_T, WALL_H, length), pos(x, WALL_H / 2, (zFrom + zTo) / 2), WALL_COLOR, Enum.Material.Concrete)
	end

	local function wallX(z: number, xFrom: number, xTo: number)
		local length = xTo - xFrom
		Util.makePart(model, "Wall", Vector3.new(length, WALL_H, WALL_T), pos((xFrom + xTo) / 2, WALL_H / 2, z), WALL_COLOR, Enum.Material.Concrete)
	end

	local function ceilingLight(x: number, z: number)
		local lamp = Util.makePart(model, "Lamp", Vector3.new(6, 0.5, 6), pos(x, WALL_H - 1, z), Color3.fromRGB(255, 240, 210), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Range = 45
		light.Brightness = 1.8
		light.Color = Color3.fromRGB(255, 235, 200)
		light.Parent = lamp
		table.insert(lights, { Part = lamp, Light = light })
	end

	-- пол и потолок
	Util.makePart(model, "Floor", Vector3.new(HALF_X * 2, 2, HALF_Z * 2), pos(0, -1, 0), FLOOR_COLOR, Enum.Material.WoodPlanks)
	Util.makePart(model, "Ceiling", Vector3.new(HALF_X * 2, 2, HALF_Z * 2), pos(0, WALL_H + 1, 0), Color3.fromRGB(20, 19, 18), Enum.Material.Slate)

	-- внешние стены, в южной - проём под ворота
	wallX(-HALF_Z, -HALF_X, HALF_X)
	wallX(HALF_Z, -HALF_X, -8)
	wallX(HALF_Z, 8, HALF_X)
	wallZ(-HALF_X, -HALF_Z, HALF_Z)
	wallZ(HALF_X, -HALF_Z, HALF_Z)

	-- центральный зал с генератором
	wallZ(-40, -70, -40)
	wallZ(-40, -32, 10)
	wallZ(-40, 18, 70)
	wallZ(40, -70, -16)
	wallZ(40, -8, 34)
	wallZ(40, 42, 70)
	wallX(-30, -40, -6)
	wallX(-30, 2, 40)
	wallX(30, -40, 20)
	wallX(30, 28, 40)

	-- перегородки в западном и восточном крыле
	wallX(-20, -90, -70)
	wallX(-20, -62, -40)
	wallX(25, -90, -58)
	wallX(25, -50, -40)
	wallX(-45, 40, 60)
	wallX(-45, 68, 90)
	wallX(20, 40, 50)
	wallX(20, 58, 90)

	-- перегородки в северном и южном крыле
	wallZ(0, -70, -60)
	wallZ(0, -52, -30)
	wallZ(10, 30, 46)
	wallZ(10, 54, 70)

	-- свет
	for _, point in { { -65, -50 }, { -65, 0 }, { -65, 50 }, { 0, -50 }, { 0, 0 }, { 0, 50 }, { 65, -50 }, { 65, 0 }, { 65, 50 } } do
		ceilingLight(point[1], point[2])
	end

	-- генератор в центре
	local generator = Util.makePart(model, "Generator", Vector3.new(10, 8, 6), pos(0, 4, 0), Color3.fromRGB(70, 80, 70), Enum.Material.DiamondPlate)
	local generatorLight = Instance.new("PointLight")
	generatorLight.Color = Color3.fromRGB(255, 60, 60)
	generatorLight.Range = 25
	generatorLight.Brightness = 2
	generatorLight.Parent = generator

	-- ворота выхода
	local gate = Util.makePart(model, "ExitGate", Vector3.new(16, 15, WALL_T), pos(0, 7.5, HALF_Z), Color3.fromRGB(120, 30, 30), Enum.Material.Metal)
	gate:SetAttribute("Locked", true)

	Util.makePart(model, "ExitFloor", Vector3.new(30, 2, 30), pos(0, -1, HALF_Z + 15), FLOOR_COLOR, Enum.Material.Slate)
	local exitPad = Util.makePart(model, "ExitPad", Vector3.new(18, 1, 12), pos(0, 0.5, HALF_Z + 10), Color3.fromRGB(60, 210, 130), Enum.Material.Neon)
	exitPad.Transparency = 0.4

	local fuseSpots = {
		pos(-70, 3, -50),
		pos(70, 3, -58),
		pos(-70, 3, 50),
		pos(68, 3, 52),
		pos(-20, 3, -52),
		pos(28, 3, 55),
	}

	local wanderNodes = {
		pos(-65, 3, -50),
		pos(-65, 3, 0),
		pos(-65, 3, 50),
		pos(-20, 3, -52),
		pos(20, 3, -52),
		pos(0, 3, 0),
		pos(-20, 3, 52),
		pos(25, 3, 52),
		pos(65, 3, -50),
		pos(65, 3, 0),
		pos(65, 3, 50),
	}

	local spawnPositions = {
		pos(-32, 4, -62),
		pos(-22, 4, -62),
		pos(-32, 4, -50),
		pos(-22, 4, -50),
	}

	return {
		Model = model,
		Index = index,
		Origin = origin,
		Lights = lights,
		Generator = generator,
		GeneratorLight = generatorLight,
		Gate = gate,
		ExitPad = exitPad,
		FuseSpots = fuseSpots,
		WanderNodes = wanderNodes,
		SpawnPositions = spawnPositions,
		MonsterSpawn = pos(70, 4, 60),
	}
end

return ArenaBuilder
