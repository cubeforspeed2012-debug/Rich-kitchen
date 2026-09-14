--!nonstrict
-- Управление. ПК: Shift бег, C подкат, F фонарь, T крик.
-- Телефон: кнопки БЕГ / ПОДКАТ / ФОНАРЬ / КРИК справа внизу.
-- Бег бесконечный. Скорость ставится каждый кадр здесь, на клиенте.

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
local running = false          -- ПК: пока зажат Shift; телефон: тумблер
local sliding = false
local slideReadyAt = 0
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
	light.Angle = 62
	light.Range = 70
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

-- Подкат: рывок вперёд + персонаж ужимается, чтобы пролезть в щель
local function slide()
	local humanoid, root = character()
	if not humanoid or not root or sliding or os.clock() < slideReadyAt then
		return
	end
	if player:GetAttribute("Downed") or player:GetAttribute("Hidden") then
		return
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.05 then
		return
	end
	direction = direction.Unit

	sliding = true
	slideReadyAt = os.clock() + MOVE.SlideCooldown
	actionEvent:FireServer({ action = "slide" })
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
		sliding = false
		-- пока над головой потолок щели - остаёмся маленькими, иначе застрянем в стене
		task.spawn(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			for _ = 1, 20 do
				local currentHumanoid, currentRoot = character()
				if not currentHumanoid or not currentRoot or sliding then
					return
				end
				params.FilterDescendantsInstances = { player.Character }
				local blocked = workspace:Raycast(currentRoot.Position, Vector3.new(0, 4.5, 0), params)
				if not blocked then
					setHeight(currentHumanoid, 1)
					return
				end
				task.wait(0.2)
			end
		end)
	end)
end

local function shout()
	if os.clock() - lastShout < GameConfig.Noise.ShoutCooldown then
		return
	end
	lastShout = os.clock()
	actionEvent:FireServer({ action = "shout" })
end

-- ---------- кнопки для телефона ----------
local function buildTouchButtons()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HWC_Touch"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")

	local function button(text, position, color)
		local element = Instance.new("TextButton")
		element.Size = UDim2.fromOffset(84, 84)
		element.Position = position
		element.AnchorPoint = Vector2.new(1, 1)
		element.BackgroundColor3 = color
		element.BackgroundTransparency = 0.25
		element.BorderSizePixel = 0
		element.Text = text
		element.Font = Enum.Font.GothamBlack
		element.TextSize = 16
		element.TextColor3 = Color3.fromRGB(255, 255, 255)
		element.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = element
		return element
	end

	local runButton = button("БЕГ", UDim2.new(1, -30, 1, -150), Color3.fromRGB(50, 90, 140))
	local slideButton = button("ПОД-\nКАТ", UDim2.new(1, -130, 1, -110), Color3.fromRGB(150, 110, 30))
	local lightButton = button("ФО-\nНАРЬ", UDim2.new(1, -30, 1, -250), Color3.fromRGB(80, 80, 90))
	local shoutButton = button("КРИК", UDim2.new(1, -130, 1, -210), Color3.fromRGB(140, 40, 40))

	runButton.Activated:Connect(function()
		running = not running
		runButton.BackgroundTransparency = running and 0 or 0.25
	end)
	slideButton.Activated:Connect(slide)
	lightButton.Activated:Connect(toggleFlashlight)
	shoutButton.Activated:Connect(shout)
end

function Input.start(hudModule)
	hud = hudModule

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
			running = true
		elseif key == Enum.KeyCode.C or key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.ButtonB then
			slide()
		elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonY then
			toggleFlashlight()
		elseif key == Enum.KeyCode.T or key == Enum.KeyCode.ButtonX then
			shout()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			running = false
		end
	end)

	if UserInputService.TouchEnabled then
		buildTouchButtons()
	end

	player.CharacterAdded:Connect(function()
		sliding = false
		task.wait(0.6)
		attachFlashlight()
		actionEvent:FireServer({ action = "flashlight", value = flashlightOn })
	end)
	attachFlashlight()

	RunService.RenderStepped:Connect(function()
		local humanoid = character()
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		if player:GetAttribute("Downed") or player:GetAttribute("Hidden") then
			humanoid.WalkSpeed = 0
			return
		end

		if sliding then
			humanoid.WalkSpeed = 8
		else
			humanoid.WalkSpeed = running and MOVE.SprintSpeed or MOVE.WalkSpeed
		end

		local slideReady = math.clamp(1 - (slideReadyAt - os.clock()) / MOVE.SlideCooldown, 0, 1)
		hud.setMoveState(running and not sliding, flashlightOn, slideReady)
	end)
end

return Input
