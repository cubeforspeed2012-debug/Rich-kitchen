--!nonstrict
-- Бег с выносливостью и ПОДКАТ: персонаж ужимается и проскальзывает
-- в низкий лаз, куда монстр не пролезет (ему придётся бежать в обход).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("LocustShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MOVE = GameConfig.Movement
local SLIDE = GameConfig.Slide

local player = Players.LocalPlayer
local slideEvent = Remotes.get("Slide")

local MovementController = {}

local hud
local stamina = MOVE.MaxStamina
local sprinting = false
local sliding = false
local lastDrainAt = 0
local slideReadyAt = 0

local function getCharacter(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, root
end

local function setHeightScale(humanoid: Humanoid, value: number)
	local scale = humanoid:FindFirstChild("BodyHeightScale")
	if scale and scale:IsA("NumberValue") then
		scale.Value = value
	end
end

local function doSlide()
	if sliding or os.clock() < slideReadyAt then
		return
	end
	local character, humanoid, root = getCharacter()
	if not character or not humanoid or not root then
		return
	end
	if humanoid.Health <= 0 or stamina < SLIDE.StaminaCost then
		return
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		return
	end

	sliding = true
	stamina -= SLIDE.StaminaCost
	slideReadyAt = os.clock() + SLIDE.Cooldown
	slideEvent:FireServer()

	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit

	local originalScale = 1
	local scaleValue = humanoid:FindFirstChild("BodyHeightScale")
	if scaleValue and scaleValue:IsA("NumberValue") then
		originalScale = scaleValue.Value
	end
	setHeightScale(humanoid, SLIDE.HeightScale)

	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 4

	local attachment = Instance.new("Attachment")
	attachment.Name = "SlideAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	velocity.LineDirection = direction
	velocity.LineVelocity = SLIDE.Speed
	velocity.Parent = root

	task.delay(SLIDE.Duration, function()
		velocity:Destroy()
		attachment:Destroy()
		local _, currentHumanoid = getCharacter()
		if currentHumanoid then
			setHeightScale(currentHumanoid, originalScale)
			currentHumanoid.WalkSpeed = sprinting and MOVE.SprintSpeed or originalSpeed
		end
		sliding = false
	end)
end

local function onSprintAction(_, state: Enum.UserInputState)
	sprinting = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Pass
end

local function onSlideAction(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		doSlide()
	end
	return Enum.ContextActionResult.Pass
end

function MovementController.start(hudModule)
	hud = hudModule

	ContextActionService:BindAction("LocustSprint", onSprintAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
	ContextActionService:BindAction("LocustSlide", onSlideAction, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl)
	ContextActionService:SetTitle("LocustSprint", "Бег")
	ContextActionService:SetTitle("LocustSlide", "Подкат")

	player.CharacterAdded:Connect(function()
		stamina = MOVE.MaxStamina
		sliding = false
		sprinting = false
	end)

	RunService.RenderStepped:Connect(function(dt)
		local _, humanoid = getCharacter()
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local wantsSprint = sprinting and moving and not sliding and stamina > MOVE.MinSprintStamina

		if wantsSprint then
			stamina = math.max(0, stamina - MOVE.SprintDrain * dt)
			lastDrainAt = os.clock()
			humanoid.WalkSpeed = MOVE.SprintSpeed
		elseif not sliding then
			humanoid.WalkSpeed = MOVE.WalkSpeed
			if os.clock() - lastDrainAt > MOVE.RegenDelay then
				stamina = math.min(MOVE.MaxStamina, stamina + MOVE.StaminaRegen * dt)
			end
		end

		hud.setStamina(stamina, MOVE.MaxStamina)
	end)
end

return MovementController
