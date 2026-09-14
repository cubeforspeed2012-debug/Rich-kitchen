--!nonstrict
-- Тряска, размытие от потери рассудка и экраны испуга.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local Effects = {}

local blur = Instance.new("BlurEffect")
blur.Name = "HWC_Blur"
blur.Size = 0
blur.Parent = Lighting

local correction = Instance.new("ColorCorrectionEffect")
correction.Name = "HWC_Correction"
correction.Saturation = -0.2
correction.Parent = Lighting

local gui = Instance.new("ScreenGui")
gui.Name = "HWC_Effects"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Parent = gui

local overlayText = Instance.new("TextLabel")
overlayText.Size = UDim2.fromScale(1, 0.2)
overlayText.Position = UDim2.fromScale(0, 0.4)
overlayText.BackgroundTransparency = 1
overlayText.Text = ""
overlayText.TextScaled = true
overlayText.Font = Enum.Font.GothamBlack
overlayText.TextColor3 = Color3.fromRGB(230, 230, 235)
overlayText.TextTransparency = 1
overlayText.Parent = gui

local shakeUntil = 0
local shakeStrength = 0

function Effects.shake(duration: number, strength: number)
	shakeUntil = os.clock() + duration
	shakeStrength = strength
end

local function flash(color: Color3, text: string, holdTime: number)
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = 0.15
	overlayText.Text = text
	overlayText.TextTransparency = 0

	task.delay(holdTime, function()
		TweenService:Create(overlay, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(overlayText, TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
	end)
end

function Effects.scare(kind: string)
	if kind == "arrival" then
		flash(Color3.new(0, 0, 0), "ОН ПРИШЁЛ", 1.4)
		Effects.shake(1.6, 1.6)
	elseif kind == "down" then
		flash(Color3.fromRGB(80, 0, 0), "ОН ТЕБЯ ДОСТАЛ", 1.2)
		Effects.shake(1.4, 2.6)
	elseif kind == "panic" then
		flash(Color3.fromRGB(40, 0, 40), "ТЫ СОРВАЛСЯ", 0.9)
		Effects.shake(2.2, 2.2)
	elseif kind == "revived" then
		flash(Color3.fromRGB(0, 60, 30), "ТЫ СНОВА НА НОГАХ", 0.7)
	elseif kind == "out" then
		flash(Color3.new(0, 0, 0), "ОН ЗАБРАЛ ТЕБЯ", 2)
	end
end

-- Чем меньше рассудка, тем сильнее плывёт картинка.
function Effects.setSanity(value: number, max: number)
	local lost = 1 - math.clamp(value / max, 0, 1)
	blur.Size = lost * 14
	correction.Contrast = lost * 0.3
	correction.TintColor = Color3.fromRGB(255, 255 - math.floor(40 * lost), 255 - math.floor(60 * lost))
	if lost > 0.55 then
		Effects.shake(0.2, lost * 0.6)
	end
end

function Effects.reset()
	blur.Size = 0
	correction.Contrast = 0
	correction.TintColor = Color3.new(1, 1, 1)
end

function Effects.start()
	RunService:BindToRenderStep("HWC_Shake", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = Workspace.CurrentCamera
		if not camera or os.clock() >= shakeUntil then
			return
		end
		local offset = Vector3.new(
			(math.random() - 0.5) * shakeStrength,
			(math.random() - 0.5) * shakeStrength,
			0
		)
		camera.CFrame = camera.CFrame * CFrame.new(offset)
	end)
end

return Effects
