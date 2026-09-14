--!nonstrict
-- Управление: Shift бег, C присесть, Shift+C подкат, F фонарь, T крик.
-- Скорость ставится каждый кадр здесь, на клиенте, - это гарантирует, что бег работает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MOVE = GameConfig.Movement

local player = Players.LocalPlayer
local actionEvent = Remotes.get("PlayerAction")

local Input = {}

local hud
local stamina = MOVE.MaxStamina
local sprintHeld = false
local crouching = false
local sliding = false
local slideReadyAt = 0
local lastDrainAt = 0
local flashlightOn = false
local flashlight = nil
local lastShout = -100

local function character()
	local model = player.Character
	if not model then
		return nil, nil
	end
	return model:FindFirstChildOfClass("Humanoid"), model:FindFirstChild("HumanoidRootPart")
end

local function setHeight(humanoid, scale)
	local value = humanoid:FindFirstChild("BodyHeightScale")
	if value and value:IsA("NumberValue") then
		value.Value = scale
	end
end

local function attachFlashlight()
	local model = player.Character
	local head = model and model:FindFirstChild("Head")
	if not head then
		return
	end
	if flashlight and flashlight.Parent then
		flashlight:Destroy()
	end
	local light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Angle = 60
	light.Range = 60
	light.Brightness = 3
	light.Face = Enum.NormalId.Front
	light.Enabled = flashlightOn
	light.Parent = head
	flashlight = light
end

local function toggleFlashlight()
	flashlightOn = not flashlightOn
	if flashlight and flashlight.Parent then
		flashlight.Enabled = flashlightOn
	else
		attachFlashlight()
	end
	actionEvent:FireServer({ action = "flashlight", value = flashlightOn })
end

local function setCrouch(value)
	crouching = value
	local humanoid = character()
	if humanoid then
		setHeight(humanoid, crouching and 0.7 or 1)
	end
	actionEvent:FireServer({ action = "crouch", value = crouching })
end

local function slide()
	local humanoid, root = character()
	if not humanoid or not root or sliding or os.clock() < slideReadyAt then
		return
	end
	if humanoid.MoveDirection.Magnitude < 0.1 or stamina < MOVE.SlideStamina then
		return
	end
	sliding = true
	stamina -= MOVE.SlideStamina
	slideReadyAt = os.clock() + MOVE.SlideCooldown
	actionEvent:FireServer({ action = "slide" })

	local direction = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z).Unit
	setHeight(humanoid, MOVE.SlideHeightScale)

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	velocity.LineDirection = direction
	velocity.LineVelocity = MOVE.SlideSpeed
	velocity.Parent = root

	task.delay(MOVE.SlideDuration, function()
		velocity:Destroy()
		attachment:Destroy()
		local currentHumanoid = character()
		if currentHumanoid then
			setHeight(currentHumanoid, crouching and 0.7 or 1)
		end
		sliding = false
	end)
end

local function shout()
	if os.clock() - lastShout < GameConfig.Noise.ShoutCooldown then
		return
	end
	lastShout = os.clock()
	actionEvent:FireServer({ action = "shout" })
end

function Input.isSprinting()
	return sprintHeld
end

function Input.start(hudModule)
	hud = hudModule

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
			sprintHeld = true
		elseif key == Enum.KeyCode.C or key == Enum.KeyCode.LeftControl then
			local humanoid = character()
			if sprintHeld and humanoid and humanoid.WalkSpeed >= MOVE.SprintSpeed - 1 then
				slide()
			else
				setCrouch(not crouching)
			end
		elseif key == Enum.KeyCode.F then
			toggleFlashlight()
		elseif key == Enum.KeyCode.T then
			shout()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			sprintHeld = false
		end
	end)

	player.CharacterAdded:Connect(function()
		stamina = MOVE.MaxStamina
		sprintHeld = false
		sliding = false
		crouching = false
		task.wait(0.6)
		attachFlashlight()
		actionEvent:FireServer({ action = "crouch", value = false })
		actionEvent:FireServer({ action = "flashlight", value = flashlightOn })
	end)
	attachFlashlight()

	RunService.RenderStepped:Connect(function(dt)
		local humanoid = character()
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		-- лежишь или сидишь в шкафу - стоишь на месте
		if player:GetAttribute("Downed") or player:GetAttribute("Hidden") then
			humanoid.WalkSpeed = 0
			hud.setStamina(stamina, MOVE.MaxStamina)
			return
		end

		if sliding then
			humanoid.WalkSpeed = 6
			hud.setStamina(stamina, MOVE.MaxStamina)
			return
		end

		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local canSprint = sprintHeld and moving and not crouching and stamina > MOVE.MinSprintStamina

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
		hud.setMoveState(crouching, canSprint, flashlightOn)
	end)
end

return Input
