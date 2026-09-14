--!nonstrict
-- Точка входа клиента.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LocustShared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local Hud = require(script.Parent:WaitForChild("Hud"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))
local ActionController = require(script.Parent:WaitForChild("ActionController"))
local Effects = require(script.Parent:WaitForChild("Effects"))

MovementController.start(Hud)
ActionController.start()
Effects.start()

Remotes.get("StateSync").OnClientEvent:Connect(function(data)
	Hud.setState(data)
	Effects.setRage(data.rage)
end)

Remotes.get("Notify").OnClientEvent:Connect(function(text: string, color: string?)
	Hud.toast(text, color)
end)

Remotes.get("Jumpscare").OnClientEvent:Connect(function()
	Effects.jumpscare(Hud.getGui())
end)

Hud.toast("Найди ключи, не попадись. Дразнить монстра - кнопка T.", "info")
