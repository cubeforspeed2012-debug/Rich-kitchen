--!nonstrict
-- Строит огромный дом из текстовой схемы MapData.Grid. 1 символ = 6 стадов.
-- Стены, потолки, щели для подката, шкафы, мебель, ключи, дверь выхода.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Util = require(Shared:WaitForChild("Util"))

local MapData = require(script.Parent:WaitForChild("MapData"))

local T = MapData.TileSize
local WALL_H = GameConfig.Map.WallHeight
local SLIT_H = GameConfig.Map.SlitHeight

local COLORS = {
	Wall = Color3.fromRGB(122, 104, 86),
	WallDark = Color3.fromRGB(64, 52, 44),
	RoomFloor = Color3.fromRGB(118, 86, 58),
	CorridorFloor = Color3.fromRGB(74, 70, 66),
	HallFloor = Color3.fromRGB(150, 140, 126),
	Ceiling = Color3.fromRGB(44, 38, 34),
	Grass = Color3.fromRGB(52, 80, 40),
	Locker = Color3.fromRGB(70, 58, 46),
	LockerDoor = Color3.fromRGB(96, 78, 60),
	Lintel = Color3.fromRGB(58, 40, 30),
	Lamp = Color3.fromRGB(255, 225, 180),
	SlitFrame = Color3.fromRGB(200, 170, 70),
	Table = Color3.fromRGB(100, 70, 44),
	Bed = Color3.fromRGB(150, 150, 165),
	Shelf = Color3.fromRGB(84, 58, 38),
	Crate = Color3.fromRGB(120, 92, 56),
	Key = Color3.fromRGB(255, 214, 90),
}

-- по чему ходят (получают пол и потолок)
local INTERIOR = {}
for ch in string.gmatch(".,DVPMKLtbsc", ".") do
	INTERIOR[ch] = true
end
local WALLISH = { ["#"] = true, ["V"] = true }

local MapBuilder = {}

function MapBuilder.build(origin, index)
	local model = Instance.new("Model")
	model.Name = "HWC_Arena_" .. tostring(index)

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

	local function runCenter(c1, c2, r, y)
		return origin + Vector3.new(((c1 + c2) / 2 - W / 2 + 0.5) * T, y or 0, (r - H / 2 + 0.5) * T)
	end

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

	-- в какой комнате тайл (для цвета пола)
	local function roomOf(c, r)
		for _, room in MapData.Rooms do
			if c >= room.c1 and c <= room.c2 and r >= room.r1 and r <= room.r2 then
				return room
			end
		end
		return nil
	end

	local result = {
		Model = model,
		Origin = origin,
		Index = index,
		Lights = {},
		Lockers = {},
		KeySpots = {},
		SpawnPositions = {},
		MonsterSpawn = origin,
		PatrolNodes = {},
		ExitDoor = nil,
		ExitPad = nil,
	}

	-- ---------- земля ----------
	Util.makePart(model, "Grass", Vector3.new(W * T + 60, 2, H * T + 60), origin + Vector3.new(0, -1, 0), COLORS.Grass, Enum.Material.Grass)

	-- ---------- пол ----------
	forRuns(function(ch, c, r)
		if not INTERIOR[ch] then
			return nil
		end
		if ch == "," or ch == "D" or ch == "V" then
			return "corridor"
		end
		local room = roomOf(c, r)
		return room and room.name == "Холл" and "hall" or "room"
	end, function(class, c1, c2, r)
		local color, material = COLORS.RoomFloor, Enum.Material.WoodPlanks
		if class == "corridor" then
			color, material = COLORS.CorridorFloor, Enum.Material.Cobblestone
		elseif class == "hall" then
			color, material = COLORS.HallFloor, Enum.Material.Marble
		end
		Util.makePart(model, "Floor", Vector3.new((c2 - c1 + 1) * T, 1.4, T), runCenter(c1, c2, r, -0.5), color, material)
	end)

	-- ---------- потолок ----------
	forRuns(function(ch)
		return INTERIOR[ch] and "ceil" or nil
	end, function(_, c1, c2, r)
		Util.makePart(model, "Ceiling", Vector3.new((c2 - c1 + 1) * T, 1, T), runCenter(c1, c2, r, WALL_H + 0.5), COLORS.Ceiling, Enum.Material.Wood)
	end)

	-- ---------- стены ----------
	forRuns(function(ch)
		return ch == "#" and "wall" or nil
	end, function(_, c1, c2, r)
		Util.makePart(model, "Wall", Vector3.new((c2 - c1 + 1) * T, WALL_H, T), runCenter(c1, c2, r, WALL_H / 2), COLORS.Wall, Enum.Material.Concrete)
	end)

	-- тёмный плинтус вдоль стен внутри - дешёвая "текстура", читается объём
	forRuns(function(ch)
		return ch == "#" and "skirt" or nil
	end, function(_, c1, c2, r)
		local skirt = Util.makePart(model, "Skirt", Vector3.new((c2 - c1 + 1) * T + 0.4, 1.2, T + 0.4), runCenter(c1, c2, r, 0.6), COLORS.WallDark, Enum.Material.Wood)
		skirt.CanCollide = false
	end)

	-- ---------- щели: снизу дыра, сверху стена, для киллера - запрет пути ----------
	for r = 0, H - 1 do
		for c = 0, W - 1 do
			if tile(c, r) == "V" then
				local topHeight = WALL_H - SLIT_H
				Util.makePart(model, "SlitTop", Vector3.new(T, topHeight, T), center(c, r, SLIT_H + topHeight / 2), COLORS.Wall, Enum.Material.Concrete)
				local frame = Util.makePart(model, "SlitFrame", Vector3.new(T + 0.3, 0.35, T + 0.3), center(c, r, SLIT_H), COLORS.SlitFrame, Enum.Material.Neon)
				frame.CanCollide = false
				local glow = Instance.new("PointLight")
				glow.Color = COLORS.SlitFrame
				glow.Range = 10
				glow.Brightness = 0.8
				glow.Parent = frame

				local blocker = Util.makePart(model, "SlitBlock", Vector3.new(T + 1, SLIT_H, T + 1), center(c, r, SLIT_H / 2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
				blocker.Transparency = 1
				blocker.CanCollide = false
				blocker.CanQuery = false
				local modifier = Instance.new("PathfindingModifier")
				modifier.Label = "Slit"
				modifier.Parent = blocker
			end
		end
	end

	-- ---------- перемычки над дверями ----------
	for r = 0, H - 1 do
		for c = 0, W - 1 do
			if tile(c, r) == "D" then
				Util.makePart(model, "Lintel", Vector3.new(T, 4, T), center(c, r, WALL_H - 2), COLORS.Lintel, Enum.Material.Wood)
			end
		end
	end

	-- ---------- лампы ----------
	for r = 0, H - 1 do
		for c = 0, W - 1 do
			if INTERIOR[tile(c, r)] and c % 4 == 2 and r % 4 == 2 then
				local lamp = Util.makePart(model, "Lamp", Vector3.new(3, 0.4, 3), center(c, r, WALL_H - 0.5), COLORS.Lamp, Enum.Material.Neon)
				local light = Instance.new("PointLight")
				light.Range = 40
				light.Brightness = 1
				light.Color = Color3.fromRGB(255, 220, 170)
				light.Shadows = false
				light.Parent = lamp
				table.insert(result.Lights, { Part = lamp, Light = light, Position = lamp.Position })
			end
		end
	end

	-- ---------- дверь выхода ----------
	forRuns(function(ch)
		return ch == "X" and "exit" or nil
	end, function(_, c1, c2, r)
		local width = (c2 - c1 + 1) * T
		Util.makePart(model, "ExitTop", Vector3.new(width, WALL_H - 14, T), runCenter(c1, c2, r, 14 + (WALL_H - 14) / 2), COLORS.Wall, Enum.Material.Concrete)
		local door = Util.makePart(model, "ExitDoor", Vector3.new(width, 14, T), runCenter(c1, c2, r, 7), Color3.fromRGB(130, 32, 32), Enum.Material.Metal)
		door:SetAttribute("Locked", true)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 60, 60)
		light.Range = 26
		light.Brightness = 2
		light.Parent = door
		result.ExitDoor = door

		Util.makePart(model, "ExitFloor", Vector3.new(width + 12, 1.4, T), runCenter(c1, c2, r, -0.5), COLORS.CorridorFloor, Enum.Material.Cobblestone)
		local pad = Util.makePart(model, "ExitPad", Vector3.new(width + 8, 0.5, T * 1.5), runCenter(c1, c2, r + 1, 0.3), Color3.fromRGB(60, 210, 130), Enum.Material.Neon)
		pad.Transparency = 0.4
		result.ExitPad = pad
	end)

	-- ---------- шкафы ----------
	local function buildLocker(c, r)
		local base = center(c, r, 0)
		local facing = Vector3.new(0, 0, 1)
		if WALLISH[tile(c, r - 1)] then
			facing = Vector3.new(0, 0, 1)
		elseif WALLISH[tile(c, r + 1)] then
			facing = Vector3.new(0, 0, -1)
		elseif WALLISH[tile(c - 1, r)] then
			facing = Vector3.new(1, 0, 0)
		elseif WALLISH[tile(c + 1, r)] then
			facing = Vector3.new(-1, 0, 0)
		end
		local side = Vector3.new(facing.Z, 0, facing.X)
		local lockerModel = Instance.new("Model")
		lockerModel.Name = "Locker"
		lockerModel.Parent = model

		local width, height, depth = 4.4, 9, 3.6
		local function oriented(w, d, h)
			return Vector3.new(math.abs(side.X) * w + math.abs(facing.X) * d, h, math.abs(side.Z) * w + math.abs(facing.Z) * d)
		end
		local function panel(name, size, offset, color)
			return Util.makePart(lockerModel, name, size, base + offset, color, Enum.Material.Wood)
		end
		panel("Back", oriented(width, 0.4, height), Vector3.new(0, height / 2, 0) - facing * (depth / 2), COLORS.Locker)
		panel("SideA", oriented(0.4, depth, height), Vector3.new(0, height / 2, 0) + side * (width / 2), COLORS.Locker)
		panel("SideB", oriented(0.4, depth, height), Vector3.new(0, height / 2, 0) - side * (width / 2), COLORS.Locker)
		panel("Top", oriented(width + 0.4, depth + 0.4, 0.4), Vector3.new(0, height, 0), COLORS.Locker)
		local door = panel("Door", oriented(width, 0.4, height), Vector3.new(0, height / 2, 0) + facing * (depth / 2), COLORS.LockerDoor)
		door.Transparency = 0.3

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Спрятаться"
		prompt.ObjectText = "Шкаф"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = door

		table.insert(result.Lockers, {
			Model = lockerModel,
			Door = door,
			Prompt = prompt,
			Inside = base + Vector3.new(0, 3.2, 0),
			Outside = base + facing * (T * 0.8) + Vector3.new(0, 3.2, 0),
			Occupant = nil,
		})
	end

	-- ---------- мебель ----------
	local function buildFurniture(ch, c, r)
		local base = center(c, r, 0)
		local group = Instance.new("Model")
		group.Name = "Furniture"
		group.Parent = model
		if ch == "t" then
			Util.makePart(group, "TableTop", Vector3.new(5.5, 0.4, 3.2), base + Vector3.new(0, 2.8, 0), COLORS.Table, Enum.Material.Wood)
			for _, offset in { Vector3.new(-2.4, 1.4, -1.3), Vector3.new(2.4, 1.4, -1.3), Vector3.new(-2.4, 1.4, 1.3), Vector3.new(2.4, 1.4, 1.3) } do
				Util.makePart(group, "Leg", Vector3.new(0.4, 2.8, 0.4), base + offset, COLORS.WallDark, Enum.Material.Wood)
			end
		elseif ch == "b" then
			Util.makePart(group, "BedFrame", Vector3.new(4.2, 1.2, 7), base + Vector3.new(0, 0.6, 0), COLORS.WallDark, Enum.Material.Wood)
			Util.makePart(group, "Mattress", Vector3.new(4, 0.8, 6.6), base + Vector3.new(0, 1.6, 0), COLORS.Bed, Enum.Material.Fabric)
			Util.makePart(group, "Pillow", Vector3.new(3, 0.6, 1.4), base + Vector3.new(0, 2.3, -2.4), Color3.fromRGB(200, 200, 210), Enum.Material.Fabric)
		elseif ch == "s" then
			Util.makePart(group, "Shelf", Vector3.new(5, 9, 1.6), base + Vector3.new(0, 4.5, 0), COLORS.Shelf, Enum.Material.Wood)
			for i = 1, 3 do
				local books = Util.makePart(group, "Books", Vector3.new(4.4, 1.4, 0.6), base + Vector3.new(0, i * 2.4, 0.9), Color3.fromRGB(60 + i * 40, 40, 30 + i * 20), Enum.Material.Fabric)
				books.CanCollide = false
			end
		elseif ch == "c" then
			local crate = Util.makePart(group, "Crate", Vector3.new(3.6, 3.6, 3.6), base + Vector3.new(0, 1.8, 0), COLORS.Crate, Enum.Material.WoodPlanks)
			crate.Orientation = Vector3.new(0, math.random(0, 90), 0)
		end
	end

	-- ---------- места под ключи ----------
	local function buildKeySpot(c, r)
		local base = center(c, r, 0)
		local pedestal = Util.makePart(model, "Pedestal", Vector3.new(2.6, 3.4, 2.6), base + Vector3.new(0, 1.7, 0), COLORS.WallDark, Enum.Material.Slate)
		table.insert(result.KeySpots, { Position = base + Vector3.new(0, 4.6, 0), Pedestal = pedestal })
	end

	for r = 0, H - 1 do
		for c = 0, W - 1 do
			local ch = tile(c, r)
			if ch == "L" then
				buildLocker(c, r)
			elseif ch == "K" then
				buildKeySpot(c, r)
			elseif ch == "t" or ch == "b" or ch == "s" or ch == "c" then
				buildFurniture(ch, c, r)
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
			if tile(c, r) == "," and c % 6 == 1 and r % 6 == 3 then
				table.insert(result.PatrolNodes, center(c, r, 0))
			end
		end
	end

	model.Parent = Workspace
	return result
end

return MapBuilder
