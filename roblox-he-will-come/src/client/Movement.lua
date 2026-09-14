--!nonstrict
-- Бег, приседание и фонарь. Всё это - про громкость.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MOVE = GameConfig.Movement

local player = Players.LocalPlayer
local crouchEvent = Remotes.get("Crouch")
local flashlightEvent = Remotes.get("Flashlight")

local Movement = {}

local hud
local stamina = MOVE.MaxStamina
local sprinting = false
local crouching = false
local flashlightOn = false
local flashlight: SpotLight? = nil
local lastDrainAt = 0
local blocked = false -- паника: бежать нельзя

local function getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function setCrouchVisual(humanoid: Humanoid, value: boolean)
	local scale = humanoid:FindFirstChild("BodyHeightScale")
	if scale and scale:IsA("NumberValue") then
		scale.Value = value and 0.65 or 1
	end
end

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
	light.Angle = 65
	light.Range = 55
	light.Brightness = 2.6
	light.Face = Enum.NormalId.Front
	light.Enabled = flashlightOn
	light.Parent = head
	flashlight = light
end

local function onSprint(_, state)
	sprinting = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Pass
end

local function onCrouch(_, state)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	crouching = not crouching
	local humanoid = getHumanoid()
	if humanoid then
		setCrouchVisual(humanoid, crouching)
	end
	crouchEvent:FireServer(crouching)
	return Enum.ContextActionResult.Pass
end

local function onFlashlight(_, state)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	flashlightOn = not flashlightOn
	if flashlight and flashlight.Parent then
		flashlight.Enabled = flashlightOn
	else
		attachFlashlight()
	end
	flashlightEvent:FireServer(flashlightOn)
	return Enum.ContextActionResult.Pass
end

function Movement.setBlocked(value: boolean)
	blocked = value
end

function Movement.start(hudModule)
	hud = hudModule

	ContextActionService:BindAction("HWCSprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
	ContextActionService:BindAction("HWCCrouch", onCrouch, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl)
	ContextActionService:BindAction("HWCLight", onFlashlight, true, Enum.KeyCode.F)
	ContextActionService:SetTitle("HWCSprint", "Бег")
	ContextActionService:SetTitle("HWCCrouch", "Красться")
	ContextActionService:SetTitle("HWCLight", "Фонарь")

	player.CharacterAdded:Connect(function()
		stamina = MOVE.MaxStamina
		crouching = false
		sprinting = false
		task.wait(0.6)
		attachFlashlight()
		crouchEvent:FireServer(false)
		flashlightEvent:FireServer(flashlightOn)
	end)
	attachFlashlight()

	RunService.RenderStepped:Connect(function(dt)
		local humanoid = getHumanoid()
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		-- когда лежишь, сервер держит скорость в нуле - не мешаем
		if humanoid.WalkSpeed == 0 then
			hud.setStamina(stamina, MOVE.MaxStamina)
			return
		end

		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local canSprint = sprinting and moving and not crouching and not blocked and stamina > MOVE.MinSprintStamina

		if canSprint then
			stamina = math.max(0, stamina - MOVE.SprintDrain * dt)
			lastDrainAt = os.clock()
			humanoid.WalkSpeed = MOVE.SprintSpeed
		else
			humanoid.WalkSpeed = crouching and MOVE.CrouchSpeed or MOVE.WalkSpeed
			if os.clock() - lastDrainAt > MOVE.RegenDelay then
				stamina = math.min(MOVE.MaxStamina, stamina + MOVE.StaminaRegen * dt)
			end
		end

		hud.setStamina(stamina, MOVE.MaxStamina)
	end)
end

return Movement
