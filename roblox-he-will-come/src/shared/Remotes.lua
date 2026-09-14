--!nonstrict
-- Все Remote-события в одном месте. Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "HWCRemotes"

local EVENT_NAMES = {
	"RoomAction",   -- клиент -> сервер: { action = "create" | "join" | "leave" | "start" | "refresh", roomId = n }
	"RoomList",     -- сервер -> клиент: список комнат
	"MatchSync",    -- сервер -> клиент: состояние матча
	"PlayerAction", -- клиент -> сервер: { action = "slide" | "shout" | "flashlight" | "crouch", value = ... }
	"Notify",       -- сервер -> клиент: текст на экран
	"Effect",       -- сервер -> клиент: "arrival" | "scream" | "down" | "revived" | "out" | "escaped" | "key"
}

local Remotes = {}

local folder

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end
else
	-- ждём не бесконечно: если сервер упал, клиент должен показать ошибку, а не висеть
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 20)
	if not folder then
		error("Папка " .. FOLDER_NAME .. " не появилась за 20 секунд. Серверный скрипт не запустился - смотри Output.")
	end
end

function Remotes.get(name: string): RemoteEvent
	local event = folder:WaitForChild(name, 10)
	if not event then
		error("Нет RemoteEvent с именем " .. name)
	end
	return event
end

return Remotes
