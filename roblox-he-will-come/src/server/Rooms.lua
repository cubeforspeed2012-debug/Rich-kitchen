--!nonstrict
-- Комнаты лобби: создать / войти / выйти / старт. Не больше 4 человек.
-- Каждая запущенная комната получает свою школу в стороне и своего монстра.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local Monster = require(script.Parent:WaitForChild("Monster"))
local Match = require(script.Parent:WaitForChild("Match"))

local ROOMS = GameConfig.Rooms

local roomListEvent = Remotes.get("RoomList")
local notifyEvent = Remotes.get("Notify")

local Rooms = {}
Rooms.__index = Rooms

function Rooms.new(lobby, monsterCollisionGroup)
	local self = setmetatable({}, Rooms)
	self.lobby = lobby
	self.monsterCollisionGroup = monsterCollisionGroup
	self.rooms = {}
	self.nextId = 1
	self.slots = {}
	for index = 1, ROOMS.MaxRooms do
		self.slots[index] = false
	end
	return self
end

function Rooms:_notify(player, text, color)
	notifyEvent:FireClient(player, text, color)
end

function Rooms:findRoomOf(player)
	for _, room in self.rooms do
		if table.find(room.players, player) then
			return room
		end
	end
	return nil
end

function Rooms:getMatchOf(player)
	local room = self:findRoomOf(player)
	return room and room.match or nil
end

function Rooms:_freeSlot()
	for index, busy in self.slots do
		if not busy then
			return index
		end
	end
	return nil
end

function Rooms:broadcast()
	local list = {}
	for _, room in self.rooms do
		local names = {}
		for _, player in room.players do
			table.insert(names, player.DisplayName)
		end
		table.insert(list, {
			id = room.id,
			host = room.host and room.host.DisplayName or "?",
			count = #room.players,
			max = ROOMS.MaxPlayers,
			state = room.state,
			players = names,
		})
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)

	for _, player in Players:GetPlayers() do
		local room = self:findRoomOf(player)
		roomListEvent:FireClient(player, {
			rooms = list,
			myRoom = room and room.id or 0,
			isHost = room ~= nil and room.host == player,
			maxPlayers = ROOMS.MaxPlayers,
		})
	end
end

function Rooms:create(player)
	if self:findRoomOf(player) then
		self:_notify(player, "Ты уже в комнате", "bad")
		return
	end
	if #self.rooms >= ROOMS.MaxRooms then
		self:_notify(player, "Все комнаты на сервере заняты", "bad")
		return
	end
	local room = { id = self.nextId, host = player, players = { player }, state = "waiting" }
	self.nextId += 1
	table.insert(self.rooms, room)
	self:_notify(player, string.format("Комната #%d создана. Жми СТАРТ, когда все соберутся.", room.id), "good")
	self:broadcast()
end

function Rooms:join(player, roomId)
	if self:findRoomOf(player) then
		self:_notify(player, "Сначала выйди из своей комнаты", "bad")
		return
	end
	for _, room in self.rooms do
		if room.id == roomId then
			if room.state ~= "waiting" then
				self:_notify(player, "Там уже идёт игра", "bad")
				return
			end
			if #room.players >= ROOMS.MaxPlayers then
				self:_notify(player, string.format("В комнате уже %d - больше нельзя", ROOMS.MaxPlayers), "bad")
				return
			end
			table.insert(room.players, player)
			self:_notify(player, string.format("Ты в комнате #%d", room.id), "good")
			self:broadcast()
			return
		end
	end
	self:_notify(player, "Комнаты уже нет", "bad")
end

function Rooms:leave(player)
	local room = self:findRoomOf(player)
	if not room then
		return
	end
	local index = table.find(room.players, player)
	if index then
		table.remove(room.players, index)
	end
	if room.match then
		room.match:playerLeft(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = false
			root.CFrame = CFrame.new(self.lobby.SpawnPosition)
		end
	end
	if room.host == player then
		room.host = room.players[1]
	end
	if #room.players == 0 then
		self:_destroyRoom(room)
	end
	self:broadcast()
end

function Rooms:start(player)
	local room = self:findRoomOf(player)
	if not room then
		self:_notify(player, "Сначала создай комнату", "bad")
		return
	end
	if room.host ~= player then
		self:_notify(player, "Запустить может только хозяин комнаты", "bad")
		return
	end
	if room.state ~= "waiting" then
		return
	end
	local slot = self:_freeSlot()
	if not slot then
		self:_notify(player, "Нет свободной арены, подожди", "bad")
		return
	end

	self.slots[slot] = true
	room.slot = slot
	room.state = "playing"

	local origin = ROOMS.ArenaBaseOffset + Vector3.new(ROOMS.ArenaSpacing * (slot - 1), 0, 0)
	room.arena = MapBuilder.build(origin, slot)
	room.monster = Monster.new(room.arena, self.monsterCollisionGroup)

	local participants = table.clone(room.players)
	room.match = Match.new(room.arena, room.monster, participants, self.lobby.SpawnPosition, function()
		task.delay(GameConfig.Match.EndScreenTime, function()
			self:_endMatch(room)
		end)
	end)
	room.match:start()
	self:broadcast()
end

function Rooms:_endMatch(room)
	if room.monster then
		room.monster:destroy()
		room.monster = nil
	end
	if room.arena and room.arena.Model then
		room.arena.Model:Destroy()
	end
	room.arena = nil
	room.match = nil
	if room.slot then
		self.slots[room.slot] = false
		room.slot = nil
	end
	room.state = "waiting"
	if #room.players == 0 then
		self:_destroyRoom(room)
	end
	self:broadcast()
end

function Rooms:_destroyRoom(room)
	if room.match and not room.match.finished then
		room.match:finish("lose")
	end
	if room.monster then
		room.monster:destroy()
		room.monster = nil
	end
	if room.arena and room.arena.Model then
		room.arena.Model:Destroy()
		room.arena = nil
	end
	if room.slot then
		self.slots[room.slot] = false
		room.slot = nil
	end
	local index = table.find(self.rooms, room)
	if index then
		table.remove(self.rooms, index)
	end
end

function Rooms:handleAction(player, payload)
	if typeof(payload) ~= "table" then
		return
	end
	local action = payload.action
	if action == "create" then
		self:create(player)
	elseif action == "join" then
		if typeof(payload.roomId) == "number" then
			self:join(player, payload.roomId)
		end
	elseif action == "leave" then
		self:leave(player)
	elseif action == "start" then
		self:start(player)
	elseif action == "refresh" then
		self:broadcast()
	end
end

return Rooms
