--!nonstrict
-- HUD: ключи, стамина, команда, статус, экран "ты упал", всплывающие сообщения.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Hud = {}

local COLORS = {
	good = Color3.fromRGB(90, 220, 140),
	bad = Color3.fromRGB(255, 85, 85),
	info = Color3.fromRGB(205, 210, 225),
}

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

-- слой сообщений: работает и в лобби
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "HWC_Toasts"
toastGui.ResetOnSpawn = false
toastGui.IgnoreGuiInset = true
toastGui.DisplayOrder = 5
toastGui.Parent = playerGui

local toast = label(toastGui, "", UDim2.fromOffset(800, 30), UDim2.new(0.5, -400, 0.76, 0), 20)
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.TextTransparency = 1

-- HUD матча
local gui = Instance.new("ScreenGui")
gui.Name = "HWC_Hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

local objective = label(gui, "", UDim2.fromOffset(460, 30), UDim2.fromOffset(20, 16), 22)
local phaseLabel = label(gui, "", UDim2.fromOffset(460, 22), UDim2.fromOffset(20, 46), 15)
phaseLabel.TextColor3 = Color3.fromRGB(180, 185, 200)

local slideText = label(gui, "Подкат (C)", UDim2.fromOffset(260, 18), UDim2.new(0, 20, 1, -70), 13)
local _, slideFill = bar(gui, UDim2.fromOffset(260, 12), UDim2.new(0, 20, 1, -52), Color3.fromRGB(230, 180, 60))
local moveState = label(gui, "", UDim2.fromOffset(400, 18), UDim2.new(0, 20, 1, -34), 13)
moveState.TextColor3 = Color3.fromRGB(170, 175, 190)

local teamTitle = label(gui, "Команда", UDim2.fromOffset(240, 20), UDim2.new(1, -260, 0, 16), 15)
teamTitle.TextColor3 = Color3.fromRGB(180, 185, 200)
local teamLabels = {}
for index = 1, 4 do
	teamLabels[index] = label(gui, "", UDim2.fromOffset(240, 20), UDim2.new(1, -260, 0, 16 + index * 22), 15)
end

local statusLabel = label(gui, "", UDim2.fromOffset(700, 34), UDim2.new(0.5, -350, 0, 18), 24)
statusLabel.TextXAlignment = Enum.TextXAlignment.Center

local hint = label(
	gui,
	"Shift бег (бесконечный)  |  C подкат - пролезть в жёлтую щель, ОН туда не пролезет  |  F фонарь  |  E ключ / шкаф / поднять  |  T крик",
	UDim2.fromOffset(1000, 20),
	UDim2.new(0.5, -500, 1, -14),
	13
)
hint.TextXAlignment = Enum.TextXAlignment.Center
hint.TextColor3 = Color3.fromRGB(150, 155, 170)

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

local toastToken = 0

function Hud.toast(text, color)
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

function Hud.setVisible(visible)
	gui.Enabled = visible
	if not visible then
		downFrame.Visible = false
	end
end

function Hud.setMoveState(running, flashlight, slideReady)
	slideFill.Size = UDim2.fromScale(slideReady, 1)
	slideText.Text = slideReady >= 1 and "Подкат готов (C)" or "Подкат..."
	local parts = {}
	table.insert(parts, running and "БЕЖИШЬ (громко, слышно за 44 стада)" or "идёшь (тихо)")
	if flashlight then
		table.insert(parts, "фонарь ВКЛ - тебя видно за 100 стадов")
	end
	moveState.Text = table.concat(parts, "  |  ")
end

function Hud.update(data)
	objective.Text = data.gateOpen and "ДВЕРЬ ОТКРЫТА - вестибюль, южная стена"
		or string.format("Ключи %d/%d - светятся жёлтым на тумбах", data.keys, data.keysRequired)

	if data.phase == "prep" then
		phaseLabel.Text = string.format("Тихо. ОН проснётся через %d сек.", math.ceil(data.timeLeft))
		phaseLabel.TextColor3 = COLORS.good
	else
		phaseLabel.Text = "ОН ходит по дому"
		phaseLabel.TextColor3 = COLORS.bad
	end

	if data.hidden then
		statusLabel.Text = "ТЫ В ШКАФУ. E - выйти"
		statusLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
	elseif data.hunted then
		statusLabel.Text = "ОН БЕЖИТ ЗА ТОБОЙ - ПОДКАТ В ЩЕЛЬ ИЛИ В ШКАФ"
		statusLabel.TextColor3 = COLORS.bad
	elseif data.distance and data.distance < 22 then
		statusLabel.Text = "ОН РЯДОМ"
		statusLabel.TextColor3 = COLORS.bad
	elseif data.distance and data.distance < 45 then
		statusLabel.Text = "слышны шаги..."
		statusLabel.TextColor3 = Color3.fromRGB(230, 170, 60)
	else
		statusLabel.Text = ""
	end

	downFrame.Visible = data.downed == true
	if data.downed then
		bleedFill.Size = UDim2.fromScale(math.clamp(data.bleed / data.bleedMax, 0, 1), 1)
		downText.Text = string.format("ТЫ УПАЛ - %d сек. Кричи T, чтобы тебя нашли", math.ceil(data.bleed))
	end

	local teammates = data.teammates or {}
	for index, element in teamLabels do
		local mate = teammates[index]
		if mate then
			local status, color = "в игре", COLORS.good
			if mate.out then
				status, color = "потерян", Color3.fromRGB(120, 120, 130)
			elseif mate.escaped then
				status, color = "выбрался", Color3.fromRGB(120, 200, 255)
			elseif mate.downed then
				status, color = "УПАЛ", COLORS.bad
			elseif mate.hidden then
				status, color = "прячется", Color3.fromRGB(150, 200, 255)
			end
			element.Text = string.format("%s - %s", mate.name, status)
			element.TextColor3 = color
		else
			element.Text = ""
		end
	end
end

return Hud
