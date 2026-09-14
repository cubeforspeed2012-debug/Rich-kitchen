--!nonstrict
-- Подколка (T), приманка (Q) и фонарик (F).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("LocustShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local RAGE = GameConfig.Rage
local BAIT = GameConfig.Bait

local player = Players.LocalPlayer
local tauntEvent = Remotes.get("Taunt")
local baitEvent = Remotes.get("ThrowBait")

local ActionController = {}

local nextTaunt = 0
local nextBait = 0
local flashlightOn = false
local flashlight: SpotLight? = nil

local function attachFlashlight()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	if flashlight and flashlight.Parent then
		flashlight:Destroy()
	end
	local light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Angle = 70
	light.Range = 48
	light.Brightness = 2.5
	light.Face = Enum.NormalId.Front
	light.Enabled = flashlightOn
	light.Parent = head
	flashlight = light
end

local function onTaunt(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if os.clock() < nextTaunt then
		return Enum.ContextActionResult.Pass
	end
	nextTaunt = os.clock() + RAGE.TauntCooldown
	tauntEvent:FireServer()
	return Enum.ContextActionResult.Pass
end

local function onBait(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if os.clock() < nextBait then
		return Enum.ContextActionResult.Pass
	end
	nextBait = os.clock() + BAIT.Cooldown
	local camera = Workspace.CurrentCamera
	local direction = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
	baitEvent:FireServer(direction)
	return Enum.ContextActionResult.Pass
end

local function onFlashlight(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	flashlightOn = not flashlightOn
	if flashlight and flashlight.Parent then
		flashlight.Enabled = flashlightOn
	else
		attachFlashlight()
	end
	return Enum.ContextActionResult.Pass
end

function ActionController.start()
	ContextActionService:BindAction("LocustTaunt", onTaunt, true, Enum.KeyCode.T)
	ContextActionService:BindAction("LocustBait", onBait, true, Enum.KeyCode.Q)
	ContextActionService:BindAction("LocustLight", onFlashlight, true, Enum.KeyCode.F)
	ContextActionService:SetTitle("LocustTaunt", "Дразнить")
	ContextActionService:SetTitle("LocustBait", "Приманка")
	ContextActionService:SetTitle("LocustLight", "Фонарь")

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		attachFlashlight()
	end)
	attachFlashlight()
end

return ActionController
