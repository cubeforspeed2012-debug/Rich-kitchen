--!nonstrict
-- HE WILL COME v2 - точка входа клиента.
-- Если что-то падает, ошибка показывается прямо на экране, а не прячется в Output.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function showFatal(message)
	warn("[HE WILL COME] " .. message)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HWC_Error"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.Parent = player:WaitForChild("PlayerGui")
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -40, 0, 120)
	label.Position = UDim2.fromOffset(20, 20)
	label.BackgroundColor3 = Color3.fromRGB(60, 0, 0)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(255, 220, 220)
	label.TextWrapped = true
	label.TextSize = 16
	label.Font = Enum.Font.Code
	label.Text = "ОШИБКА КЛИЕНТА (скинь этот текст):\n" .. message
	label.Parent = gui
end

local ok, err = pcall(function()
	local Shared = ReplicatedStorage:WaitForChild("HWCShared", 20)
	if not Shared then
		error("Нет папки HWCShared в ReplicatedStorage")
	end
	local Remotes = require(Shared:WaitForChild("Remotes"))

	local LobbyUI = require(script.Parent:WaitForChild("LobbyUI"))
	local Hud = require(script.Parent:WaitForChild("Hud"))
	local Input = require(script.Parent:WaitForChild("Input"))
	local Effects = require(script.Parent:WaitForChild("Effects"))

	Input.start(Hud)
	Effects.start()

	local inMatch = false

	Remotes.get("RoomList").OnClientEvent:Connect(function(data)
		LobbyUI.update(data)
	end)

	Remotes.get("MatchSync").OnClientEvent:Connect(function(data)
		if not data.inMatch then
			if inMatch then
				inMatch = false
				Hud.setVisible(false)
				LobbyUI.setVisible(true)
				Effects.reset()
			end
			return
		end
		if not inMatch then
			inMatch = true
			Hud.setVisible(true)
			LobbyUI.setVisible(false)
		end
		Hud.update(data)
		Effects.setDistance(data.distance or 999, data.hunted == true)
	end)

	Remotes.get("Notify").OnClientEvent:Connect(function(str, color)
		Hud.toast(str, color)
	end)

	Remotes.get("Effect").OnClientEvent:Connect(function(kind, data)
		Effects.play(kind, data)
	end)

	Remotes.get("RoomAction"):FireServer({ action = "refresh" })
	print("[HE WILL COME] клиент запущен")
end)

if not ok then
	showFatal(tostring(err))
end
