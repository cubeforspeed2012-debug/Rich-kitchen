--!nonstrict
-- Строит школу из текстовой схемы MapData.Grid. 1 символ = 4 стада.
-- Стены, окна, пол, потолок, лампы, шкафчики, парты, двор, забор, ворота.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Util = require(Shared:WaitForChild("Util"))

local MapData = require(script.Parent:WaitForChild("MapData"))

local T = MapData.TileSize
local WALL_H = GameConfig.Map.WallHeight

local COLORS = {
	Wall = Color3.fromRGB(168, 156, 132),
	WallDark = Color3.fromRGB(96, 84, 70),
	RoomFloor = Color3.fromRGB(150, 128, 96),
	CorridorFloor = Color3.fromRGB(104, 110, 112),
	Ceiling = Color3.fromRGB(52, 50, 48),
	Grass = Color3.fromRGB(60, 92, 44),
	Asphalt = Color3.fromRGB(58, 58, 60),
	Fence = Color3.fromRGB(70, 74, 78),
	Locker = Color3.fromRGB(58, 72, 66),
	LockerDoor = Color3.fromRGB(78, 96, 88),
	Desk = Color3.fromRGB(110, 78, 48),
	Lintel = Color3.fromRGB(70, 48, 34),
	Lamp = Color3.fromRGB(255, 240, 210),
}

local INTERIOR = { ["."] = true, [","] = true, ["D"] = true, ["P"] = true, ["M"] = true, ["B"] = true, ["L"] = true }
local WALLISH = { ["#"] = true, ["W"] = true }

local MapBuilder = {}

function MapBuilder.build(origin, index)
	local model = Instance.new("Model")
	model.Name = "HWC_Arena_" .. tostring(index)

	-- ---------- разбор схемы ----------
	local rows = {}
	for _, line in string.split(MapData.Grid, "\n") do
		if #line > 0 then
			table.insert(rows, line)
		end
	end
	local H = #rows
	local W = 0
	for _, line in rows do
		W = math.max(W, #line)
	end

	local function tile(c, r)
		if c < 0 or r < 0 or c >= W or r >= H then
			return " "
		end
		local line = rows[r + 1]
		if c + 1 > #line then
			return " "
		end
		return string.sub(line, c + 1, c + 1)
	end

	local function center(c, r, y)
		return origin + Vector3.new((c - W / 2 + 0.5) * T, y or 0, (r - H / 2 + 0.5) * T)
	end

	-- центр отрезка тайлов c1..c2 в строке r
	local function runCenter(c1, c2, r, y)
		return origin + Vector3.new(((c1 + c2) / 2 - W / 2 + 0.5) * T, y or 0, (r - H / 2 + 0.5) * T)
	end

	local function isInterior(ch)
		return INTERIOR[ch] == true
	end

	local function isWallish(ch)
		return WALLISH[ch] == true
	end

	-- обходим строки и вызываем callback на каждый непрерывный отрезок тайлов одного "класса"
	local function forRuns(classify, callback)
		for r = 0, H - 1 do
			local c = 0
			while c < W do
				local class = classify(tile(c, r), c, r)
				if class then
					local c2 = c
					while c2 + 1 < W and classify(tile(c2 + 1, r), c2 + 1, r) == class do
						c2 += 1
					end
					callback(class, c, c2, r)
					c = c2 + 1
				else
					c += 1
				end
			end
		end
	end

	local result = {
		Model = model,
		Origin = origin,
		Index = index,
		Lights = {},
		Lockers = {},
		Searchables = {},
		SpawnPositions = {},
		MonsterSpawn = origin,
		PatrolNodes = {},
		Gate = nil,
		ExitPad = nil,
	}

	-- ---------- земля ----------
	local grass = Util.makePart(model, "Grass", Vector3.new(W * T + 40, 2, H * T + 40), origin + Vector3.new(0, -1, 0), COLORS.Grass, Enum.Material.Grass)
	grass.Name = "Grass"

	-- ---------- асфальт ----------
	forRuns(function(ch)
		return ch == "=" and "asphalt" or nil
	end, function(_, c1, c2, r)
		Util.makePart(model, "Asphalt", Vector3.new((c2 - c1 + 1) * T, 0.3, T), runCenter(c1, c2, r, 0.05), COLORS.Asphalt, Enum.Material.Asphalt)
	end)

	-- ---------- пол и потолок ----------
	forRuns(function(ch)
		if not isInterior(ch) then
			return nil
		end
		return (ch == "," or ch == "D") and "corridor" or "room"
	end, function(class, c1, c2, r)
		local isCorridor = class == "corridor"
		Util.makePart(
			model,
			"Floor",
			Vector3.new((c2 - c1 + 1) * T, 1.4, T),
			runCenter(c1, c2, r, -0.5),
			isCorridor and COLORS.CorridorFloor or COLORS.RoomFloor,
			isCorridor and Enum.Material.Concrete or Enum.Material.WoodPlanks
		)
	end)

	forRuns(function(ch)
		return isInterior(ch) and "ceil" or nil
	end, function(_, c1, c2, r)
		Util.makePart(model, "Ceiling", Vector3.new((c2 - c1 + 1) * T, 1, T), runCenter(c1, c2, r, WALL_H + 0.5), COLORS.Ceiling, Enum.Material.Concrete)
	end)

	-- ---------- стены ----------
	forRuns(function(ch)
		return ch == "#" and "wall" or nil
	end, function(_, c1, c2, r)
		local wall = Util.makePart(model, "Wall", Vector3.new((c2 - c1 + 1) * T, WALL_H, T), runCenter(c1, c2, r, WALL_H / 2), COLORS.Wall, Enum.Material.Brick)
		wall.Name = "Wall"
	end)

	-- окна: низ стены, стекло, верх стены
	for r = 0, H - 1 do
		for c = 0, W - 1 do
			if tile(c, r) == "W" then
				Util.makePart(model, "WallLow", Vector3.new(T, 4, T), center(c, r, 2), COLORS.Wall, Enum.Material.Brick)
				local glass = Util.makePart(model, "Glass", Vector3.new(T, 5, T), center(c, r, 6.5), Color3.fromRGB(150, 190, 210), Enum.Material.Glass)
				glass.Transparency = 0.55
				Util.makePart(model, "WallHigh", Vector3.new(T, 3, T), center(c, r, 10.5), COLORS.Wall, Enum.Material.Brick)
			end
		end
	end

	-- перемычки над дверными проёмами (тайлы D)
	for r = 0, H - 1 do
		for c = 0, W - 1 do
			if tile(c, r) == "D" then
				Util.makePart(model, "Lintel", Vector3.new(T, 3, T), center(c, r, WALL_H - 1.5), COLORS.Lintel, Enum.Material.Wood)
			end
		end
	end

	-- ---------- лампы ----------
	for r = 0, H - 1 do
		for c = 0, W - 1 do
			if isInterior(tile(c, r)) and c % 4 == 2 and r % 4 == 2 then
				local lamp = Util.makePart(model, "Lamp", Vector3.new(2.6, 0.3, 2.6), center(c, r, WALL_H - 0.4), COLORS.Lamp, Enum.Material.Neon)
				local light = Instance.new("PointLight")
				light.Range = 30
				light.Brightness = 1.1
				light.Color = Color3.fromRGB(255, 236, 200)
				light.Shadows = false
				light.Parent = lamp
				table.insert(result.Lights, { Part = lamp, Light = light, Position = lamp.Position })
			end
		end
	end

	-- ---------- забор и ворота ----------
	for r = 0, H - 1 do
		for c = 0, W - 1 do
			local ch = tile(c, r)
			if ch == "F" then
				local left, right = tile(c - 1, r), tile(c + 1, r)
				local up, down = tile(c, r - 1), tile(c, r + 1)
				local horizontal = left == "F" or right == "F" or left == "X" or right == "X"
				local vertical = up == "F" or down == "F"
				if horizontal then
					local panel = Util.makePart(model, "Fence", Vector3.new(T, 9, 0.5), center(c, r, 4.5), COLORS.Fence, Enum.Material.Metal)
					panel.Transparency = 0.3
				end
				if vertical then
					local panel = Util.makePart(model, "Fence", Vector3.new(0.5, 9, T), center(c, r, 4.5), COLORS.Fence, Enum.Material.Metal)
					panel.Transparency = 0.3
				end
				Util.makePart(model, "FencePost", Vector3.new(1, 9.5, 1), center(c, r, 4.75), COLORS.WallDark, Enum.Material.Metal)
			end
		end
	end

	forRuns(function(ch)
		return ch == "X" and "gate" or nil
	end, function(_, c1, c2, r)
		local width = (c2 - c1 + 1) * T
		local gate = Util.makePart(model, "ExitGate", Vector3.new(width, 9, 0.8), runCenter(c1, c2, r, 4.5), Color3.fromRGB(130, 32, 32), Enum.Material.Metal)
		gate:SetAttribute("Locked", true)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 60, 60)
		light.Range = 20
		light.Brightness = 2
		light.Parent = gate
		result.Gate = gate

		local padCenter = runCenter(c1, c2, r + 1, 0.3)
		local pad = Util.makePart(model, "ExitPad", Vector3.new(width + 4, 0.5, T * 1.5), padCenter, Color3.fromRGB(60, 210, 130), Enum.Material.Neon)
		pad.Transparency = 0.4
		result.ExitPad = pad
	end)

	-- ---------- деревья ----------
	for r = 0, H - 1 do
		for c = 0, W - 1 do
			if tile(c, r) == "T" then
				Util.makePart(model, "Trunk", Vector3.new(1.8, 9, 1.8), center(c, r, 4.5), Color3.fromRGB(70, 50, 34), Enum.Material.Wood)
				local crown = Util.makePart(model, "Crown", Vector3.new(10, 9, 10), center(c, r, 11), Color3.fromRGB(44, 78, 38), Enum.Material.LeafyGrass)
				crown.Shape = Enum.PartType.Ball
				crown.CanCollide = false
			end
		end
	end

	-- ---------- шкафчики ----------
	local function buildLocker(c, r)
		local base = center(c, r, 0)
		-- лицом от стены
		local facing = Vector3.new(0, 0, 1)
		if isWallish(tile(c, r - 1)) then
			facing = Vector3.new(0, 0, 1)
		elseif isWallish(tile(c, r + 1)) then
			facing = Vector3.new(0, 0, -1)
		elseif isWallish(tile(c - 1, r)) then
			facing = Vector3.new(1, 0, 0)
		elseif isWallish(tile(c + 1, r)) then
			facing = Vector3.new(-1, 0, 0)
		end
		local side = Vector3.new(facing.Z, 0, facing.X) -- перпендикуляр
		local lockerModel = Instance.new("Model")
		lockerModel.Name = "Locker"
		lockerModel.Parent = model

		local width, height, depth = 3.6, 8, 3.2
		local function panel(name, size, offset, color)
			return Util.makePart(lockerModel, name, size, base + offset, color, Enum.Material.Metal)
		end
		-- ориентация: ширина вдоль side, глубина вдоль facing
		local function oriented(w, d)
			return Vector3.new(math.abs(side.X) * w + math.abs(facing.X) * d, height, math.abs(side.Z) * w + math.abs(facing.Z) * d)
		end
		panel("Back", oriented(width, 0.3), Vector3.new(0, height / 2, 0) - facing * (depth / 2), COLORS.Locker)
		panel("SideA", oriented(0.3, depth), Vector3.new(0, height / 2, 0) + side * (width / 2), COLORS.Locker)
		panel("SideB", oriented(0.3, depth), Vector3.new(0, height / 2, 0) - side * (width / 2), COLORS.Locker)
		panel("Top", Vector3.new(math.abs(side.X) * width + math.abs(facing.X) * depth, 0.3, math.abs(side.Z) * width + math.abs(facing.Z) * depth), Vector3.new(0, height, 0), COLORS.Locker)
		local door = panel("Door", oriented(width, 0.3), Vector3.new(0, height / 2, 0) + facing * (depth / 2), COLORS.LockerDoor)
		door.Transparency = 0.35

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Спрятаться"
		prompt.ObjectText = "Шкафчик"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = door

		table.insert(result.Lockers, {
			Model = lockerModel,
			Door = door,
			Prompt = prompt,
			Inside = base + Vector3.new(0, 3.2, 0),
			Outside = base + facing * (T * 0.95) + Vector3.new(0, 3.2, 0),
			Occupant = nil,
		})
	end

	-- ---------- парты с рюкзаками ----------
	local backpackColors = {
		Color3.fromRGB(160, 40, 40), Color3.fromRGB(40, 70, 150), Color3.fromRGB(40, 120, 60),
		Color3.fromRGB(150, 110, 30), Color3.fromRGB(90, 40, 120),
	}
	local function buildSearchable(c, r)
		local base = center(c, r, 0)
		local deskModel = Instance.new("Model")
		deskModel.Name = "Desk"
		deskModel.Parent = model
		Util.makePart(deskModel, "Top", Vector3.new(3.6, 0.3, 2.2), base + Vector3.new(0, 2.6, 0), COLORS.Desk, Enum.Material.Wood)
		Util.makePart(deskModel, "LegA", Vector3.new(0.3, 2.5, 2.0), base + Vector3.new(-1.6, 1.25, 0), COLORS.WallDark, Enum.Material.Metal)
		Util.makePart(deskModel, "LegB", Vector3.new(0.3, 2.5, 2.0), base + Vector3.new(1.6, 1.25, 0), COLORS.WallDark, Enum.Material.Metal)
		local bag = Util.makePart(deskModel, "Backpack", Vector3.new(1.3, 1.1, 0.8), base + Vector3.new(0.4, 3.3, 0.2), backpackColors[math.random(1, #backpackColors)], Enum.Material.Fabric)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Обыскать"
		prompt.ObjectText = "Рюкзак"
		prompt.HoldDuration = GameConfig.Match.SearchHoldTime
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = bag

		table.insert(result.Searchables, {
			Model = deskModel,
			Bag = bag,
			Prompt = prompt,
			Position = base + Vector3.new(0, 3, 0),
			Searched = false,
			HasKey = false,
		})
	end

	for r = 0, H - 1 do
		for c = 0, W - 1 do
			local ch = tile(c, r)
			if ch == "L" then
				buildLocker(c, r)
			elseif ch == "B" then
				buildSearchable(c, r)
			elseif ch == "P" then
				table.insert(result.SpawnPositions, center(c, r, 3.5))
			elseif ch == "M" then
				result.MonsterSpawn = center(c, r, 0)
			end
		end
	end

	-- ---------- точки патруля ----------
	for _, room in MapData.Rooms do
		table.insert(result.PatrolNodes, center((room.c1 + room.c2) / 2, (room.r1 + room.r2) / 2, 0))
	end
	for r = 0, H - 1 do
		for c = 0, W - 1 do
			if tile(c, r) == "," and c % 5 == 0 and r % 5 == 0 then
				table.insert(result.PatrolNodes, center(c, r, 0))
			end
		end
	end

	model.Parent = Workspace
	return result
end

return MapBuilder
