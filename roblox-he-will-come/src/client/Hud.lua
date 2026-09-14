--!nonstrict
-- HUD матча: фаза, предохранители, рассудок, шум, команда, статус "он идёт за тобой".

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Hud = {}

local COLORS = {
	good = Color3.fromRGB(90, 220, 140),
	bad = Color3.fromRGB(255, 85, 85),
	info = Color3.fromRGB(205, 210, 225),
}

local gui = Instance.new("ScreenGui")
gui.Name = "HWC_Hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent, text, size, position, textSize)
	local element = Instance.new("TextLabel")
	element.BackgroundTransparency = 1
	element.Size = size
	element.Position = position
	element.Text = text
	element.TextSize = textSize
	element.Font = Enum.Font.GothamBold
	element.TextColor3 = Color3.fromRGB(240, 240, 245)
	element.TextStrokeTransparency = 0.35
	element.TextXAlignment = Enum.TextXAlignment.Left
	element.Parent = parent
	return element
end

local function bar(parent, size, position, color)
	local back = Instance.new("Frame")
	back.Size = size
	back.Position = position
	back.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	back.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	return back, fill
end

-- сверху слева: задача
local objective = label(gui, "", UDim2.fromOffset(420, 28), UDim2.fromOffset(20, 16), 20)
local phaseLabel = label(gui, "", UDim2.fromOffset(420, 22), UDim2.fromOffset(20, 44), 15)
phaseLabel.TextColor3 = Color3.fromRGB(180, 185, 200)

-- рассудок
local sanityText = label(gui, "Рассудок", UDim2.fromOffset(240, 18), UDim2.new(0, 20, 1, -96), 13)
local _, sanityFill = bar(gui, UDim2.fromOffset(240, 12), UDim2.new(0, 20, 1, -78), Color3.fromRGB(150, 120, 230))

-- шум
local noiseText = label(gui, "Шум", UDim2.fromOffset(240, 18), UDim2.new(0, 20, 1, -58), 13)
local _, noiseFill = bar(gui, UDim2.fromOffset(240, 12), UDim2.new(0, 20, 1, -40), Color3.fromRGB(230, 170, 60))

-- выносливость
local _, staminaFill = bar(gui, UDim2.fromOffset(240, 8), UDim2.new(0, 20, 1, -22), Color3.fromRGB(110, 190, 255))

-- команда справа
local teamTitle = label(gui, "Команда", UDim2.fromOffset(220, 20), UDim2.new(1, -240, 0, 16), 15)
teamTitle.TextColor3 = Color3.fromRGB(180, 185, 200)
local teamLabels = {}
for index = 1, 4 do
	local element = label(gui, "", UDim2.fromOffset(220, 20), UDim2.new(1, -240, 0, 16 + index * 22), 15)
	teamLabels[index] = element
end

-- статус по центру
local statusLabel = label(gui, "", UDim2.fromOffset(600, 30), UDim2.new(0.5, -300, 0, 20), 22)
statusLabel.TextXAlignment = Enum.TextXAlignment.Center

local hintLabel = label(
	gui,
	"Shift - бег (громко)   |   C - красться (тихо)   |   F - фонарь (он это чувствует)   |   E - взаимодействие",
	UDim2.fromOffset(900, 20),
	UDim2.new(0.5, -450, 1, -24),
	13
)
hintLabel.TextXAlignment = Enum.TextXAlignment.Center
hintLabel.TextColor3 = Color3.fromRGB(150, 155, 170)

-- экран "ты упал"
local downFrame = Instance.new("Frame")
downFrame.Size = UDim2.fromScale(1, 1)
downFrame.BackgroundColor3 = Color3.fromRGB(60, 0, 0)
downFrame.BackgroundTransparency = 0.65
downFrame.BorderSizePixel = 0
downFrame.Visible = false
downFrame.ZIndex = 20
downFrame.Parent = gui

local downText = label(downFrame, "ТЫ УПАЛ", UDim2.fromScale(1, 0.1), UDim2.fromScale(0, 0.4), 36)
downText.TextXAlignment = Enum.TextXAlignment.Center
downText.ZIndex = 21
local _, bleedFill = bar(downFrame, UDim2.fromOffset(320, 14), UDim2.new(0.5, -160, 0.52, 0), Color3.fromRGB(220, 60, 60))
bleedFill.ZIndex = 21

-- Отдельный слой для сообщений: он работает и в лобби, когда HUD выключен.
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "HWC_Toasts"
toastGui.ResetOnSpawn = false
toastGui.IgnoreGuiInset = true
toastGui.DisplayOrder = 5
toastGui.Parent = player:WaitForChild("PlayerGui")

local toast = label(toastGui, "", UDim2.fromOffset(760, 28), UDim2.new(0.5, -380, 0.74, 0), 19)
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.TextTransparency = 1

local toastToken = 0

function Hud.toast(text: string, color: string?)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextColor3 = COLORS[color or "info"] or COLORS.info
	toast.TextTransparency = 0
	task.delay(3.5, function()
		if token == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		end
	end)
end

function Hud.setVisible(visible: boolean)
	gui.Enabled = visible
	if not visible then
		downFrame.Visible = false
	end
end

function Hud.setStamina(value: number, max: number)
	staminaFill.Size = UDim2.fromScale(math.clamp(value / max, 0, 1), 1)
end

function Hud.update(data)
	objective.Text = data.generatorOn and "ВОРОТА ОТКРЫТЫ - НА ЮГ"
		or string.format("Предохранители %d/%d", data.fuses, data.fusesRequired)

	if data.phase == "prep" then
		phaseLabel.Text = string.format("Тишина. ОН придёт через %d сек.", math.ceil(data.timeLeft))
		phaseLabel.TextColor3 = COLORS.good
	else
		phaseLabel.Text = data.generatorOn and "Бегите к воротам" or "ОН здесь. Ищите щитки."
		phaseLabel.TextColor3 = COLORS.bad
	end

	sanityFill.Size = UDim2.fromScale(math.clamp(data.sanity / data.sanityMax, 0, 1), 1)
	sanityText.Text = data.gazing and "Рассудок  (СМОТРИШЬ НА НЕГО)" or "Рассудок"
	sanityText.TextColor3 = data.gazing and COLORS.bad or Color3.fromRGB(200, 200, 215)

	noiseFill.Size = UDim2.fromScale(math.clamp(data.heat / data.heatMax, 0, 1), 1)
	noiseText.Text = data.hunted and "Шум  (ОН ИДЁТ ЗА ТОБОЙ)" or "Шум"
	noiseText.TextColor3 = data.hunted and COLORS.bad or Color3.fromRGB(200, 200, 215)

	if data.panic then
		statusLabel.Text = "ПАНИКА"
		statusLabel.TextColor3 = COLORS.bad
	elseif data.gazing then
		statusLabel.Text = "ДЕРЖИ ЕГО ВЗГЛЯДОМ"
		statusLabel.TextColor3 = Color3.fromRGB(255, 200, 90)
	elseif data.distance and data.distance < 25 then
		statusLabel.Text = "ОН РЯДОМ"
		statusLabel.TextColor3 = COLORS.bad
	else
		statusLabel.Text = ""
	end

	downFrame.Visible = data.downed == true
	if data.downed then
		bleedFill.Size = UDim2.fromScale(math.clamp(data.bleed / data.bleedMax, 0, 1), 1)
		downText.Text = string.format("ТЫ УПАЛ - %d сек", math.ceil(data.bleed))
	end

	local teammates = data.teammates or {}
	for index, element in teamLabels do
		local mate = teammates[index]
		if mate then
			local status = "в игре"
			local color = COLORS.good
			if mate.out then
				status = "потерян"
				color = Color3.fromRGB(120, 120, 130)
			elseif mate.escaped then
				status = "выбрался"
				color = Color3.fromRGB(120, 200, 255)
			elseif mate.downed then
				status = "УПАЛ"
				color = COLORS.bad
			end
			element.Text = string.format("%s - %s", mate.name, status)
			element.TextColor3 = color
		else
			element.Text = ""
		end
	end
end

return Hud
