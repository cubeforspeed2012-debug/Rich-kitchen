--!nonstrict
-- HE WILL COME - точка входа клиента.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local LobbyUI = require(script.Parent:WaitForChild("LobbyUI"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local Movement = require(script.Parent:WaitForChild("Movement"))
local Gaze = require(script.Parent:WaitForChild("Gaze"))
local Effects = require(script.Parent:WaitForChild("Effects"))

Movement.start(Hud)
Gaze.start()
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
			Movement.setBlocked(false)
		end
		return
	end

	if not inMatch then
		inMatch = true
		Hud.setVisible(true)
		LobbyUI.setVisible(false)
	end

	Hud.update(data)
	Effects.setSanity(data.sanity, data.sanityMax)
	Movement.setBlocked(data.panic == true or data.downed == true)
end)

Remotes.get("Notify").OnClientEvent:Connect(function(text: string, color: string?)
	Hud.toast(text, color)
end)

Remotes.get("Scare").OnClientEvent:Connect(function(kind: string)
	Effects.scare(kind)
end)

-- просим сервер прислать список комнат сразу после входа
Remotes.get("RoomAction"):FireServer({ action = "refresh" })
