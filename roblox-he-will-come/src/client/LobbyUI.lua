--!nonstrict
-- Интерфейс лобби: список комнат, создать / войти / выйти / старт.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local roomAction = Remotes.get("RoomAction")

local LobbyUI = {}

local gui = Instance.new("ScreenGui")
gui.Name = "HWC_Lobby"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(520, 420)
panel.Position = UDim2.new(0.5, -260, 0.5, -210)
panel.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(120, 30, 30)
stroke.Thickness = 2
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 42)
title.Position = UDim2.fromOffset(12, 10)
title.BackgroundTransparency = 1
title.Text = "HE WILL COME"
title.Font = Enum.Font.GothamBlack
title.TextSize = 28
title.TextColor3 = Color3.fromRGB(220, 50, 50)
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -24, 0, 20)
subtitle.Position = UDim2.fromOffset(12, 50)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Комнаты до 4 человек. Создай свою или зайди к другим."
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 14
subtitle.TextColor3 = Color3.fromRGB(170, 170, 185)
subtitle.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 0, 240)
list.Position = UDim2.fromOffset(12, 78)
list.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
list.BackgroundTransparency = 0.3
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 6)
padding.Parent = list

local empty = Instance.new("TextLabel")
empty.Size = UDim2.new(1, -12, 0, 40)
empty.BackgroundTransparency = 1
empty.Text = "Комнат пока нет. Создай первую."
empty.Font = Enum.Font.Gotham
empty.TextSize = 15
empty.TextColor3 = Color3.fromRGB(140, 140, 155)
empty.Parent = list

local function makeButton(text: string, position: UDim2, size: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.AutoButtonColor = true
	button.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

local createButton = makeButton("Создать комнату", UDim2.fromOffset(12, 330), UDim2.fromOffset(240, 38), Color3.fromRGB(50, 90, 60))
local leaveButton = makeButton("Выйти из комнаты", UDim2.fromOffset(268, 330), UDim2.fromOffset(240, 38), Color3.fromRGB(70, 40, 40))
local startButton = makeButton("НАЧАТЬ ИГРУ", UDim2.fromOffset(12, 374), UDim2.fromOffset(496, 36), Color3.fromRGB(150, 35, 35))

createButton.Activated:Connect(function()
	roomAction:FireServer({ action = "create" })
end)
leaveButton.Activated:Connect(function()
	roomAction:FireServer({ action = "leave" })
end)
startButton.Activated:Connect(function()
	roomAction:FireServer({ action = "start" })
end)

local rows = {}

local function clearRows()
	for _, row in rows do
		row:Destroy()
	end
	table.clear(rows)
end

function LobbyUI.update(data)
	clearRows()

	local roomsData = data.rooms or {}
	empty.Visible = #roomsData == 0

	for index, room in roomsData do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 54)
		row.BackgroundColor3 = room.id == data.myRoom and Color3.fromRGB(45, 60, 45) or Color3.fromRGB(30, 30, 38)
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = list

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -110, 1, 0)
		label.Position = UDim2.fromOffset(12, 0)
		label.BackgroundTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Font = Enum.Font.GothamBold
		label.TextSize = 15
		label.TextColor3 = Color3.fromRGB(235, 235, 240)
		label.Text = string.format(
			"Комната #%d  -  %d/%d\n%s%s",
			room.id,
			room.count,
			room.max,
			table.concat(room.players, ", "),
			room.state == "playing" and "   [идёт игра]" or ""
		)
		label.Parent = row

		if room.id ~= data.myRoom and room.state == "waiting" and room.count < room.max and not data.myRoom then
			local joinButton = Instance.new("TextButton")
			joinButton.Size = UDim2.fromOffset(90, 34)
			joinButton.Position = UDim2.new(1, -100, 0.5, -17)
			joinButton.BackgroundColor3 = Color3.fromRGB(55, 75, 110)
			joinButton.BorderSizePixel = 0
			joinButton.Text = "Войти"
			joinButton.Font = Enum.Font.GothamBold
			joinButton.TextSize = 15
			joinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
			joinButton.Parent = row

			local joinCorner = Instance.new("UICorner")
			joinCorner.CornerRadius = UDim.new(0, 6)
			joinCorner.Parent = joinButton

			joinButton.Activated:Connect(function()
				roomAction:FireServer({ action = "join", roomId = room.id })
			end)
		end

		table.insert(rows, row)
	end

	createButton.Visible = data.myRoom == nil
	leaveButton.Visible = data.myRoom ~= nil
	startButton.Visible = data.isHost == true
	subtitle.Text = data.myRoom
			and string.format("Ты в комнате #%d. Максимум %d игрока(ов).", data.myRoom, data.maxPlayers or 4)
		or string.format("Комнаты до %d человек. Создай свою или зайди к другим.", data.maxPlayers or 4)
end

function LobbyUI.setVisible(visible: boolean)
	gui.Enabled = visible
end

return LobbyUI
