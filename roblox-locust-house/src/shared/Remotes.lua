--!nonstrict
-- Один модуль на все Remote-события. Сервер их создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENT_NAMES = {
	"Taunt",        -- клиент -> сервер: подразнить монстра
	"ThrowBait",    -- клиент -> сервер: бросить приманку
	"Slide",        -- клиент -> сервер: сообщить про подкат (шум)
	"StateSync",    -- сервер -> клиент: ярость, множитель, ключи, приманки
	"Notify",       -- сервер -> клиент: текст на экран
	"Jumpscare",    -- сервер -> клиент: поймали
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("LocustRemotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "LocustRemotes"
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
	folder = ReplicatedStorage:WaitForChild("LocustRemotes") :: Folder
end

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
