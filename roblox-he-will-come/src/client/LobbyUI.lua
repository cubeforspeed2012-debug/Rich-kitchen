--!nonstrict
-- Окно лобби: список комнат, создать / войти / выйти / старт.

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
panel.Size = UDim2.fromOffset(540, 440)
panel.Position = UDim2.new(0.5, -270, 0.5, -220)
panel.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(130, 30, 30)
stroke.Thickness = 2
stroke.Parent = panel

local function text(parent, str, size, position, textSize, color)
	local element = Instance.new("TextLabel")
	element.Size = size
	element.Position = position
	element.BackgroundTransparency = 1
	element.Text = str
	element.Font = Enum.Font.GothamBold
	element.TextSize = textSize
	element.TextColor3 = color or Color3.fromRGB(235, 235, 240)
	element.TextXAlignment = Enum.TextXAlignment.Left
	element.TextWrapped = true
	element.Parent = parent
	return element
end

text(panel, "HE WILL COME", UDim2.new(1, -24, 0, 40), UDim2.fromOffset(14, 10), 28, Color3.fromRGB(220, 50, 50))
local subtitle = text(panel, "", UDim2.new(1, -24, 0, 36), UDim2.fromOffset(14, 50), 14, Color3.fromRGB(170, 170, 185))

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -28, 0, 236)
list.Position = UDim2.fromOffset(14, 92)
list.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
list.BackgroundTransparency = 0.3
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
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

local empty = text(list, "Комнат пока нет. Создай первую.", UDim2.new(1, -12, 0, 40), UDim2.new(), 15, Color3.fromRGB(140, 140, 155))

local function button(parent, str, size, position, color)
	local element = Instance.new("TextButton")
	element.Size = size
	element.Position = position
	element.BackgroundColor3 = color
	element.BorderSizePixel = 0
	element.Text = str
	element.Font = Enum.Font.GothamBold
	element.TextSize = 16
	element.TextColor3 = Color3.fromRGB(255, 255, 255)
	element.AutoButtonColor = true
	element.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = element
	return element
end

local createButton = button(panel, "Создать комнату", UDim2.fromOffset(250, 40), UDim2.fromOffset(14, 340), Color3.fromRGB(50, 95, 60))
local leaveButton = button(panel, "Выйти из комнаты", UDim2.fromOffset(250, 40), UDim2.fromOffset(276, 340), Color3.fromRGB(75, 40, 40))
local startButton = button(panel, "НАЧАТЬ ИГРУ", UDim2.fromOffset(512, 40), UDim2.fromOffset(14, 388), Color3.fromRGB(160, 35, 35))

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

function LobbyUI.update(data)
	for _, row in rows do
		row:Destroy()
	end
	table.clear(rows)

	local roomsData = data.rooms or {}
	local myRoom = data.myRoom or 0
	empty.Visible = #roomsData == 0

	for index, room in roomsData do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 56)
		row.BackgroundColor3 = room.id == myRoom and Color3.fromRGB(45, 65, 45) or Color3.fromRGB(30, 30, 38)
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = list
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row

		local names = table.concat(room.players or {}, ", ")
		local state = room.state == "playing" and "  [идёт игра]" or ""
		text(row, string.format("Комната #%d  -  %d/%d%s\n%s", room.id, room.count, room.max, state, names), UDim2.new(1, -120, 1, 0), UDim2.fromOffset(12, 0), 15)

		if myRoom == 0 and room.state == "waiting" and room.count < room.max then
			local join = button(row, "Войти", UDim2.fromOffset(96, 36), UDim2.new(1, -106, 0.5, -18), Color3.fromRGB(55, 75, 115))
			join.Activated:Connect(function()
				roomAction:FireServer({ action = "join", roomId = room.id })
			end)
		end
		table.insert(rows, row)
	end

	createButton.Visible = myRoom == 0
	leaveButton.Visible = myRoom ~= 0
	startButton.Visible = data.isHost == true
	if myRoom ~= 0 then
		subtitle.Text = string.format("Ты в комнате #%d. Максимум %d игрока. Хозяин жмёт СТАРТ.", myRoom, data.maxPlayers or 4)
	else
		subtitle.Text = string.format("Комнаты до %d человек. Создай свою или зайди к другим.", data.maxPlayers or 4)
	end
end

function LobbyUI.setVisible(visible)
	gui.Enabled = visible
end

return LobbyUI
