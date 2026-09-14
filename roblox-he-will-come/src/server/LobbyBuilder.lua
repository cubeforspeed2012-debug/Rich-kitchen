--!nonstrict
-- Лобби: сюда попадают все при входе, отсюда создают и выбирают комнаты.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local Util = require(Shared:WaitForChild("Util"))

local LobbyBuilder = {}

local FLOOR_COLOR = Color3.fromRGB(30, 30, 36)
local WALL_COLOR = Color3.fromRGB(48, 48, 58)

function LobbyBuilder.build(center: Vector3)
	local old = Workspace:FindFirstChild("HWC_Lobby")
	if old then
		old:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "HWC_Lobby"
	model.Parent = Workspace

	local function pos(x: number, y: number, z: number): Vector3
		return center + Vector3.new(x, y, z)
	end

	Util.makePart(model, "Floor", Vector3.new(180, 2, 180), pos(0, -1, 0), FLOOR_COLOR, Enum.Material.Concrete)

	-- стены по периметру
	Util.makePart(model, "Wall", Vector3.new(180, 24, 2), pos(0, 12, -90), WALL_COLOR, Enum.Material.Concrete)
	Util.makePart(model, "Wall", Vector3.new(180, 24, 2), pos(0, 12, 90), WALL_COLOR, Enum.Material.Concrete)
	Util.makePart(model, "Wall", Vector3.new(2, 24, 180), pos(-90, 12, 0), WALL_COLOR, Enum.Material.Concrete)
	Util.makePart(model, "Wall", Vector3.new(2, 24, 180), pos(90, 12, 0), WALL_COLOR, Enum.Material.Concrete)
	Util.makePart(model, "Ceiling", Vector3.new(180, 2, 180), pos(0, 25, 0), WALL_COLOR, Enum.Material.Concrete)

	-- лампы, чтобы в лобби было светло и спокойно
	for _, offset in { Vector3.new(-45, 0, -45), Vector3.new(45, 0, -45), Vector3.new(-45, 0, 45), Vector3.new(45, 0, 45), Vector3.zero } do
		local lamp = Util.makePart(
			model,
			"Lamp",
			Vector3.new(8, 0.6, 8),
			pos(offset.X, 23, offset.Z),
			Color3.fromRGB(255, 245, 220),
			Enum.Material.Neon
		)
		local light = Instance.new("PointLight")
		light.Range = 60
		light.Brightness = 2.4
		light.Color = Color3.fromRGB(255, 240, 215)
		light.Parent = lamp
	end

	-- вывеска
	local sign = Util.makePart(model, "Sign", Vector3.new(60, 12, 1), pos(0, 14, -88), Color3.fromRGB(12, 12, 14), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(1200, 240)
	gui.Parent = sign

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Text = "HE WILL COME"
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(220, 40, 40)
	title.Parent = gui

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(24, 1, 24)
	spawn.Position = pos(0, 0.5, 30)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(60, 90, 140)
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.5
	spawn.Parent = model

	return {
		Model = model,
		SpawnPosition = pos(0, 4, 30),
		Spawn = spawn,
	}
end

return LobbyBuilder
