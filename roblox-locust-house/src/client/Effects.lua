--!nonstrict
-- Скример, тряска камеры и цветокоррекция при ярости.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Effects = {}

local player = Players.LocalPlayer

local correction = Instance.new("ColorCorrectionEffect")
correction.Name = "LocustCorrection"
correction.TintColor = Color3.fromRGB(255, 255, 255)
correction.Saturation = -0.15
correction.Parent = Lighting

local shakeUntil = 0
local shakeStrength = 0

function Effects.setRage(rage: number)
	local intensity = math.clamp(rage / 100, 0, 1)
	correction.TintColor = Color3.fromRGB(255, 255 - math.floor(70 * intensity), 255 - math.floor(90 * intensity))
	correction.Contrast = intensity * 0.25
end

function Effects.shake(duration: number, strength: number)
	shakeUntil = os.clock() + duration
	shakeStrength = strength
end

function Effects.jumpscare(gui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(90, 0, 0)
	frame.BackgroundTransparency = 0.15
	frame.ZIndex = 50
	frame.Parent = gui

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 0.3)
	text.Position = UDim2.fromScale(0, 0.35)
	text.BackgroundTransparency = 1
	text.Text = "ПОПАЛСЯ"
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = Color3.fromRGB(255, 240, 240)
	text.ZIndex = 51
	text.Parent = frame

	Effects.shake(1.2, 2.5)

	task.delay(1.1, function()
		TweenService:Create(frame, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(text, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.wait(0.9)
		frame:Destroy()
	end)
end

function Effects.start()
	-- Приоритет выше камеры, иначе стандартный скрипт камеры затрёт тряску.
	RunService:BindToRenderStep("LocustShake", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		if os.clock() < shakeUntil then
			local offset = Vector3.new(
				(math.random() - 0.5) * shakeStrength,
				(math.random() - 0.5) * shakeStrength,
				0
			)
			camera.CFrame = camera.CFrame * CFrame.new(offset)
		end
	end)

	player.CharacterAdded:Connect(function()
		correction.TintColor = Color3.fromRGB(255, 255, 255)
	end)
end

return Effects
