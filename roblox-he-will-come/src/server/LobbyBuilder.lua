--!nonstrict
-- Лобби: светлая площадка, откуда создают комнаты.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local Util = require(Shared:WaitForChild("Util"))

local LobbyBuilder = {}

function LobbyBuilder.build(center)
	local old = Workspace:FindFirstChild("HWC_Lobby")
	if old then
		old:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "HWC_Lobby"

	local function pos(x, y, z)
		return center + Vector3.new(x, y, z)
	end

	local floorColor = Color3.fromRGB(44, 46, 52)
	local wallColor = Color3.fromRGB(70, 72, 80)

	Util.makePart(model, "Floor", Vector3.new(160, 2, 160), pos(0, -1, 0), floorColor, Enum.Material.Slate)
	Util.makePart(model, "Wall", Vector3.new(160, 22, 2), pos(0, 11, -80), wallColor, Enum.Material.Brick)
	Util.makePart(model, "Wall", Vector3.new(160, 22, 2), pos(0, 11, 80), wallColor, Enum.Material.Brick)
	Util.makePart(model, "Wall", Vector3.new(2, 22, 160), pos(-80, 11, 0), wallColor, Enum.Material.Brick)
	Util.makePart(model, "Wall", Vector3.new(2, 22, 160), pos(80, 11, 0), wallColor, Enum.Material.Brick)
	Util.makePart(model, "Ceiling", Vector3.new(160, 2, 160), pos(0, 23, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Concrete)

	for _, offset in { Vector3.new(-40, 0, -40), Vector3.new(40, 0, -40), Vector3.new(-40, 0, 40), Vector3.new(40, 0, 40), Vector3.zero } do
		local lamp = Util.makePart(model, "Lamp", Vector3.new(8, 0.5, 8), pos(offset.X, 21.5, offset.Z), Color3.fromRGB(255, 245, 225), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Range = 60
		light.Brightness = 2
		light.Parent = lamp
	end

	local sign = Util.makePart(model, "Sign", Vector3.new(70, 14, 1), pos(0, 13, -78), Color3.fromRGB(10, 10, 12), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(1400, 280)
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

	model.Parent = Workspace

	return {
		Model = model,
		Spawn = spawn,
		SpawnPosition = pos(0, 4, 30),
	}
end

return LobbyBuilder
