--!nonstrict
-- Экраны испуга, тряска, сердцебиение-виньетка, темнота при приближении.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local Effects = {}

local correction = Instance.new("ColorCorrectionEffect")
correction.Name = "HWC_Correction"
correction.Saturation = -0.25
correction.Parent = Lighting

local gui = Instance.new("ScreenGui")
gui.Name = "HWC_Effects"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local vignette = Instance.new("Frame")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundColor3 = Color3.fromRGB(110, 0, 0)
vignette.BackgroundTransparency = 1
vignette.BorderSizePixel = 0
vignette.Parent = gui

local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.ZIndex = 2
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
overlayText.ZIndex = 3
overlayText.Parent = gui

local shakeUntil = 0
local shakeStrength = 0
local pulse = 0

function Effects.shake(duration, strength)
	shakeUntil = os.clock() + duration
	shakeStrength = strength
end

local function flash(color, str, holdTime, alpha)
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = alpha or 0.15
	overlayText.Text = str
	overlayText.TextTransparency = 0
	task.delay(holdTime, function()
		TweenService:Create(overlay, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(overlayText, TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
	end)
end

function Effects.play(kind, data)
	if kind == "arrival" then
		flash(Color3.new(0, 0, 0), "ОН ПРОСНУЛСЯ", 1.3)
		Effects.shake(1.5, 1.4)
	elseif kind == "scream" then
		flash(Color3.fromRGB(70, 0, 0), "", 0.4, 0.55)
		Effects.shake(1.2, 2.4)
	elseif kind == "down" then
		flash(Color3.fromRGB(80, 0, 0), "ОН ТЕБЯ ДОСТАЛ", 1.2)
		Effects.shake(1.4, 2.8)
	elseif kind == "revived" then
		flash(Color3.fromRGB(0, 60, 30), "ТЫ СНОВА НА НОГАХ", 0.7)
	elseif kind == "out" then
		flash(Color3.new(0, 0, 0), "ОН ЗАБРАЛ ТЕБЯ", 2)
	elseif kind == "escaped" then
		flash(Color3.fromRGB(0, 40, 20), "ТЫ ВЫБРАЛСЯ", 1.5)
	elseif kind == "key" then
		flash(Color3.fromRGB(60, 50, 0), "КЛЮЧ!", 0.4, 0.7)
	elseif kind == "shout" then
		Effects.shake(0.4, 0.8)
	end
end

-- чем ближе он, тем краснее края и сильнее "пульс"
function Effects.setDistance(distance, hunted)
	local danger = math.clamp(1 - distance / 50, 0, 1)
	if hunted then
		danger = math.max(danger, 0.6)
	end
	pulse = danger
	correction.Contrast = danger * 0.2
	correction.TintColor = Color3.fromRGB(255, 255 - math.floor(35 * danger), 255 - math.floor(45 * danger))
end

function Effects.reset()
	pulse = 0
	correction.Contrast = 0
	correction.TintColor = Color3.new(1, 1, 1)
	vignette.BackgroundTransparency = 1
end

function Effects.start()
	RunService:BindToRenderStep("HWC_Shake", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		if os.clock() < shakeUntil then
			camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * shakeStrength, (math.random() - 0.5) * shakeStrength, 0)
		end
		if pulse > 0 then
			local beat = (math.sin(os.clock() * (4 + pulse * 6)) + 1) / 2
			vignette.BackgroundTransparency = 1 - pulse * (0.25 + beat * 0.25)
		end
	end)
end

return Effects
