--!nonstrict
-- Общий список Remote-событий лобби и матча.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENT_NAMES = {
	-- лобби
	"RoomAction",   -- клиент -> сервер: {action = "create"/"join"/"leave"/"start", roomId = n}
	"RoomList",     -- сервер -> клиент: список комнат
	-- матч
	"MatchSync",    -- сервер -> клиент: состояние матча и игрока
	"GazeReport",   -- клиент -> сервер: куда смотрит камера
	"Notify",       -- сервер -> клиент: текст
	"Scare",        -- сервер -> клиент: он тебя достал
	"Crouch",       -- клиент -> сервер: приседание (влияет на шум)
	"Flashlight",   -- клиент -> сервер: фонарь включён/выключен
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("HWCRemotes")
	if existing then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "HWCRemotes"
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
	folder = ReplicatedStorage:WaitForChild("HWCRemotes")
end

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name)
end

return Remotes
