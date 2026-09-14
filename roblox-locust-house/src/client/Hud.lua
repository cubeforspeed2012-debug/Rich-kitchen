--!nonstrict
-- Весь интерфейс рисуется кодом: полоски стамины и ярости, множитель,
-- ключи, приманки и всплывающие подсказки.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Hud = {}

local COLORS = {
	good = Color3.fromRGB(90, 220, 140),
	bad = Color3.fromRGB(255, 90, 90),
	info = Color3.fromRGB(200, 210, 230),
	rage = Color3.fromRGB(255, 170, 60),
}

local gui = Instance.new("ScreenGui")
gui.Name = "LocustHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local element = Instance.new("TextLabel")
	element.BackgroundTransparency = 1
	element.Size = size
	element.Position = position
	element.Text = text
	element.TextSize = textSize
	element.Font = Enum.Font.GothamBold
	element.TextColor3 = Color3.fromRGB(240, 240, 245)
	element.TextStrokeTransparency = 0.4
	element.TextXAlignment = Enum.TextXAlignment.Left
	element.Parent = parent
	return element
end

local function bar(parent: Instance, size: UDim2, position: UDim2, color: Color3): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Size = size
	back.Position = position
	back.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	back.BackgroundTransparency = 0.35
	back.BorderSizePixel = 0
	back.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	return back, fill
end

-- Задача раунда
local objective = label(gui, "Ключи 0/4", UDim2.fromOffset(360, 30), UDim2.fromOffset(20, 18), 22)
local hint = label(gui, "Найди ключи и беги к красной двери на севере", UDim2.fromOffset(460, 24), UDim2.fromOffset(20, 46), 15)
hint.TextColor3 = Color3.fromRGB(180, 185, 200)

-- Ярость монстра (главная механика)
local rageTitle = label(gui, "ЯРОСТЬ САРАНЧИ", UDim2.fromOffset(300, 22), UDim2.new(0.5, -150, 0, 16), 16)
rageTitle.TextXAlignment = Enum.TextXAlignment.Center
local _, rageFill = bar(gui, UDim2.fromOffset(300, 14), UDim2.new(0.5, -150, 0, 40), COLORS.rage)
local multiplierLabel = label(gui, "x1.00", UDim2.fromOffset(300, 26), UDim2.new(0.5, -150, 0, 58), 20)
multiplierLabel.TextXAlignment = Enum.TextXAlignment.Center
multiplierLabel.TextColor3 = COLORS.rage

-- Стамина
local _, staminaFill = bar(gui, UDim2.fromOffset(260, 12), UDim2.new(0, 20, 1, -54), Color3.fromRGB(120, 200, 255))
local staminaLabel = label(gui, "Выносливость", UDim2.fromOffset(260, 20), UDim2.new(0, 20, 1, -76), 14)
staminaLabel.TextColor3 = Color3.fromRGB(170, 200, 230)

-- Приманки и управление
local baitLabel = label(gui, "Приманки: 3", UDim2.fromOffset(300, 24), UDim2.new(0, 20, 1, -100), 17)
local keysHint = label(
	gui,
	"Shift - бег   |   C - подкат (пролезть в лаз)   |   Q - приманка   |   T - ПОДРАЗНИТЬ   |   F - фонарь",
	UDim2.fromOffset(900, 22),
	UDim2.new(0, 20, 1, -26),
	14
)
keysHint.TextColor3 = Color3.fromRGB(150, 155, 170)

-- Индикатор близости монстра
local dangerLabel = label(gui, "", UDim2.fromOffset(300, 26), UDim2.new(0.5, -150, 0, 88), 18)
dangerLabel.TextXAlignment = Enum.TextXAlignment.Center

-- Тосты
local toast = label(gui, "", UDim2.fromOffset(700, 30), UDim2.new(0.5, -350, 0.72, 0), 20)
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.TextTransparency = 1

-- Красная рамка опасности
local vignette = Instance.new("Frame")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
vignette.BackgroundTransparency = 1
vignette.BorderSizePixel = 0
vignette.ZIndex = 0
vignette.Parent = gui

local toastToken = 0

function Hud.toast(text: string, color: string?)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextColor3 = COLORS[color or "info"] or COLORS.info
	toast.TextTransparency = 0
	task.delay(3, function()
		if token == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		end
	end)
end

function Hud.setStamina(value: number, max: number)
	staminaFill.Size = UDim2.fromScale(math.clamp(value / max, 0, 1), 1)
	staminaFill.BackgroundColor3 = value < 20 and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(120, 200, 255)
end

function Hud.setState(data)
	objective.Text = string.format("Ключи %d/%d", data.keys, data.keysTotal)
	hint.Text = data.locked and "Найди все ключи, потом красная дверь на севере"
		or "ВЫХОД ОТКРЫТ! Беги на север!"

	rageFill.Size = UDim2.fromScale(math.clamp(data.rage / 100, 0, 1), 1)
	if data.rage >= 80 then
		rageTitle.Text = "!!! ЯРОСТЬ !!!"
		rageTitle.TextColor3 = Color3.fromRGB(255, 90, 60)
		rageFill.BackgroundColor3 = Color3.fromRGB(255, 70, 50)
	elseif data.rage >= 40 then
		rageTitle.Text = "САРАНЧА ЗЛИТСЯ"
		rageTitle.TextColor3 = COLORS.rage
		rageFill.BackgroundColor3 = COLORS.rage
	else
		rageTitle.Text = "ЯРОСТЬ САРАНЧИ"
		rageTitle.TextColor3 = Color3.fromRGB(210, 210, 220)
		rageFill.BackgroundColor3 = Color3.fromRGB(160, 160, 170)
	end

	multiplierLabel.Text = string.format("x%.2f   банк: %d", data.multiplier, data.bank)
	baitLabel.Text = string.format("Приманки: %d", data.baits)

	local distance = data.distance or 999
	if distance < 18 then
		dangerLabel.Text = "ОН ПРЯМО ЗДЕСЬ"
		dangerLabel.TextColor3 = COLORS.bad
	elseif distance < 40 then
		dangerLabel.Text = "он рядом..."
		dangerLabel.TextColor3 = COLORS.rage
	elseif distance < 70 then
		dangerLabel.Text = "слышны шаги"
		dangerLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	else
		dangerLabel.Text = ""
	end

	local danger = math.clamp(1 - distance / 40, 0, 1) * 0.45
	vignette.BackgroundTransparency = 1 - danger
end

function Hud.getGui(): ScreenGui
	return gui
end

return Hud
